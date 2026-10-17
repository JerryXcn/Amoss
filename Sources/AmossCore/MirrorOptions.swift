import Foundation

public enum MirrorQuality: String, CaseIterable, Identifiable, Sendable {
    case smooth, balanced, sharp
    public var id: Self { self }
    public var title: String {
        switch self { case .smooth: L10n.text("流畅"); case .balanced: L10n.text("均衡"); case .sharp: L10n.text("清晰") }
    }
    public var detail: String {
        switch self {
        case .smooth: L10n.text("最长边 1280 · 最高 30 fps")
        case .balanced: L10n.text("最长边 1920 · 最高 60 fps")
        case .sharp: L10n.text("原始分辨率 · 最高 60 fps")
        }
    }
    public var arguments: [String] {
        switch self {
        case .smooth: ["--max-size=1280", "--max-fps=30", "--video-bit-rate=4M"]
        case .balanced: ["--max-size=1920", "--max-fps=60", "--video-bit-rate=8M"]
        case .sharp: ["--max-size=0", "--max-fps=60", "--video-bit-rate=16M"]
        }
    }
}

public struct MirrorOptions: Equatable, Sendable {
    public var quality: MirrorQuality
    public var audio: Bool
    public var stayAwake: Bool
    public var startWithScreenOff: Bool

    public init(quality: MirrorQuality = .balanced, audio: Bool = true,
                stayAwake: Bool = false, startWithScreenOff: Bool = false) {
        self.quality = quality
        self.audio = audio
        self.stayAwake = stayAwake
        self.startWithScreenOff = startWithScreenOff
    }

    public func arguments(for device: AndroidDevice, displayID: Int = 0) -> [String] {
        // Autosync belongs exclusively to ClipboardSyncStore. Manual ⌘C/⌘V
        // still works without it; a running window cannot bypass its switch.
        var args = [
            "--serial=\(device.serial)",
            "--display-id=\(displayID)",
            "--window-title=" + L10n.text("\(device.name) · 屏幕 \(displayID) — Amoss"),
            "--window-height=800",
            "--shortcut-mod=lsuper,rsuper",
            "--keyboard=sdk", "--mouse=sdk",
            "--verbosity=info", "--no-clipboard-autosync"
        ] + quality.arguments
        if !audio { args.append("--no-audio") }
        if stayAwake || startWithScreenOff { args.append("--stay-awake") }
        if startWithScreenOff { args += ["--no-power-on", "--turn-screen-off"] }
        return args
    }

    public func arguments(for device: AndroidDevice, application: AndroidApplication) -> [String] {
        // Keep the device's native size/density for apps that assume phone metrics.
        // Audio, physical panel power and stay-awake settings belong to the phone.
        let args = ["--serial=\(device.serial)", "--new-display",
                    "--start-app=\(application.packageName)", "--no-vd-system-decorations",
                    "--display-ime-policy=local", "--no-power-on", "--no-audio",
                    "--window-title=\(application.name) · \(device.name) — Amoss",
                    "--window-height=800", "--shortcut-mod=lsuper,rsuper",
                    "--keyboard=sdk", "--mouse=sdk", "--no-mouse-hover", "--verbosity=info",
                    "--no-clipboard-autosync"] + quality.arguments
        return args
    }
}

public enum ScrcpyLog {
    /// The native toolbar and keyboard shortcuts report the latest requested
    /// panel state, allowing a fold-screen restart to preserve user intent.
    public static func requestedDisplayOff(_ log: String) -> Bool? {
        for line in log.components(separatedBy: .newlines).reversed() {
            if line == "INFO: Amoss display power: off" { return true }
            if line == "INFO: Amoss display power: on" { return false }
        }
        return nil
    }

    public static func hasVideo(_ log: String) -> Bool {
        log.contains("INFO: Texture:") || log.contains("INFO: Video texture:")
    }

    public static func failureMessage(_ log: String) -> String {
        if log.contains("Could not start app") || log.contains("No activity found") || log.contains("not launchable") {
            return L10n.text("这个应用未能在独立窗口中启动。可以刷新应用列表后重试，或尝试其他应用。")
        }
        if log.contains("Could not create virtual display") || log.contains("new-display is not supported") {
            return L10n.text("手机系统未能创建应用窗口。设备镜像仍可使用。")
        }
        if log.contains("unauthorized") {
            return L10n.text("请解锁手机，并在手机上允许 USB 调试，然后重试。")
        }
        if log.contains("INJECT_EVENTS") {
            return L10n.text("手机未允许输入控制。请检查开发者选项中的「USB 调试（安全设置）」，然后重新开启镜像。")
        }
        if log.contains("Could not find any ADB device") || log.contains("Device disconnected") {
            return L10n.text("设备已断开。请检查 USB 连接，然后重试。")
        }
        if log.localizedCaseInsensitiveContains("encoder") {
            return L10n.text("手机暂时无法启动视频编码。请将镜像画质调为「流畅」后重试。")
        }
        return L10n.text("请确认手机已解锁并允许 USB 调试，然后重试。可以在详情中查看运行日志。")
    }
}
