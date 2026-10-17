import AppKit
import Observation
#if canImport(AmossCore)
import AmossCore
#endif

@MainActor @Observable
final class Preferences {
    private let defaults: UserDefaults
    var quality: MirrorQuality { didSet { defaults.set(quality.rawValue, forKey: "quality") } }
    var audio: Bool { didSet { defaults.set(audio, forKey: "audio") } }
    var stayAwake: Bool { didSet { defaults.set(stayAwake, forKey: "stayAwake") } }
    var language: AppLanguage {
        get { L10n.settings.selection }
        set { L10n.settings.setSelection(newValue) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["quality": "balanced", "audio": true, "stayAwake": false])
        quality = MirrorQuality(rawValue: defaults.string(forKey: "quality") ?? "balanced") ?? .balanced
        audio = defaults.bool(forKey: "audio")
        stayAwake = defaults.bool(forKey: "stayAwake")
    }

    var options: MirrorOptions { .init(quality: quality, audio: audio, stayAwake: stayAwake) }
}

@MainActor @Observable
final class AppModel {
    let preferences = Preferences()
    let mirrors = MirrorSessionStore()
    let clipboard = ClipboardSyncStore()
    private(set) var devices: [AndroidDevice] = []
    private(set) var refreshing = false
    private(set) var hasScanned = false
    private(set) var connectionError: String?
    private(set) var tools: Toolchain?
    var authorizationDevice: AndroidDevice?
    var showingHelp = false
    var detailDevice: AndroidDevice?
    var notice: String?
    var displayRequest: AndroidDevice?
    private(set) var displays: [String: DisplaySnapshot] = [:]
    private(set) var preparing = Set<String>()
    var displayError: String?
    private(set) var menuDisplayErrors: [String: String] = [:]
    private(set) var expandedApplicationDeviceIDs = Set<String>()
    var applicationSearches: [String: String] = [:]
    private(set) var applications: [String: [AndroidApplication]] = [:]
    private(set) var loadingApplications = Set<String>()
    private(set) var applicationErrors: [String: String] = [:]
    @ObservationIgnored var onMenuError: ((String, String) -> Void)?
    @ObservationIgnored private var applicationTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var scanLoop: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var preparations: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var lastDisplayRefresh = Date.distantPast
    @ObservationIgnored private let windowCoordinator = MirrorWindowCoordinator()

    init() {
        do { tools = try Toolchain.bundled() }
        catch { connectionError = error.localizedDescription }
        mirrors.onWindowReady = { [weak self] session in self?.presentMirror(session) }
    }

    func start() {
        guard scanLoop == nil else { return }
        scanLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
            }
        }
    }

    func refresh() async {
        guard !refreshing, let tools else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let result = try await DeviceDiscovery.scan(using: tools)
            try Task.checkCancellation()
            let removed = devices.filter { old in !result.devices.contains { $0.id == old.id } }
            devices = result.devices
            hasScanned = true
            connectionError = nil
            mirrors.reconcile(devices)
            clipboard.reconcile(devices, tools: tools)
            if let device = removed.first { showNotice(L10n.text("\(device.name) 已断开连接")) }
            if let auth = authorizationDevice,
               devices.first(where: { $0.id == auth.id })?.state != .unauthorized {
                authorizationDevice = nil
            }
            for device in removed {
                preparations[device.id]?.cancel()
                displays.removeValue(forKey: device.id)
                menuDisplayErrors.removeValue(forKey: device.id)
                if displayRequest?.id == device.id { displayRequest = nil }
            }
            for id in Array(applicationTasks.keys) where !devices.contains(where: { $0.id == id && $0.state == .ready }) {
                applicationTasks[id]?.cancel()
            }
            for device in removed {
                applications.removeValue(forKey: device.id)
                applicationErrors.removeValue(forKey: device.id)
                applicationSearches.removeValue(forKey: device.id)
            }
            expandedApplicationDeviceIDs.formIntersection(devices.filter { $0.state == .ready }.map(\.id))
            // Only retry explicitly expanded lists. Discovery must never reopen
            // a list that the user has collapsed.
            for device in devices where expandedApplicationDeviceIDs.contains(device.id) &&
                applications[device.id] == nil && applicationErrors[device.id] == nil {
                refreshApplications(device)
            }
            await refreshDisplayStates()
        } catch is CancellationError { }
        catch {
            connectionError = error.localizedDescription
            hasScanned = true
            clipboard.connectionUnavailable()
        }
    }

    func activate(_ device: AndroidDevice) {
        if device.state == .unauthorized { authorizationDevice = device; return }
        guard device.state == .ready, connectionError == nil, tools != nil else { return }
        if let session = mirrors.sessions[device.id] {
            guard session.phase != .stopping else { return }
            presentMirror(session)
            return
        }
        prepare(device, alwaysChoose: false)
    }

    func presentMirror(_ session: MirrorSession) {
        let display = displays[session.device.id]?.displays.first { $0.id == session.displayID }
        let fallback = MirrorWindowMetrics(videoWidth: Double(display?.width ?? 1080),
                                           videoHeight: Double(display?.height ?? 1920))
        windowCoordinator.present(session, fallback: fallback)
    }

    func toggleApplications(_ device: AndroidDevice) {
        guard device.state == .ready else { return }
        if expandedApplicationDeviceIDs.remove(device.id) != nil { return }
        expandedApplicationDeviceIDs.insert(device.id)
        if applications[device.id] == nil { refreshApplications(device) }
    }

    func refreshApplications(_ device: AndroidDevice) {
        guard let tools, device.state == .ready, !loadingApplications.contains(device.id) else { return }
        loadingApplications.insert(device.id)
        applicationErrors.removeValue(forKey: device.id)
        applicationTasks[device.id] = Task { [weak self] in
            guard let self else { return }
            defer { loadingApplications.remove(device.id); applicationTasks.removeValue(forKey: device.id) }
            do {
                let result = try await ApplicationDiscovery.list(device: device, tools: tools)
                try Task.checkCancellation()
                guard devices.contains(where: { $0.id == device.id && $0.state == .ready }) else { return }
                applications[device.id] = result
            } catch is CancellationError { }
            catch { applicationErrors[device.id] = error.localizedDescription }
        }
    }

    func openApplication(_ application: AndroidApplication, on device: AndroidDevice) {
        guard let tools, connectionError == nil,
              devices.contains(where: { $0.id == device.id && $0.state == .ready }) else { return }
        if let session = mirrors.session(for: application, device: device) {
            if session.phase != .stopping { presentMirror(session) }
            return
        }
        var recent = UserDefaults.standard.stringArray(forKey: "recentApps.\(device.id)") ?? []
        recent.removeAll { $0 == application.id }
        recent.insert(application.id, at: 0)
        UserDefaults.standard.set(Array(recent.prefix(5)), forKey: "recentApps.\(device.id)")
        mirrors.start(device, tools: tools, options: preferences.options,
                      presentation: windowCoordinator.placement(metrics: .init(videoWidth: 1080, videoHeight: 1920)),
                      application: application)
    }

    func chooseDisplay(_ device: AndroidDevice) { prepare(device, alwaysChoose: true) }

    func cancelLaunch(_ serial: String) {
        preparations[serial]?.cancel()
        mirrors.stop(serial)
    }

    func savedSelection(for device: AndroidDevice) -> DisplaySelection? {
        DisplaySelection(stored: UserDefaults.standard.string(forKey: "display.\(device.serial)"))
    }

    func activateFromMenu(_ device: AndroidDevice, selection: DisplaySelection? = nil) {
        guard device.state == .ready, connectionError == nil else { return }
        if selection == nil, let session = mirrors.sessions[device.id] {
            if session.phase != .stopping { presentMirror(session) }
            return
        }
        prepare(device, alwaysChoose: false, menuSelection: selection, fromMenu: true)
    }

    func loadDisplaysForMenu(_ device: AndroidDevice, force: Bool = false) {
        guard let tools, device.state == .ready, !preparing.contains(device.id),
              force || displays[device.id] == nil else { return }
        preparing.insert(device.id)
        menuDisplayErrors.removeValue(forKey: device.id)
        preparations[device.id] = Task { [weak self] in
            guard let self else { return }
            defer { preparing.remove(device.id); preparations.removeValue(forKey: device.id) }
            do {
                let snapshot = try await DisplayProbe.list(device: device, tools: tools)
                try Task.checkCancellation()
                guard devices.contains(where: { $0.id == device.id && $0.state == .ready }) else { return }
                displays[device.id] = snapshot
                menuDisplayErrors.removeValue(forKey: device.id)
            } catch is CancellationError { }
            catch { menuDisplayErrors[device.id] = error.localizedDescription }
        }
    }

    private func prepare(_ device: AndroidDevice, alwaysChoose: Bool,
                         menuSelection: DisplaySelection? = nil, fromMenu: Bool = false) {
        guard let tools, !preparing.contains(device.id) else { return }
        preparing.insert(device.id)
        displayError = nil
        preparations[device.id] = Task { [weak self] in
            guard let self else { return }
            defer { preparing.remove(device.id); preparations.removeValue(forKey: device.id) }
            do {
                let snapshot = try await DisplayProbe.list(device: device, tools: tools)
                try Task.checkCancellation()
                guard devices.contains(where: { $0.id == device.id && $0.state == .ready }) else { return }
                displays[device.id] = snapshot
                if !fromMenu && (alwaysChoose || (snapshot.displays.count > 1 && savedSelection(for: device) == nil)) {
                    displayRequest = device
                } else {
                    let choice = menuSelection ?? savedSelection(for: device) ?? .automatic
                    if let display = choice.resolve(in: snapshot) {
                        if fromMenu { UserDefaults.standard.set(choice.storageValue, forKey: "display.\(device.id)") }
                        await launch(device, display: display, selection: choice)
                    } else if fromMenu {
                        onMenuError?(L10n.text("请选择镜像屏幕"), L10n.text("未能确定当前屏幕，请在菜单栏的设备菜单中展开「镜像屏幕」，按编号和分辨率选择。"))
                    } else { displayRequest = device }
                }
            } catch is CancellationError { }
            catch {
                displayError = error.localizedDescription
                if fromMenu { onMenuError?(L10n.text("未能读取屏幕"), error.localizedDescription) }
                else { showNotice(L10n.text("未能读取屏幕，请重试")); displayRequest = device }
            }
        }
    }

    func startDisplay(_ device: AndroidDevice, selection: DisplaySelection) {
        guard let snapshot = displays[device.id], let display = selection.resolve(in: snapshot),
              !preparing.contains(device.id) else { return }
        UserDefaults.standard.set(selection.storageValue, forKey: "display.\(device.serial)")
        displayRequest = nil
        preparing.insert(device.id)
        preparations[device.id] = Task { [weak self] in
            guard let self else { return }
            defer { preparing.remove(device.id); preparations.removeValue(forKey: device.id) }
            await launch(device, display: display, selection: selection)
        }
    }

    private func launch(_ device: AndroidDevice, display: AndroidDisplay, selection: DisplaySelection,
                        options: MirrorOptions? = nil) async {
        guard let tools else { return }
        if let current = mirrors.sessions[device.id] {
            if current.displayID == display.id && current.phase == .running &&
                current.followsActiveDisplay == (selection == .automatic) {
                activate(device); return
            }
            mirrors.stop(device.id)
            for _ in 0..<25 {
                if mirrors.sessions[device.id] == nil { break }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
        guard !Task.isCancelled, devices.contains(where: { $0.id == device.id && $0.state == .ready }),
              mirrors.sessions[device.id] == nil else { return }
        var launchOptions = options ?? preferences.options
        if options == nil {
            launchOptions.startWithScreenOff = display.state == "OFF" || display.state?.hasPrefix("DOZE") == true
        }
        mirrors.start(device, tools: tools, options: launchOptions,
                      displayID: display.id, followsActiveDisplay: selection == .automatic,
                      presentation: windowCoordinator.placement(metrics: .init(
                        videoWidth: Double(display.width), videoHeight: Double(display.height))))
    }

    private func refreshDisplayStates() async {
        guard let tools, Date().timeIntervalSince(lastDisplayRefresh) >= 3 else { return }
        lastDisplayRefresh = Date()
        let targets = devices.filter {
            (mirrors.sessions[$0.id] != nil || displayRequest?.id == $0.id) &&
            (displays[$0.id]?.displays.count ?? 0) > 1 && !preparing.contains($0.id)
        }
        for device in targets {
            guard let known = displays[device.id],
                  let snapshot = try? await DisplayProbe.refresh(device: device, displays: known.displays, tools: tools),
                  !Task.isCancelled else { continue }
            displays[device.id] = snapshot
            if let session = mirrors.sessions[device.id], session.followsActiveDisplay,
               session.phase == .running,
               let active = snapshot.automaticDisplay(keeping: session.displayID), active.id != session.displayID {
                showNotice(L10n.text("屏幕已切换，正在打开\(active.title)…"))
                await launch(device, display: active, selection: .automatic, options: session.options)
            }
        }
    }

    func showNotice(_ text: String) {
        noticeTask?.cancel()
        notice = text
        noticeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            self?.notice = nil
        }
    }

    func shutdown() {
        scanLoop?.cancel()
        scanLoop = nil
        noticeTask?.cancel()
        for task in preparations.values { task.cancel() }
        for task in applicationTasks.values { task.cancel() }
        mirrors.shutdown()
        clipboard.shutdown()
    }
}
