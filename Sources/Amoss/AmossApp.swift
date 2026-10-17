import SwiftUI
import AppKit
#if canImport(AmossCore)
import AmossCore
#endif

/// AppKit owns the menu-bar lifetime; all application windows still use SwiftUI.
/// Creating a window is an explicit user action, never a launch side effect.
@main
struct AmossApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusController: StatusMenuController?
    private var windows: [String: HostedWindowController] = [:]
    private var languageObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusController = StatusMenuController(model: model, delegate: self)
        installMainMenu()
        languageObservers.append(NotificationCenter.default.addObserver(
            forName: LanguageSettings.changed, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.languageDidChange() }
            })
        languageObservers.append(NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in L10n.settings.systemLanguageChanged() }
            })
        model.onMenuError = { [weak self] title, message in self?.showMessage(title, message: message) }
        model.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Finder relaunch must not silently open the device window.
        if let window = windows["devices"]?.window, window.isVisible || window.isMiniaturized {
            present(window)
        }
        return false
    }

    @objc func showDeviceWindow() {
        showWindow("devices", title: "Amoss", size: NSSize(width: 560, height: 620), resizable: true,
                   toolbar: true, content: DevicesView(model: model))
    }

    @objc func showPreferences() {
        showWindow("preferences", title: L10n.text("设置"), size: NSSize(width: 520, height: 530),
                   content: PreferencesView(preferences: model.preferences))
    }

    @objc func showHelp() {
        showWindow("help", title: L10n.text("Amoss 使用帮助"), size: NSSize(width: 560, height: 720),
                   content: HelpView(onClose: { [weak self] in self?.windows["help"]?.close() }))
    }

    func searchApplications(_ device: AndroidDevice) {
        showWindow("applications.\(device.id)", title: L10n.text("\(device.name) · 应用"), size: NSSize(width: 440, height: 470),
                   content: ApplicationSearchView(device: device, model: model))
    }

    @objc func refreshDevices() { Task { await model.refresh() } }

    @objc func showAbout() {
        showWindow("about", title: L10n.text("关于 Amoss"), size: NSSize(width: 520, height: 616),
                   content: AboutView(onHelp: { [weak self] in self?.showHelp() },
                                      onClose: { [weak self] in self?.windows["about"]?.close() }))
    }

    func showMessage(_ title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.text("知道了"))
        NSApp.activate()
        alert.runModal()
    }

    func showFailure() {
        guard let failure = model.mirrors.failure else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = failure.application == nil ? L10n.text("无法开启镜像") : L10n.text("无法打开应用窗口")
        alert.informativeText = failure.message
        alert.addButton(withTitle: L10n.text("重试"))
        alert.addButton(withTitle: L10n.text("关闭"))
        NSApp.activate()
        let response = alert.runModal()
        model.mirrors.failure = nil
        if response == .alertFirstButtonReturn,
           let device = model.devices.first(where: { $0.id == failure.device.id && $0.state == .ready }) {
            if let application = failure.application { model.openApplication(application, on: device) }
            else { model.activateFromMenu(device) }
        }
    }

    private func showWindow<Content: View>(_ id: String, title: @autoclosure @escaping () -> String, size: NSSize,
                                           resizable: Bool = false, toolbar: Bool = false, content: Content) {
        if let window = windows[id]?.window { present(window); return }
        let controller = HostedWindowController(id: id, title: title, size: size,
                                                resizable: resizable, rootView: AnyView(content))
        if toolbar { controller.installToolbar(delegate: self) }
        controller.onClose = { [weak self] in
            // Do not retain hidden SwiftUI sheets after the main window closes.
            DispatchQueue.main.async {
                self?.windows.removeValue(forKey: id)
                if self?.windows.isEmpty == true { NSApp.setActivationPolicy(.accessory) }
            }
        }
        windows[id] = controller
        if let window = controller.window { present(window) }
    }

    private func present(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func installMainMenu() {
        let main = NSMenu()
        let application = NSMenu(title: "Amoss")
        add(L10n.text("关于 Amoss"), #selector(showAbout), to: application)
        application.addItem(.separator())
        add(L10n.text("设置…"), #selector(showPreferences), key: ",", to: application)
        application.addItem(.separator())
        let hide = NSMenuItem(title: L10n.text("隐藏 Amoss"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        application.addItem(hide)
        application.addItem(.separator())
        application.addItem(NSMenuItem(title: L10n.text("退出 Amoss"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appItem = NSMenuItem(); appItem.submenu = application; main.addItem(appItem)
        let file = NSMenu(title: L10n.text("文件"))
        add(L10n.text("主界面"), #selector(showDeviceWindow), key: "1", to: file)
        add(L10n.text("重新检测设备"), #selector(refreshDevices), key: "r", to: file)
        file.addItem(.separator())
        file.addItem(NSMenuItem(title: L10n.text("关闭窗口"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let fileItem = NSMenuItem(); fileItem.submenu = file; main.addItem(fileItem)
        let edit = NSMenu(title: L10n.text("编辑"))
        for (title, selector, key) in [(L10n.text("撤销"), "undo:", "z"), (L10n.text("剪切"), "cut:", "x"),
                                        (L10n.text("复制"), "copy:", "c"), (L10n.text("粘贴"), "paste:", "v"), (L10n.text("全选"), "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: key))
        }
        let editItem = NSMenuItem(); editItem.submenu = edit; main.addItem(editItem)
        let deviceMenu = NSMenuItem()
        deviceMenu.submenu = statusController?.applicationDeviceMenu()
        main.addItem(deviceMenu)
        let help = NSMenu(title: L10n.text("帮助"))
        add(L10n.text("Amoss 使用帮助"), #selector(showHelp), to: help)
        let helpItem = NSMenuItem(); helpItem.submenu = help; main.addItem(helpItem)
        NSApp.mainMenu = main
    }

    private func languageDidChange() {
        installMainMenu()
        for controller in windows.values { controller.refreshLocalization() }
        DistributedNotificationCenter.default().postNotificationName(LanguageSettings.changed, object: nil,
            userInfo: ["selection": L10n.settings.selection.rawValue,
                       "languages": Locale.preferredLanguages], deliverImmediately: true)
    }

    private func add(_ title: String, _ selector: Selector, key: String = "", to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for observer in languageObservers { NotificationCenter.default.removeObserver(observer) }
        languageObservers.removeAll()
        statusController?.stop()
        model.shutdown()
        guard !model.mirrors.sessions.isEmpty || model.clipboard.hasPendingShutdown else { return .terminateNow }
        Task { @MainActor in
            for _ in 0..<60 {
                if model.mirrors.sessions.isEmpty && !model.clipboard.hasPendingShutdown { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@MainActor
private final class HostedWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    var onClose: (() -> Void)?
    private weak var appDelegate: AppDelegate?
    private let titleProvider: () -> String

    init(id: String, title: @escaping () -> String, size: NSSize, resizable: Bool, rootView: AnyView) {
        titleProvider = title
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title()
        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.contentViewController = NSHostingController(rootView: LocalizedWindowRoot(content: rootView))
        if resizable { window.contentMinSize = NSSize(width: 460, height: 300) }
        super.init(window: window)
        window.delegate = self
        if id == "devices" {
            window.setFrameAutosaveName("AmossDevicesWindow")
            if !window.setFrameUsingName("AmossDevicesWindow") { window.center() }
        } else { window.center() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func windowWillClose(_ notification: Notification) { onClose?() }

    func refreshLocalization() {
        window?.title = titleProvider()
        if let appDelegate { installToolbar(delegate: appDelegate) }
    }

    func installToolbar(delegate: AppDelegate) {
        appDelegate = delegate
        let toolbar = NSToolbar(identifier: "AmossDevicesToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window?.toolbar = toolbar
        window?.toolbarStyle = .unifiedCompact
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .init("refresh"), .init("more")]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id.rawValue == "refresh" {
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = L10n.text("重新检测设备"); item.toolTip = L10n.text("重新检测设备（⌘R）")
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: item.label)
            item.target = appDelegate; item.action = #selector(AppDelegate.refreshDevices)
            return item
        }
        guard id.rawValue == "more" else { return nil }
        let item = NSMenuToolbarItem(itemIdentifier: id)
        item.label = L10n.text("更多"); item.toolTip = L10n.text("更多")
        item.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: L10n.text("更多"))
        let menu = NSMenu()
        for (title, action) in [(L10n.text("设置…"), #selector(AppDelegate.showPreferences)),
                                (L10n.text("连接与操作帮助"), #selector(AppDelegate.showHelp)), (L10n.text("关于 Amoss"), #selector(AppDelegate.showAbout))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = appDelegate; menu.addItem(entry)
        }
        item.menu = menu
        return item
    }
}

private struct LocalizedWindowRoot: View {
    let content: AnyView
    var body: some View {
        content.environment(\.locale, Locale(identifier: L10n.settings.resolved.rawValue))
    }
}

private struct ApplicationSearchView: View {
    let device: AndroidDevice
    @Bindable var model: AppModel
    @State private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(device.name).font(.headline)
            if model.devices.contains(where: { $0.id == device.id && $0.state == .ready }) {
                ApplicationsView(device: device, model: model, search: $search)
            } else {
                ContentUnavailableView(L10n.text("设备已断开"), systemImage: "cable.connector.slash",
                                       description: Text(L10n.text("重新连接并授权后，应用列表会恢复。")))
            }
        }
        .padding(20).frame(width: 440)
        .onAppear { if model.applications[device.id] == nil { model.refreshApplications(device) } }
        .onChange(of: model.devices) {
            if model.applications[device.id] == nil,
               let current = model.devices.first(where: { $0.id == device.id && $0.state == .ready }) {
                model.refreshApplications(current)
            }
        }
    }
}
