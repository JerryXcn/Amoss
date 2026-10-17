import AppKit
import CoreGraphics
import Foundation

/// Public NSPasteboard API exposes changeCount, but no global change event.
/// Keep a bounded fallback delay, and let macOS coalesce timer wakeups.
public struct ClipboardPollingPolicy: Sendable {
    private var lastActivity: TimeInterval?
    public init() {}
    public mutating func recordActivity(at uptime: TimeInterval) { lastActivity = uptime }
    public func interval(at uptime: TimeInterval, lowPower: Bool) -> TimeInterval {
        guard !lowPower, let lastActivity, uptime - lastActivity < 10 else { return 2 }
        return 0.5
    }
    public func tolerance(at uptime: TimeInterval, lowPower: Bool) -> TimeInterval {
        interval(at: uptime, lowPower: lowPower) * 0.1
    }
}

/// Owned by the clipboard store, not by individual devices. Public workspace
/// events supplement polling without monitoring keystrokes or private APIs.
@MainActor
public final class ClipboardMonitor {
    private let check: () -> Bool
    private let workspaceCenter: NotificationCenter
    private let processCenter: NotificationCenter
    private let lowPower: () -> Bool
    private let screenIsAsleep: () -> Bool
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var task: Task<Void, Never>?
    private var policy = ClipboardPollingPolicy()
    private var enabled = false
    private var screenAsleep = false
    private var systemAsleep = false
    private var sessionInactive = false

    public init(workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
                processCenter: NotificationCenter = .default,
                lowPower: @escaping () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled },
                screenIsAsleep: @escaping () -> Bool = { CGDisplayIsAsleep(CGMainDisplayID()) != 0 },
                check: @escaping () -> Bool) {
        self.workspaceCenter = workspaceCenter
        self.processCenter = processCenter
        self.lowPower = lowPower
        self.screenIsAsleep = screenIsAsleep
        self.check = check
    }

    public var isPolling: Bool { enabled && !screenAsleep && !systemAsleep && !sessionInactive }

    public func start() {
        guard !enabled else { return }
        enabled = true
        screenAsleep = screenIsAsleep()
        systemAsleep = false
        sessionInactive = false
        policy.recordActivity(at: ProcessInfo.processInfo.systemUptime)
        observe(workspaceCenter, NSWorkspace.screensDidSleepNotification) { $0.screenAsleep = true }
        observe(workspaceCenter, NSWorkspace.screensDidWakeNotification) { $0.screenAsleep = false }
        observe(workspaceCenter, NSWorkspace.willSleepNotification) { $0.systemAsleep = true }
        observe(workspaceCenter, NSWorkspace.didWakeNotification) {
            $0.systemAsleep = false
            $0.screenAsleep = $0.screenIsAsleep()
        }
        observe(workspaceCenter, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        observe(workspaceCenter, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }
        observe(workspaceCenter, NSWorkspace.didActivateApplicationNotification) { _ in }
        observe(processCenter, .NSProcessInfoPowerStateDidChange) { _ in }
        checkAndSchedule()
    }

    /// Phone → Mac writes are already known changes. They also start a short
    /// fast interval for an active copy/paste exchange, without reading again.
    public func recordActivity() {
        guard enabled else { return }
        policy.recordActivity(at: ProcessInfo.processInfo.systemUptime)
        schedule()
    }

    public func stop() {
        enabled = false
        task?.cancel()
        task = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        policy = ClipboardPollingPolicy()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         update: @escaping @MainActor @Sendable (ClipboardMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.enabled else { return }
                update(self)
                self.checkAndSchedule()
            }
        }
        observers.append((center, token))
    }

    private func checkAndSchedule() {
        if isPolling, check() { policy.recordActivity(at: ProcessInfo.processInfo.systemUptime) }
        schedule()
    }

    private func schedule() {
        task?.cancel()
        task = nil
        guard isPolling else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let interval = policy.interval(at: now, lowPower: lowPower())
        let tolerance = policy.tolerance(at: now, lowPower: lowPower())
        task = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(interval), tolerance: .seconds(tolerance)) }
            catch { return }
            guard !Task.isCancelled, let self, self.isPolling else { return }
            self.task = nil
            self.checkAndSchedule()
        }
    }
}
