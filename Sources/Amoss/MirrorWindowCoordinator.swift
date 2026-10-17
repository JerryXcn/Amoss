import AppKit
#if canImport(AmossCore)
import AmossCore
#endif

@MainActor
final class MirrorWindowCoordinator {
    func placement(metrics: MirrorWindowMetrics) -> MirrorWindowPresentation? {
        guard let list = NSApp.windows.first(where: { $0.identifier?.rawValue == "devices" || $0.title == "Amoss" }),
              list.isVisible || list.isMiniaturized,
              let screen = list.screen ?? NSScreen.main else { return nil }
        if list.isMiniaturized { list.deminiaturize(nil) }
        let frames = MirrorWindowLayout.pair(list: list.frame, visible: screen.visibleFrame, metrics: metrics)
        list.setFrame(frames.list, display: true)
        list.orderFrontRegardless()
        return MirrorWindowPresentation(frame: frames.mirror)
    }

    func present(_ session: MirrorSession, fallback: MirrorWindowMetrics) {
        let presentation = placement(metrics: session.windowMetrics ?? fallback)
        if let app = NSRunningApplication(processIdentifier: session.pid) {
            // macOS 14+ requires cooperation for reliable activation. The helper
            // uses an auxiliary Stage Manager window so the list remains visible.
            NSApp.yieldActivation(to: app)
            // A menu-bar launch has no list window to place beside. Still send
            // the presentation request so minimized helper windows are restored.
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(MirrorWindowPresentation.notification), object: session.token.uuidString,
                userInfo: presentation.map { ["presentation": $0.json ?? ""] } ?? [:], deliverImmediately: true)
            _ = app.activate(from: .current, options: [.activateAllWindows])
        }
    }
}
