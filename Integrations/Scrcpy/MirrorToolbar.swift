// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Amoss contributors
import AppKit
import SwiftUI

private typealias ControlAction = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Bool

@MainActor
private final class ToolbarState: ObservableObject {
    let isApplication = ProcessInfo.processInfo.environment["AMOSS_APP_WINDOW"] == "1"
    @Published var enabled = true
    @Published var displayOff = false
    @Published var failed = false
    weak var window: NSWindow?
    var context: UnsafeMutableRawPointer?
    var action: ControlAction?

    func send(_ code: Int32) {
        guard enabled, let action, let context else { return }
        guard action(context, code) else {
            failed = true
            NSSound.beep()
            return
        }
        failed = false
        if code == 3 { displayOff = true }
        if code == 4 { displayOff = false }
        // Clicking a native control must not steal subsequent phone typing.
        window?.makeFirstResponder(window?.contentView)
    }
}

private struct MirrorToolbar: View {
    @ObservedObject var state: ToolbarState

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                control(L10n.text("返回"), symbol: "chevron.backward", id: "back", help: L10n.text("返回（⌘B）"), code: 0)
                if state.isApplication {
                    Text(L10n.text("独立应用窗口")).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                control(L10n.text("主页"), symbol: "house", id: "home", help: L10n.text("回到手机主页（⌘H）"), code: 1)
                control(L10n.text("多任务"), symbol: "square.on.square", id: "recents", help: L10n.text("切换最近使用的应用（⌘S）"), code: 2)
                Divider().frame(height: 18).padding(.horizontal, 4)
                control(state.displayOff ? L10n.text("亮屏") : L10n.text("熄屏"),
                        symbol: state.displayOff ? "sun.max" : "moon",
                        id: "display-power",
                        help: state.displayOff ? L10n.text("亮屏（⇧⌘O）") : L10n.text("熄屏，保留镜像（⌘O）"),
                        code: state.displayOff ? 4 : 3)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 44)
        .background(Color(nsColor: .windowBackgroundColor))
        .disabled(!state.enabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(state.isApplication ? L10n.text("应用窗口操作") : L10n.text("手机系统操作"))
        .alert(L10n.text("操作未发送"), isPresented: $state.failed) {
            Button(L10n.text("好"), role: .cancel) { }
        } message: {
            Text(L10n.text("设备连接可能已断开，请重新开启镜像后重试。"))
        }
        .environment(\.locale, Locale(identifier: L10n.settings.resolved.rawValue))
    }

    private func control(_ title: String, symbol: String, id: String, help: String, code: Int32) -> some View {
        Button { state.send(code) } label: {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
            .frame(maxWidth: .infinity).frame(height: 32)
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(ToolbarButtonStyle())
        .frame(maxWidth: 44)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityIdentifier("mirror-\(id)")
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        HoverButton(configuration: configuration, enabled: enabled)
    }
    private struct HoverButton: View {
        let configuration: ButtonStyleConfiguration
        let enabled: Bool
        @State private var hovering = false
        var body: some View {
            configuration.label
                .foregroundStyle(enabled ? Color.primary : Color.secondary)
                .background(Color.primary.opacity(configuration.isPressed ? 0.13 : (hovering && enabled ? 0.06 : 0)),
                            in: RoundedRectangle(cornerRadius: 7))
                .onHover { hovering = $0 }
        }
    }
}

@MainActor
private final class NativeToolbar {
    let state = ToolbarState()
    let view: NSHostingView<MirrorToolbar>
    let windowBehavior: MirrorWindowBehavior
    private var languageObserver: NSObjectProtocol?

    init(window: NSWindow, context: UnsafeMutableRawPointer, action: @escaping ControlAction) {
        windowBehavior = MirrorWindowBehavior(window: window)
        state.window = window
        state.context = context
        state.action = action
        view = NSHostingView(rootView: MirrorToolbar(state: state))
        languageObserver = DistributedNotificationCenter.default().addObserver(
            forName: LanguageSettings.changed, object: nil, queue: .main) { [weak self] notification in
                guard let raw = notification.userInfo?["selection"] as? String,
                      let selection = AppLanguage(rawValue: raw),
                      let languages = notification.userInfo?["languages"] as? [String] else { return }
                Task { @MainActor in
                    guard let self else { return }
                    L10n.settings.applyRemote(selection: selection, preferredLanguages: languages)
                    self.windowBehavior.refreshLocalizedTitle()
                }
            }
        view.sizingOptions = []
        view.translatesAutoresizingMaskIntoConstraints = false
        if let content = window.contentView {
            content.addSubview(view, positioned: .above, relativeTo: nil)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                view.heightAnchor.constraint(equalToConstant: 44)
            ])
        }
    }

    func remove() {
        if let languageObserver { DistributedNotificationCenter.default().removeObserver(languageObserver) }
        languageObserver = nil
        windowBehavior.remove()
        state.enabled = false
        state.context = nil
        state.action = nil
        view.removeFromSuperview()
    }
}

@MainActor @_cdecl("amoss_native_install")
func amossNativeInstall(_ window: UnsafeMutableRawPointer, _ context: UnsafeMutableRawPointer,
                        _ action: @escaping @convention(c) (UnsafeMutableRawPointer?, Int32) -> Bool) -> UnsafeMutableRawPointer {
    let nativeWindow = Unmanaged<NSWindow>.fromOpaque(window).takeUnretainedValue()
    return Unmanaged.passRetained(NativeToolbar(window: nativeWindow, context: context, action: action)).toOpaque()
}

@MainActor @_cdecl("amoss_native_remove")
func amossNativeRemove(_ pointer: UnsafeMutableRawPointer) {
    Unmanaged<NativeToolbar>.fromOpaque(pointer).takeRetainedValue().remove()
}

@MainActor @_cdecl("amoss_native_set_enabled")
func amossNativeSetEnabled(_ pointer: UnsafeMutableRawPointer, _ enabled: Bool) {
    Unmanaged<NativeToolbar>.fromOpaque(pointer).takeUnretainedValue().state.enabled = enabled
}

@MainActor @_cdecl("amoss_native_set_display_power")
func amossNativeSetDisplayPower(_ pointer: UnsafeMutableRawPointer, _ on: Bool) {
    Unmanaged<NativeToolbar>.fromOpaque(pointer).takeUnretainedValue().state.displayOff = !on
}

@MainActor @_cdecl("amoss_native_set_video_size")
func amossNativeSetVideoSize(_ pointer: UnsafeMutableRawPointer, _ width: Int32, _ height: Int32) {
    Unmanaged<NativeToolbar>.fromOpaque(pointer).takeUnretainedValue().windowBehavior.setVideoSize(width: width, height: height)
}

@MainActor @_cdecl("amoss_native_prepare_window")
func amossNativePrepareWindow(_ pointer: UnsafeMutableRawPointer) {
    Unmanaged<NativeToolbar>.fromOpaque(pointer).takeUnretainedValue().windowBehavior.prepareToShow()
}

@MainActor @_cdecl("amoss_native_window_shown")
func amossNativeWindowShown(_ pointer: UnsafeMutableRawPointer) {
    Unmanaged<NativeToolbar>.fromOpaque(pointer).takeUnretainedValue().windowBehavior.didShow()
}
