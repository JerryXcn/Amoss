import AppKit
import Observation
#if canImport(AmossCore)
import AmossCore
#endif

enum ClipboardSyncStatus: Equatable {
    case disabled, waiting, connecting, ready, issue(String)
    var title: String {
        switch self {
        case .disabled: L10n.text("已关闭")
        case .waiting: L10n.text("等待 USB 连接与授权")
        case .connecting: L10n.text("正在连接剪贴板…")
        case .ready: L10n.text("已开启 · 后台双向同步")
        case .issue(let message): message
        }
    }
}

@MainActor @Observable
final class ClipboardSyncStore {
    private(set) var enabled: [String: Bool] = [:]
    private(set) var statuses: [String: ClipboardSyncStatus] = [:]
    @ObservationIgnored private let preferences: ClipboardDevicePreferences
    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private var sessions: [String: ClipboardSession] = [:]
    @ObservationIgnored private var retired: [ClipboardSession] = []
    @ObservationIgnored private var readers: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var retryAfter: [String: Date] = [:]
    @ObservationIgnored private var failureCounts: [String: Int] = [:]
    @ObservationIgnored private var devices: [AndroidDevice] = []
    @ObservationIgnored private var tools: Toolchain?
    @ObservationIgnored private var monitor: ClipboardMonitor?
    @ObservationIgnored private var changeCount: Int
    @ObservationIgnored private var routing = ClipboardRouting()
    @ObservationIgnored private var stopped = false

    init(defaults: UserDefaults = .standard, pasteboard: NSPasteboard = .general) {
        preferences = ClipboardDevicePreferences(defaults: defaults)
        self.pasteboard = pasteboard
        changeCount = pasteboard.changeCount
        monitor = ClipboardMonitor { [weak self] in self?.pollMac() ?? false }
    }

    var hasPendingShutdown: Bool { !sessions.isEmpty || retired.contains { !$0.isStopped } }
    func isEnabled(_ id: String) -> Bool { enabled[id] ?? preferences.isEnabled(id) }
    func status(_ id: String) -> ClipboardSyncStatus {
        statuses[id] ?? (isEnabled(id) ? .waiting : .disabled)
    }

    func setEnabled(_ value: Bool, for id: String) {
        enabled[id] = value
        preferences.setEnabled(value, for: id)
        retryAfter[id] = nil
        failureCounts[id] = nil
        if !value { stopSession(id); statuses[id] = .disabled }
        if let tools { reconcile(devices, tools: tools) }
    }

    func retry(_ id: String) {
        stopSession(id)
        retryAfter[id] = nil
        failureCounts[id] = nil
        if let tools { reconcile(devices, tools: tools) }
    }

    func reconcile(_ devices: [AndroidDevice], tools: Toolchain) {
        guard !stopped else { return }
        self.devices = devices
        self.tools = tools
        retired.removeAll { $0.isStopped }
        let readyIDs = Set(devices.filter { $0.state == .ready && $0.isUSB }.map(\.id))
        for id in Array(sessions.keys) where !readyIDs.contains(id) || !isEnabled(id) {
            stopSession(id)
        }
        for id in Array(statuses.keys) where !readyIDs.contains(id) {
            statuses[id] = isEnabled(id) ? .waiting : .disabled
            retryAfter[id] = nil
            failureCounts[id] = nil
        }
        for device in devices {
            if enabled[device.id] == nil { enabled[device.id] = preferences.isEnabled(device.id) }
            guard isEnabled(device.id) else { statuses[device.id] = .disabled; continue }
            guard readyIDs.contains(device.id) else { statuses[device.id] = .waiting; continue }
            guard sessions[device.id] == nil, (retryAfter[device.id] ?? .distantPast) <= Date() else { continue }
            startSession(device, tools: tools)
        }
        if sessions.isEmpty { stopPolling() }
    }

    func connectionUnavailable() {
        for id in Array(sessions.keys) { stopSession(id); statuses[id] = .waiting }
        devices = []
        stopPolling()
    }

    private func startSession(_ device: AndroidDevice, tools: Toolchain) {
        let id = device.id
        if sessions.isEmpty { changeCount = pasteboard.changeCount }
        let session = ClipboardSession(device: device, tools: tools)
        sessions[id] = session
        routing.connect(id)
        statuses[id] = .connecting
        readers[id] = Task { [weak self, weak session] in
            guard let session else { return }
            for await event in session.events {
                guard let self, !Task.isCancelled, self.sessions[id] === session, self.isEnabled(id) else { return }
                switch event {
                case .ready, .sent:
                    self.statuses[id] = .ready
                    self.failureCounts[id] = 0
                case .text(let text):
                    // Account for a Mac copy that happened between timer ticks.
                    self.pollMac()
                    self.receive(text, from: id)
                case .ended(let error):
                    self.sessions[id] = nil
                    self.readers[id] = nil
                    self.routing.disconnect(id)
                    self.retired.append(session)
                    let failures = min((self.failureCounts[id] ?? 0) + 1, 5)
                    self.failureCounts[id] = failures
                    self.retryAfter[id] = Date().addingTimeInterval(min(pow(2, Double(failures)), 30))
                    self.statuses[id] = .issue(error ?? L10n.text("剪贴板连接已断开，正在重试。"))
                    if self.sessions.isEmpty { self.stopPolling() }
                }
            }
        }
        monitor?.start()
    }

    @discardableResult private func pollMac() -> Bool {
        let current = pasteboard.changeCount
        guard current != changeCount else { return false }
        changeCount = current
        if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny {
            for id in sessions.keys { statuses[id] = .issue(L10n.text("macOS 未允许 Amoss 读取剪贴板，请在系统设置中允许。")) }
            return true
        }
        guard let types = pasteboard.types, types.contains(.string), !types.contains(.fileURL),
              !types.contains(.png), !types.contains(.tiff),
              let text = pasteboard.string(forType: .string) else {
            routing.macContainsNonText()
            return true
        }
        guard valid(text) else { routing.macContainsNonText(); return true }
        deliver(text, change: routing.copiedOnMac(text))
        return true
    }

    private func receive(_ text: String, from id: String) {
        guard valid(text, device: id) else { return }
        let change = routing.copiedOnDevice(text, id: id)
        if change.updateMac {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            // Do not treat our own write as a fresh Mac copy on the next tick.
            changeCount = pasteboard.changeCount
            monitor?.recordActivity()
        }
        deliver(text, change: change)
        statuses[id] = .ready
    }

    private func valid(_ text: String, device: String? = nil) -> Bool {
        guard text.utf8.count <= ClipboardProtocol.maximumTextBytes else {
            for id in device.map({ [$0] }) ?? Array(sessions.keys) {
                statuses[id] = .issue(ClipboardProtocolError.textTooLong.localizedDescription)
            }
            return false
        }
        return true
    }

    private func deliver(_ text: String, change: ClipboardRouting.Change) {
        for id in change.destinations where isEnabled(id) {
            do { try sessions[id]?.send(text) }
            catch { statuses[id] = .issue(error.localizedDescription) }
        }
    }

    private func stopSession(_ id: String) {
        readers.removeValue(forKey: id)?.cancel()
        if let session = sessions.removeValue(forKey: id) {
            session.stop()
            retired.append(session)
        }
        routing.disconnect(id)
    }

    private func stopPolling() {
        monitor?.stop()
        routing = ClipboardRouting()
        changeCount = pasteboard.changeCount
    }

    func shutdown() {
        stopped = true
        for id in Array(sessions.keys) { stopSession(id) }
        stopPolling()
    }
}
