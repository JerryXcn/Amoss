// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Amoss contributors
import AppKit

/// Forward SDL's window delegate so its renderer, fullscreen and input callbacks
/// remain intact while resizing only the video area at the phone's aspect ratio.
@MainActor
final class MirrorWindowBehavior: NSObject, NSWindowDelegate {
    weak var window: NSWindow?
    nonisolated(unsafe) let previousDelegate: (any NSWindowDelegate)?
    private var metrics: MirrorWindowMetrics?
    private var shown = false
    private let sessionToken: String?

    init(window: NSWindow) {
        self.window = window
        previousDelegate = window.delegate
        sessionToken = ProcessInfo.processInfo.environment["AMOSS_SESSION_TOKEN"]
        super.init()
        window.delegate = self
        // Auxiliary windows join the active Stage Manager set instead of
        // displacing the device-list app. Keep the normal window level.
        window.collectionBehavior.remove([.primary, .canJoinAllApplications, .canJoinAllSpaces])
        window.collectionBehavior.formUnion([.auxiliary, .moveToActiveSpace])
        window.tabbingMode = .disallowed
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) { NSApp.applicationIconImage = icon }
        if let sessionToken {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(present(_:)),
                name: Notification.Name(MirrorWindowPresentation.notification), object: sessionToken,
                suspensionBehavior: .deliverImmediately)
        }
    }

    nonisolated override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || previousDelegate?.responds(to: selector) == true
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        if previousDelegate?.responds(to: selector) == true { return previousDelegate }
        return super.forwardingTarget(for: selector)
    }

    func windowWillResize(_ sender: NSWindow, to proposed: NSSize) -> NSSize {
        let size = previousDelegate?.windowWillResize?(sender, to: proposed) ?? proposed
        guard let metrics, !sender.styleMask.contains(.fullScreen) else { return size }
        let maximum = sender.screen?.visibleFrame.size ?? CGSize(width: 10000, height: 10000)
        return MirrorWindowLayout.resized(size, current: sender.frame.size, metrics: metrics, maximum: maximum)
    }

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        let frame = previousDelegate?.windowWillUseStandardFrame?(window, defaultFrame: newFrame) ?? newFrame
        guard let metrics else { return frame }
        let size = MirrorWindowLayout.fittedSize(metrics: metrics, maximum: frame.size,
                                                 preferredVideoHeight: frame.height - metrics.chromeHeight)
        return CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    func setVideoSize(width: Int32, height: Int32) {
        guard let window, width > 0, height > 0 else { return }
        let titlebar = window.frame.height - window.contentRect(forFrameRect: window.frame).height
        metrics = .init(videoWidth: Double(width), videoHeight: Double(height), titlebarHeight: titlebar)
        window.contentMinSize = CGSize(width: 160, height: max(160, 160 * Double(height) / Double(width)) + 44)
        if shown { reportMetrics() }
    }

    func prepareToShow() {
        if let value = MirrorWindowPresentation.decode(ProcessInfo.processInfo.environment["AMOSS_WINDOW_PRESENTATION"]) {
            apply(value)
        }
    }

    func didShow() {
        shown = true
        refreshLocalizedTitle()
        reportMetrics()
    }

    func refreshLocalizedTitle() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["AMOSS_APP_WINDOW"] != "1",
              let name = environment["AMOSS_DEVICE_NAME"],
              let displayID = environment["AMOSS_DISPLAY_ID"] else { return }
        window?.title = L10n.text("\(name) · 屏幕 \(displayID) — Amoss")
    }

    private func reportMetrics() {
        guard let metrics, let data = try? JSONEncoder().encode(metrics),
              let json = String(data: data, encoding: .utf8) else { return }
        FileHandle.standardOutput.write(Data("INFO: Amoss window ready: \(json)\n".utf8))
    }

    @objc private func present(_ notification: Notification) {
        guard notification.object as? String == sessionToken,
              let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        if !window.styleMask.contains(.fullScreen),
           let value = MirrorWindowPresentation.decode(notification.userInfo?["presentation"] as? String) { apply(value) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func apply(_ presentation: MirrorWindowPresentation) {
        guard let window, let metrics else { return }
        let target = presentation.frame
        let size = MirrorWindowLayout.fittedSize(metrics: metrics, maximum: target.size,
                                                 preferredVideoHeight: target.height - metrics.chromeHeight)
        window.setFrame(CGRect(x: target.minX, y: target.maxY - size.height,
                               width: size.width, height: size.height), display: true)
    }

    func remove() {
        DistributedNotificationCenter.default().removeObserver(self)
        if let window, window.delegate === self { window.delegate = previousDelegate }
    }
}
