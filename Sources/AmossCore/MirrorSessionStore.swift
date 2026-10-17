import Foundation
import Observation
import CoreGraphics

public enum MirrorPhase: Equatable, Sendable { case starting, running, stopping }

public struct MirrorSession: Sendable {
    public let token: UUID
    public let device: AndroidDevice
    public let pid: Int32
    public let displayID: Int
    public let followsActiveDisplay: Bool
    public let application: AndroidApplication?
    public var id: String { MirrorSessionStore.sessionID(device: device, application: application) }
    public var options: MirrorOptions
    public var phase: MirrorPhase
    public var log: String
    public var windowMetrics: MirrorWindowMetrics?
}

public struct MirrorFailure: Identifiable, Sendable {
    public let id = UUID()
    public let device: AndroidDevice
    public let message: String
    public let log: String
    public var application: AndroidApplication? = nil
}

@MainActor @Observable
public final class MirrorSessionStore {
    public private(set) var sessions: [String: MirrorSession] = [:]
    public var failure: MirrorFailure?
    public private(set) var notice: String?
    @ObservationIgnored private var processes: [String: ManagedProcess] = [:]
    @ObservationIgnored private var readers: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var deadlines: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var tails: [String: Data] = [:]
    @ObservationIgnored private var shuttingDown = false
    @ObservationIgnored public var onWindowReady: ((MirrorSession) -> Void)?

    public init() {}

    nonisolated public static func sessionID(device: AndroidDevice, application: AndroidApplication? = nil) -> String {
        guard let application else { return device.id }
        return device.id + "\u{1F}" + application.packageName
    }

    public func session(for application: AndroidApplication, device: AndroidDevice) -> MirrorSession? {
        sessions[Self.sessionID(device: device, application: application)]
    }

    /// Returns the existing PID on duplicate launch, for activation by AppKit.
    @discardableResult
    public func start(_ device: AndroidDevice, tools: Toolchain, options: MirrorOptions,
                      displayID: Int = 0, followsActiveDisplay: Bool = false,
                      presentation: MirrorWindowPresentation? = nil,
                      application: AndroidApplication? = nil) -> Int32? {
        guard !shuttingDown, device.state == .ready else { return nil }
        guard application?.isValid != false else { return nil }
        let id = Self.sessionID(device: device, application: application)
        if let session = sessions[id] { return session.pid }
        do {
            let token = UUID()
            var environment = tools.environment
            // Disable scrcpy's default POWER toggle and request an idempotent
            // WAKEUP only after its keep-panel-off control has been queued.
            environment["AMOSS_WAKE_MIRROR"] = application == nil && options.startWithScreenOff ? "1" : "0"
            environment["AMOSS_APP_WINDOW"] = application == nil ? "0" : "1"
            environment["AMOSS_LANGUAGE"] = L10n.settings.selection.rawValue
            environment["AMOSS_DEVICE_NAME"] = device.name
            environment["AMOSS_DISPLAY_ID"] = String(displayID)
            environment["AMOSS_SESSION_TOKEN"] = token.uuidString
            environment["AMOSS_WINDOW_PRESENTATION"] = presentation?.json
            let process = try ManagedProcess(executable: tools.scrcpy,
                                             arguments: application.map { options.arguments(for: device, application: $0) }
                                                ?? options.arguments(for: device, displayID: displayID), environment: environment)
            processes[id] = process
            sessions[id] = MirrorSession(token: token, device: device, pid: process.pid,
                                               displayID: displayID, followsActiveDisplay: application == nil && followsActiveDisplay,
                                               application: application, options: options,
                                               phase: .starting, log: "", windowMetrics: nil)
            tails[id] = Data()
            readers[id] = Task { [weak self] in
                for await event in process.events {
                    guard let self else { break }
                    guard self.sessions[id]?.token == token else { break }
                    switch event {
                    case .output(let data): self.receive(data, for: id)
                    case .exited(let code): self.didExit(id, code: code)
                    }
                }
            }
            deadlines[id] = Task { [weak self] in
                // Hardware decoding in scrcpy 5 no longer emits the software
                // renderer's Texture log. Observe the child window as well.
                for _ in 0..<150 {
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                    guard let self, self.sessions[id]?.token == token else { return }
                    if self.sessions[id]?.phase != .starting { return }
                    if Self.hasVisibleWindow(pid: process.pid) {
                        self.sessions[id]?.phase = .running
                        return
                    }
                }
                guard let self, let session = self.sessions[id],
                      session.token == token, session.phase == .starting else { return }
                self.failure = MirrorFailure(device: device,
                    message: application == nil ? L10n.text("镜像启动超时。请检查 USB 连接与屏幕选择，然后重试。") : L10n.text("应用窗口启动超时。请检查手机是否已解锁，或尝试其他应用。"),
                    log: session.log, application: application)
                self.stop(id)
            }
            return process.pid
        } catch {
            failure = MirrorFailure(device: device, message: error.localizedDescription, log: "", application: application)
            return nil
        }
    }

    public func stop(_ serial: String) {
        guard sessions[serial] != nil else { return }
        sessions[serial]?.phase = .stopping
        deadlines[serial]?.cancel()
        processes[serial]?.stop()
    }

    public func reconcile(_ devices: [AndroidDevice]) {
        let ready = Set(devices.filter { $0.state == .ready }.map(\.id))
        for (serial, session) in sessions where !ready.contains(session.device.id) && session.phase != .stopping {
            notice = L10n.text("\(session.device.name) 已断开连接")
            stop(serial)
        }
    }

    public func clearNotice() { notice = nil }

    public func shutdown() {
        shuttingDown = true
        for serial in Array(sessions.keys) { stop(serial) }
    }

    private func receive(_ data: Data, for serial: String) {
        var tail = tails[serial, default: Data()]
        tail.append(data)
        if tail.count > 32_768 { tail.removeFirst(tail.count - 32_768) }
        tails[serial] = tail
        let log = String(decoding: tail, as: UTF8.self)
        sessions[serial]?.log = log
        if let metrics = MirrorWindowMetrics.from(log: log) {
            let firstWindow = sessions[serial]?.windowMetrics == nil
            sessions[serial]?.windowMetrics = metrics
            if sessions[serial]?.phase == .starting {
                sessions[serial]?.phase = .running
                deadlines[serial]?.cancel()
            }
            if firstWindow, let session = sessions[serial], session.phase == .running { onWindowReady?(session) }
        }
        if let off = ScrcpyLog.requestedDisplayOff(log) {
            sessions[serial]?.options.startWithScreenOff = off
        }
        if sessions[serial]?.phase == .starting && ScrcpyLog.hasVideo(log) {
            sessions[serial]?.phase = .running
            deadlines[serial]?.cancel()
        }
    }

    private func didExit(_ serial: String, code: Int32) {
        guard let session = sessions.removeValue(forKey: serial) else { return }
        processes.removeValue(forKey: serial)
        readers.removeValue(forKey: serial)
        deadlines.removeValue(forKey: serial)?.cancel()
        tails.removeValue(forKey: serial)
        guard !shuttingDown, session.phase != .stopping else { return }
        if code == 2 {
            notice = L10n.text("\(session.device.name) 已断开连接")
        } else if code != 0 {
            failure = MirrorFailure(device: session.device, message: ScrcpyLog.failureMessage(session.log),
                                    log: session.log, application: session.application)
        }
    }

    private static func hasVisibleWindow(pid: Int32) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        return windows.contains {
            ($0[kCGWindowOwnerPID as String] as? Int32) == pid &&
            ($0[kCGWindowLayer as String] as? Int) == 0
        }
    }
}
