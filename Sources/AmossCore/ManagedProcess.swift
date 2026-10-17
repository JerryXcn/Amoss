import Foundation
import Darwin

public enum ProcessEvent: Sendable {
    case output(Data)
    case exited(Int32)
}

/// A single owner for each child process. A pipe reader drains output continuously;
/// stopping never touches other scrcpy instances or the shared ADB server.
public final class ManagedProcess: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var finished = false
    public let events: AsyncStream<ProcessEvent>
    public var pid: Int32 { process.processIdentifier }

    public init(executable: URL, arguments: [String], environment: [String: String]? = nil) throws {
        let child = Process()
        child.executableURL = executable
        child.arguments = arguments
        child.environment = environment
        child.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        child.standardOutput = pipe
        child.standardError = pipe
        process = child
        let (stream, continuation) = AsyncStream<ProcessEvent>.makeStream()
        events = stream
        // Install completion before launch. waitUntilExit() can miss a fast
        // child's completion when used from a different worker run loop while
        // AppKit is tracking menus, leaving exited ADB commands waiting forever.
        let termination = DispatchSemaphore(value: 0)
        child.terminationHandler = { _ in termination.signal() }
        try child.run()
        // The child inherited a write descriptor; close the parent's copy so EOF
        // is delivered when the child exits, including early launch failures.
        try? pipe.fileHandleForWriting.close()
        continuation.onTermination = { [weak self] _ in self?.stop() }
        DispatchQueue.global(qos: .utility).async { [self] in
            while true {
                let data = pipe.fileHandleForReading.availableData
                if data.isEmpty { break }
                continuation.yield(.output(data))
            }
            try? pipe.fileHandleForReading.close()
            termination.wait()
            lock.withLock { finished = true }
            continuation.yield(.exited(child.terminationStatus))
            continuation.finish()
        }
    }

    public func stop() {
        lock.withLock {
            if !finished && process.isRunning { process.terminate() }
        }
        // A hung encoder must not leave an orphan after Cancel or application quit.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) { [self] in
            lock.withLock {
                if !finished && process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
            }
        }
    }
}

public struct CommandResult: Sendable {
    public let output: String
    public let exitCode: Int32
}

public enum CommandError: LocalizedError {
    case timeout
    case noResult
    public var errorDescription: String? {
        switch self {
        case .timeout: L10n.text("连接超时，请检查设备后重试。")
        case .noResult: L10n.text("工具未返回结果。")
        }
    }
}

public enum CommandRunner {
    public static func run(_ executable: URL, _ arguments: [String],
                           environment: [String: String]? = nil,
                           timeout: Duration = .seconds(8)) async throws -> CommandResult {
        try Task.checkCancellation()
        let child = try ManagedProcess(executable: executable, arguments: arguments, environment: environment)
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: CommandResult.self) { group in
                group.addTask {
                    var output = Data()
                    for await event in child.events {
                        try Task.checkCancellation()
                        switch event {
                        case .output(let data):
                            output.append(data)
                            if output.count > 262_144 { output.removeFirst(output.count - 262_144) }
                        case .exited(let code):
                            return CommandResult(output: String(decoding: output, as: UTF8.self), exitCode: code)
                        }
                    }
                    try Task.checkCancellation()
                    throw CommandError.noResult
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    child.stop()
                    throw CommandError.timeout
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw CommandError.noResult }
                return result
            }
        } onCancel: { child.stop() }
    }
}
