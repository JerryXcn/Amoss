import Foundation
import Network

public enum ClipboardSessionEvent: Sendable {
    case ready
    case text(String)
    case sent
    case ended(String?)
}

/// One USB device, one control-only server. This does not launch the SDL helper,
/// create a window, wake the display, inject input, or capture video/audio.
@MainActor
public final class ClipboardSession {
    public let events: AsyncStream<ClipboardSessionEvent>
    public private(set) var isStopped = false
    private let continuation: AsyncStream<ClipboardSessionEvent>.Continuation
    private let tools: Toolchain
    private let device: AndroidDevice
    private let token = String(format: "%08x", UInt32.random(in: 1...0x7fffffff))
    private let remotePath = "/data/local/tmp/amoss-clipboard-\(UUID().uuidString.lowercased()).jar"
    private var setupTask: Task<Void, Never>?
    private var readerTask: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var server: ManagedProcess?
    private var connection: NWConnection?
    private var port: UInt16?
    private var decoder = ClipboardProtocol.Decoder()
    private var connected = false
    private var stopping = false
    private var attempts = 0
    private var sequence: UInt64 = 0
    private var awaitingAck: UInt64?
    private var pendingText: String?
    private var ackDeadline: Task<Void, Never>?
    private var echoes = ClipboardEchoFilter()

    public init(device: AndroidDevice, tools: Toolchain) {
        self.device = device
        self.tools = tools
        (events, continuation) = AsyncStream.makeStream()
        setupTask = Task { [weak self] in await self?.prepare() }
    }

    public func send(_ text: String) throws {
        guard text.utf8.count <= ClipboardProtocol.maximumTextBytes else { throw ClipboardProtocolError.textTooLong }
        guard !stopping else { return }
        // Bound queued clipboard memory even when somebody copies repeatedly
        // during a slow USB connection. Only the newest pending copy matters.
        pendingText = text
        flush()
    }

    public func stop() { finish(nil) }

    private func command(_ arguments: [String], timeout: Duration = .seconds(8)) async throws -> CommandResult {
        let result = try await CommandRunner.run(tools.adb, device.selector + arguments,
                                                  environment: tools.environment, timeout: timeout)
        guard result.exitCode == 0 else { throw ClipboardProtocolError.unavailable }
        return result
    }

    private func prepare() async {
        do {
            _ = try await command(["push", tools.server.path, remotePath])
            try Task.checkCancellation()
            let forwarded = try await command(["forward", "tcp:0", "localabstract:scrcpy_\(token)"])
            guard let port = UInt16(forwarded.output.trimmingCharacters(in: .whitespacesAndNewlines)), port > 0 else {
                throw ClipboardProtocolError.unavailable
            }
            self.port = port
            try Task.checkCancellation()
            let arguments = device.selector + ["shell", "CLASSPATH=\(remotePath)", "app_process", "/",
                "com.genymobile.scrcpy.Server", ClipboardProtocol.serverVersion, "scid=\(token)",
                "log_level=warn", "video=false", "audio=false", "control=true", "tunnel_forward=true",
                "send_device_meta=false", "clipboard_autosync=true", "power_on=false", "cleanup=true"]
            let child = try ManagedProcess(executable: tools.adb, arguments: arguments, environment: tools.environment)
            server = child
            readerTask = Task { [weak self] in
                for await event in child.events {
                    guard let self, !self.stopping else { return }
                    switch event {
                    case .output(let data):
                        // Never retain server output or clipboard contents in a log.
                        if String(decoding: data, as: UTF8.self).contains("No clipboard manager") {
                            self.finish(L10n.text("这台手机未提供可用的剪贴板服务。"))
                        }
                    case .exited: self.finish(L10n.text("手机剪贴板服务已断开，正在重新连接。"))
                    }
                }
            }
            connect()
            timer = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(12)) } catch { return }
                guard let self, !self.connected else { return }
                self.finish(L10n.text("剪贴板连接超时，正在重试。"))
            }
        } catch is CancellationError { }
        catch { finish(error.localizedDescription) }
    }

    private func connect() {
        guard !stopping, let port else { return }
        attempts += 1
        let socket = NWConnection(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        connection = socket
        socket.stateUpdateHandler = { [weak self, weak socket] state in
            Task { @MainActor in
                guard let self, let socket, self.connection === socket, !self.stopping else { return }
                switch state {
                case .ready: self.receive(socket)
                case .failed, .waiting: self.connectionEnded(socket)
                default: break
                }
            }
        }
        socket.start(queue: DispatchQueue.global(qos: .utility))
    }

    private func receive(_ socket: NWConnection) {
        socket.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self, weak socket] data, _, complete, error in
            Task { @MainActor in
                guard let self, let socket, self.connection === socket, !self.stopping else { return }
                if var data, !data.isEmpty {
                    do {
                        if !self.connected {
                            guard data.removeFirst() == 0 else { throw ClipboardProtocolError.invalidMessage }
                            self.connected = true
                            self.timer?.cancel()
                            self.continuation.yield(.ready)
                            self.flush()
                        }
                        for message in try self.decoder.append(Data(data)) {
                            switch message {
                            case .text(let text):
                                guard !self.echoes.isEcho(text) else { continue }
                                // A newer phone copy supersedes a queued Mac copy.
                                self.pendingText = nil
                                self.continuation.yield(.text(text))
                            case .acknowledgement(let sequence):
                                if sequence == self.awaitingAck {
                                    self.awaitingAck = nil
                                    self.ackDeadline?.cancel()
                                    self.continuation.yield(.sent)
                                    self.flush()
                                }
                            }
                        }
                    } catch { self.finish(error.localizedDescription); return }
                }
                if complete || error != nil { self.connectionEnded(socket) }
                else { self.receive(socket) }
            }
        }
    }

    private func connectionEnded(_ socket: NWConnection) {
        guard connection === socket, !stopping else { return }
        socket.cancel()
        connection = nil
        if !connected && attempts < 35 {
            // ADB accepts localhost before Android has bound the abstract socket.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.connect()
            }
        } else { finish(L10n.text("剪贴板连接已中断，正在重试。")) }
    }

    private func flush() {
        guard connected, !stopping, awaitingAck == nil, let text = pendingText, let connection else { return }
        pendingText = nil
        sequence &+= 1
        if sequence == 0 { sequence = 1 }
        guard let message = try? ClipboardProtocol.setText(text, sequence: sequence) else { return }
        awaitingAck = sequence
        echoes.sent(text)
        connection.send(content: message, completion: .contentProcessed { [weak self] error in
            if error != nil { Task { @MainActor in self?.finish(L10n.text("剪贴板发送失败，正在重试。")) } }
        })
        ackDeadline?.cancel()
        ackDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            self?.finish(L10n.text("手机未响应剪贴板同步，正在重试。"))
        }
    }

    private func finish(_ error: String?) {
        guard !stopping else { return }
        stopping = true
        pendingText = nil
        let setup = setupTask
        setup?.cancel()
        timer?.cancel()
        ackDeadline?.cancel()
        connection?.cancel()
        connection = nil
        server?.stop()
        readerTask?.cancel()
        continuation.yield(.ended(error))
        continuation.finish()
        Task {
            // Wait for cancelled setup before cleaning up, including cancellation
            // while ADB has allocated a port but has not returned it yet.
            await setup?.value
            let listing = try? await CommandRunner.run(tools.adb, ["forward", "--list"],
                                                       environment: tools.environment, timeout: .seconds(2))
            for line in listing?.output.split(whereSeparator: \.isNewline) ?? [] {
                let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
                if fields.count == 3, fields[0] == device.serial, fields[2] == "localabstract:scrcpy_\(token)" {
                    _ = try? await CommandRunner.run(tools.adb, ["-s", device.serial, "forward", "--remove", fields[1]],
                                                     environment: tools.environment, timeout: .seconds(2))
                }
            }
            // Normally scrcpy's cleanup process already unlinks its own jar.
            // Remove only this session's exact path if launch was interrupted.
            _ = try? await CommandRunner.run(tools.adb, ["-s", device.serial, "shell", "rm", "-f", remotePath],
                                             environment: tools.environment, timeout: .seconds(2))
            isStopped = true
        }
    }
}
