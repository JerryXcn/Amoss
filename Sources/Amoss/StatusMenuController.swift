import AppKit
import Observation
#if canImport(AmossCore)
import AmossCore
#endif

@MainActor
private final class MenuAction: NSObject {
    let perform: () -> Void
    init(_ perform: @escaping () -> Void) { self.perform = perform }
}

private enum MenuContext: Equatable {
    case root, devices, device(String), applications(String), displays(String), windows
}

@MainActor
private final class LiveMenu: NSMenu {
    let context: MenuContext
    var revision = ""
    init(_ context: MenuContext) {
        self.context = context
        super.init(title: "")
        autoenablesItems = false
        minimumWidth = 230
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Native menus supply hover navigation, keyboard/type selection, scrolling,
/// accessibility and the current system appearance without custom popovers.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private weak var appDelegate: AppDelegate?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var openMenus: [LiveMenu] = []
    private var stopped = false

    init(model: AppModel, delegate: AppDelegate) {
        self.model = model
        appDelegate = delegate
        super.init()
        let root = makeMenu(.root)
        statusItem.menu = root
        statusItem.button?.setAccessibilityLabel("Amoss")
        observeChanges()
    }

    func applicationDeviceMenu() -> NSMenu {
        let menu = makeMenu(.devices)
        menu.title = L10n.text("设备")
        return menu
    }

    func stop() {
        stopped = true
        statusItem.menu?.cancelTracking()
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func observeChanges() {
        guard !stopped else { return }
        withObservationTracking {
            // Observe user-facing state, never the rapidly changing video logs.
            _ = model.devices; _ = model.hasScanned; _ = model.connectionError
            _ = model.applications; _ = model.loadingApplications; _ = model.applicationErrors
            _ = model.preparing; _ = model.displays; _ = model.menuDisplayErrors
            _ = model.mirrors.sessions; _ = model.mirrors.failure
            _ = model.clipboard.enabled; _ = model.clipboard.statuses
            _ = L10n.settings.resolved
            updateStatus()
            // Preserve parent menu identity while a child loads asynchronously.
            for menu in openMenus.reversed() where !openMenus.contains(where: { $0.supermenu === menu }) {
                rebuild(menu)
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeChanges() }
        }
    }

    private func updateStatus() {
        let ready = model.devices.filter { $0.state == .ready }.count
        let warning = model.connectionError != nil || model.mirrors.failure != nil || model.devices.contains { $0.state == .unauthorized }
        let symbol = warning ? "exclamationmark.triangle" : "iphone"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Amoss")
            ?? NSImage(systemSymbolName: "smartphone", accessibilityDescription: "Amoss")
        image?.isTemplate = true
        statusItem.button?.image = image
        let count = model.mirrors.sessions.count
        statusItem.button?.toolTip = L10n.text("Amoss · \(ready) 台设备可用\(count > 0 ? L10n.text(" · \(count) 个窗口") : "")")
    }

    private func makeMenu(_ context: MenuContext) -> LiveMenu {
        let menu = LiveMenu(context)
        menu.delegate = self
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let menu = menu as? LiveMenu else { return }
        rebuild(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard let menu = menu as? LiveMenu else { return }
        if !openMenus.contains(where: { $0 === menu }) { openMenus.append(menu) }
        switch menu.context {
        case .applications(let id):
            if let device = currentDevice(id), model.applications[id] == nil, model.applicationErrors[id] == nil {
                model.refreshApplications(device)
            }
        case .displays(let id):
            if let device = currentDevice(id), model.displays[id] == nil, model.menuDisplayErrors[id] == nil {
                model.loadDisplaysForMenu(device)
            }
        default: break
        }
        rebuild(menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        openMenus.removeAll { $0 === menu }
        if let parent = menu.supermenu as? LiveMenu, openMenus.contains(where: { $0 === parent }) {
            rebuild(parent)
        }
    }

    private func currentDevice(_ id: String) -> AndroidDevice? {
        model.devices.first { $0.id == id }
    }

    private func signature(_ context: MenuContext) -> String {
        let devices = model.devices.map { "\($0.id):\($0.name):\($0.state.rawValue)" }.joined(separator: "|")
        let sessions = model.mirrors.sessions.values.sorted { $0.id < $1.id }
            .map { "\($0.id):\($0.phase):\($0.displayID):\($0.followsActiveDisplay)" }.joined(separator: "|")
        let common = L10n.settings.resolved.rawValue + devices + (model.connectionError ?? "")
        switch context {
        case .root, .devices: return common + "\(model.hasScanned):\(model.mirrors.sessions.count):\(model.mirrors.failure?.id.uuidString ?? "")"
        case .windows: return common + sessions
        case .device(let id): return common + sessions + "\(model.preparing.contains(id)):\(model.clipboard.isEnabled(id)):\(model.clipboard.status(id))"
        case .applications(let id):
            return common + sessions + "\(model.loadingApplications.contains(id))" + (model.applicationErrors[id] ?? "") +
                (model.applications[id]?.map { $0.id + $0.name }.joined(separator: "|") ?? "nil")
        case .displays(let id):
            return common + sessions + "\(model.preparing.contains(id))" + (model.menuDisplayErrors[id] ?? "") +
                String(describing: model.displays[id]) + (model.savedSelection(for: currentDevice(id) ?? .init(serial: id, state: .offline))?.storageValue ?? "auto")
        }
    }

    private func rebuild(_ menu: LiveMenu) {
        let revision = signature(menu.context)
        guard revision != menu.revision else { return }
        menu.revision = revision
        menu.removeAllItems()
        switch menu.context {
        case .root: buildRoot(menu)
        case .devices:
            buildDeviceList(menu)
            if !model.mirrors.sessions.isEmpty {
                menu.addItem(.separator())
                item(L10n.text("已打开窗口（\(model.mirrors.sessions.count)）"), in: menu).submenu = makeMenu(.windows)
            }
        case .windows: buildWindows(menu)
        case .device(let id): if let device = currentDevice(id) { buildDevice(device, in: menu) } else { note(L10n.text("设备已断开"), in: menu) }
        case .applications(let id): if let device = currentDevice(id), device.state == .ready { buildApplications(device, in: menu) } else { note(L10n.text("设备不可用，请重新连接并授权"), in: menu) }
        case .displays(let id): if let device = currentDevice(id), device.state == .ready { buildDisplays(device, in: menu) } else { note(L10n.text("设备不可用，请重新连接并授权"), in: menu) }
        }
    }

    private func buildRoot(_ menu: NSMenu) {
        item(L10n.text("主界面…"), symbol: "macwindow", key: "1", in: menu) { [weak self] in self?.appDelegate?.showDeviceWindow() }
        menu.addItem(.separator())
        buildDeviceList(menu)
        menu.addItem(.separator())
        if !model.mirrors.sessions.isEmpty {
            item(L10n.text("已打开窗口（\(model.mirrors.sessions.count)）"), symbol: "macwindow.on.rectangle", in: menu).submenu = makeMenu(.windows)
        }
        if let failure = model.mirrors.failure {
            let entry = item(L10n.text("上次打开失败…"), symbol: "exclamationmark.triangle", in: menu) { [weak self] in self?.appDelegate?.showFailure() }
            entry.subtitle = failure.application?.name ?? failure.device.name
        }
        item(L10n.text("设置…"), symbol: "slider.horizontal.3", key: ",", in: menu) { [weak self] in self?.appDelegate?.showPreferences() }
        item(L10n.text("连接与操作帮助…"), symbol: "questionmark.circle", in: menu) { [weak self] in self?.appDelegate?.showHelp() }
        item(L10n.text("关于 Amoss"), in: menu) { [weak self] in self?.appDelegate?.showAbout() }
        menu.addItem(.separator())
        let quit = item(L10n.text("退出 Amoss"), key: "q", in: menu) { NSApp.terminate(nil) }
        if !model.mirrors.sessions.isEmpty { quit.subtitle = L10n.text("同时关闭 \(model.mirrors.sessions.count) 个窗口") }
    }

    private func buildDeviceList(_ menu: NSMenu) {
        menu.addItem(.sectionHeader(title: L10n.text("设备列表 · \(model.devices.count) 台")))
        if let error = model.connectionError {
            item(L10n.text("设备检测失败…"), symbol: "exclamationmark.triangle", in: menu) { [weak self] in
                self?.appDelegate?.showMessage(L10n.text("设备检测失败"), message: error)
            }
        }
        if model.devices.isEmpty {
            note(model.hasScanned ? L10n.text("未连接 USB 设备") : L10n.text("正在检测 USB 设备…"), in: menu)
        }
        let duplicateNames = Dictionary(grouping: model.devices, by: \.name)
        for device in model.devices {
            let entry = item(device.name, symbol: "smartphone", in: menu)
            let suffix = (duplicateNames[device.name]?.count ?? 0) > 1 ? " · …\(device.serial.suffix(6))" : ""
            entry.subtitle = "USB · \(device.state.label)\(suffix)"
            entry.submenu = makeMenu(.device(device.id))
        }
        item(L10n.text("重新检测设备"), symbol: "arrow.clockwise", in: menu) { [weak self] in self?.appDelegate?.refreshDevices() }
    }

    private func buildDevice(_ device: AndroidDevice, in menu: NSMenu) {
        if device.state == .unauthorized {
            note(L10n.text("等待手机授权"), in: menu)
            item(L10n.text("如何授权…"), in: menu) { [weak self] in
                self?.appDelegate?.showMessage(L10n.text("请在手机上允许连接"), message: L10n.text("解锁手机，在「允许 USB 调试？」提示中选择「允许」。授权后菜单自动更新。没有看到提示时，请重新插拔数据线并检查 USB 调试。"))
            }
        } else if device.state != .ready || model.connectionError != nil {
            note(device.state == .ready ? L10n.text("连接暂不可用") : device.state.label, in: menu)
            item(L10n.text("重新检测设备"), in: menu) { [weak self] in self?.appDelegate?.refreshDevices() }
        } else {
            let session = model.mirrors.sessions[device.id]
            let preparing = model.preparing.contains(device.id)
            let title = preparing ? L10n.text("正在读取屏幕…") : session.map { $0.phase == .starting ? L10n.text("正在开启镜像…") : $0.phase == .stopping ? L10n.text("正在结束镜像…") : L10n.text("显示镜像") } ?? L10n.text("开启镜像")
            item(title, symbol: "play.rectangle", enabled: !preparing && (session == nil || session?.phase == .running), in: menu) { [weak self] in self?.model.activateFromMenu(device) }
            item(L10n.text("镜像屏幕"), symbol: "rectangle.2.swap", in: menu).submenu = makeMenu(.displays(device.id))
            if session != nil || preparing {
                item(session?.phase == .starting || preparing ? L10n.text("取消镜像") : L10n.text("结束镜像"), enabled: session?.phase != .stopping, in: menu) { [weak self] in self?.model.cancelLaunch(device.id) }
            }
            menu.addItem(.separator())
            item(L10n.text("应用"), symbol: "square.grid.2x2", in: menu).submenu = makeMenu(.applications(device.id))
        }
        menu.addItem(.separator())
        let clipboard = item(L10n.text("剪贴板同步"), symbol: "doc.on.clipboard", in: menu) { [weak self] in
            guard let self else { return }
            self.model.clipboard.setEnabled(!self.model.clipboard.isEnabled(device.id), for: device.id)
        }
        clipboard.state = model.clipboard.isEnabled(device.id) ? .on : .off
        clipboard.subtitle = model.clipboard.status(device.id).title
        clipboard.toolTip = L10n.text("无需打开镜像。Mac 与手机双向同步文字；多台开启的设备共享同一份剪贴板。")
        if case .issue = model.clipboard.status(device.id) {
            item(L10n.text("重新连接剪贴板"), in: menu) { [weak self] in self?.model.clipboard.retry(device.id) }
        }
        menu.addItem(.separator())
        item(L10n.text("设备信息…"), in: menu) { [weak self] in
            self?.appDelegate?.showMessage(device.name, message: L10n.text("USB · \(device.state.label)\n序列号：\(device.serial)"))
        }
    }

    private func buildApplications(_ device: AndroidDevice, in menu: NSMenu) {
        item(L10n.text("搜索应用…"), symbol: "magnifyingglass", in: menu) { [weak self] in self?.appDelegate?.searchApplications(device) }
        let loading = model.loadingApplications.contains(device.id)
        item(loading ? L10n.text("正在读取应用…") : L10n.text("刷新应用列表"), symbol: "arrow.clockwise", enabled: !loading, in: menu) { [weak self] in self?.model.refreshApplications(device) }
        menu.addItem(.separator())
        if let error = model.applicationErrors[device.id] {
            let entry = item(L10n.text("应用读取失败，点此查看…"), in: menu) { [weak self] in self?.appDelegate?.showMessage(L10n.text("应用读取失败"), message: error) }
            entry.toolTip = error
        }
        guard let applications = model.applications[device.id], !applications.isEmpty else {
            note(loading ? L10n.text("首次读取可能需要几秒钟…") : L10n.text("没有可打开的应用"), in: menu)
            return
        }
        let recentIDs = UserDefaults.standard.stringArray(forKey: "recentApps.\(device.id)") ?? []
        let recent = recentIDs.compactMap { id in applications.first { $0.id == id } }
        if !recent.isEmpty {
            menu.addItem(.sectionHeader(title: L10n.text("最近打开")))
            for application in recent { applicationItem(application, device: device, in: menu) }
            menu.addItem(.separator())
        }
        menu.addItem(.sectionHeader(title: L10n.text("全部应用 · \(applications.count)")))
        for application in applications { applicationItem(application, device: device, in: menu) }
    }

    private func applicationItem(_ application: AndroidApplication, device: AndroidDevice, in menu: NSMenu) {
        let session = model.mirrors.session(for: application, device: device)
        let suffix = session.map { $0.phase == .starting ? L10n.text(" · 正在打开…") : $0.phase == .stopping ? L10n.text(" · 正在关闭…") : "" } ?? ""
        let entry = item(application.name + suffix, enabled: model.connectionError == nil && (session == nil || session?.phase == .running), in: menu) { [weak self] in self?.model.openApplication(application, on: device) }
        entry.state = session?.phase == .running ? .on : .off
        entry.toolTip = "\(application.packageName)\n\(session == nil ? L10n.text("在独立窗口打开；手机可同时使用其他应用") : L10n.text("显示已有窗口"))"
    }

    private func buildDisplays(_ device: AndroidDevice, in menu: NSMenu) {
        let preparing = model.preparing.contains(device.id)
        let selection = model.savedSelection(for: device) ?? .automatic
        let automatic = item(L10n.text("自动跟随当前屏幕"), enabled: !preparing && model.connectionError == nil, in: menu) { [weak self] in self?.model.activateFromMenu(device, selection: .automatic) }
        automatic.state = selection == .automatic ? .on : .off
        automatic.toolTip = L10n.text("选择后立即开启或切换镜像；折叠时跟随内外屏")
        menu.addItem(.separator())
        if let snapshot = model.displays[device.id] {
            for display in snapshot.displays {
                let entry = item(display.title, enabled: display.enabled && !preparing && model.connectionError == nil, in: menu) { [weak self] in self?.model.activateFromMenu(device, selection: .fixed(display.id)) }
                entry.subtitle = "\(display.resolution) · \(display.status)"
                entry.state = selection == .fixed(display.id) ? .on : .off
            }
        } else { note(preparing ? L10n.text("正在读取屏幕…") : L10n.text("尚未读取屏幕"), in: menu) }
        if model.menuDisplayErrors[device.id] != nil { note(L10n.text("读取失败，可重新读取屏幕"), in: menu) }
        menu.addItem(.separator())
        item(preparing ? L10n.text("正在读取屏幕…") : L10n.text("重新读取屏幕"), enabled: !preparing, in: menu) { [weak self] in self?.model.loadDisplaysForMenu(device, force: true) }
    }

    private func buildWindows(_ menu: NSMenu) {
        for session in model.mirrors.sessions.values.sorted(by: { $0.id < $1.id }) {
            let title = session.application?.name ?? L10n.text("屏幕 \(session.displayID) 镜像")
            let entry = item(title, enabled: session.phase == .running, in: menu) { [weak self] in
                guard let current = self?.model.mirrors.sessions[session.id] else { return }
                self?.model.presentMirror(current)
            }
            entry.subtitle = "\(session.device.name)\(session.phase == .starting ? L10n.text(" · 正在打开…") : session.phase == .stopping ? L10n.text(" · 正在关闭…") : "")"
        }
        menu.addItem(.separator())
        item(L10n.text("关闭所有镜像与应用窗口"), in: menu) { [weak self] in
            guard let self else { return }
            for id in Array(model.mirrors.sessions.keys) { model.cancelLaunch(id) }
        }
    }

    @discardableResult
    private func item(_ title: String, symbol: String? = nil, key: String = "", enabled: Bool = true,
                      in menu: NSMenu, action: (() -> Void)? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action == nil ? nil : #selector(performAction(_:)), keyEquivalent: key)
        item.target = self
        if let action { item.representedObject = MenuAction(action) }
        item.isEnabled = enabled
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        menu.addItem(item)
        return item
    }

    private func note(_ title: String, in menu: NSMenu) { item(title, enabled: false, in: menu) }
    @objc private func performAction(_ sender: NSMenuItem) { (sender.representedObject as? MenuAction)?.perform() }
}
