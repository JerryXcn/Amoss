import Foundation

public struct AndroidDisplay: Identifiable, Equatable, Sendable {
    public let id: Int
    public var width: Int
    public var height: Int
    public var name: String?
    public var kind: String?
    public var state: String?
    public var enabled: Bool = true

    public init(id: Int, width: Int, height: Int, name: String? = nil,
                kind: String? = nil, state: String? = nil, enabled: Bool = true) {
        self.id = id; self.width = width; self.height = height
        self.name = name; self.kind = kind; self.state = state; self.enabled = enabled
    }

    public var title: String { L10n.text("屏幕 \(id)") }
    public var resolution: String { "\(width) × \(height)" }
    public var isOn: Bool { enabled && state == "ON" }
    public var status: String {
        guard enabled else { return L10n.text("未启用") }
        switch state {
        case "ON": return L10n.text("正在使用")
        case "OFF": return L10n.text("已熄屏")
        case "DOZE", "DOZE_SUSPEND": return L10n.text("息屏显示")
        default: return L10n.text("状态未知")
        }
    }
}

public struct DisplaySnapshot: Equatable, Sendable {
    public var displays: [AndroidDisplay]
    public var posture: String?
    /// Enabled screens in Android's current fold-state layout, independent of
    /// whether their physical panels are illuminated.
    public var activeLayoutIDs: Set<Int>

    public init(displays: [AndroidDisplay], posture: String? = nil, activeLayoutIDs: Set<Int> = []) {
        self.displays = displays; self.posture = posture; self.activeLayoutIDs = activeLayoutIDs
    }

    /// Prefer an illuminated physical display. An inactive foldable screen is
    /// never inferred from its ID or size; vendor numbering is not standardized.
    public func automaticDisplay(keeping currentID: Int? = nil) -> AndroidDisplay? {
        let physical = displays.filter { $0.kind != "VIRTUAL" && $0.enabled }
        let on = physical.filter(\.isOn)
        if let currentID, let current = on.first(where: { $0.id == currentID }) { return current }
        if let only = on.first, on.count == 1 { return only }
        if let primary = on.first(where: { $0.id == 0 }) { return primary }
        if let first = on.first { return first }
        let active = physical.filter { activeLayoutIDs.contains($0.id) }
        if active.count == 1 { return active.first }
        if let currentID, let current = physical.first(where: { $0.id == currentID }),
           activeLayoutIDs.isEmpty || activeLayoutIDs.contains(currentID) { return current }
        if physical.count == 1 { return physical.first }
        if displays.count == 1 && displays[0].enabled { return displays[0] }
        return nil
    }
}

public enum DisplaySelection: Equatable, Sendable {
    case automatic
    case fixed(Int)
    public var storageValue: String {
        switch self { case .automatic: "auto"; case .fixed(let id): String(id) }
    }
    public init?(stored: String?) {
        guard let stored else { return nil }
        if stored == "auto" { self = .automatic }
        else if let id = Int(stored), id >= 0 { self = .fixed(id) }
        else { return nil }
    }
    public func resolve(in snapshot: DisplaySnapshot) -> AndroidDisplay? {
        switch self {
        case .automatic: snapshot.automaticDisplay()
        case .fixed(let id): snapshot.displays.first { $0.id == id && $0.enabled }
        }
    }
}

public enum DisplayParser {
    public static func scrcpyList(_ output: String) -> [AndroidDisplay] {
        captures(#"--display-id=(\d+)\s+\((\d+)x(\d+)\)"#, in: output).compactMap { values in
            guard let id = Int(values[0]), let width = Int(values[1]), let height = Int(values[2]),
                  width > 0, height > 0 else { return nil }
            return AndroidDisplay(id: id, width: width, height: height)
        }.sorted { $0.id < $1.id }
    }

    public static func enrich(_ displays: [AndroidDisplay], dumpsys: String) -> DisplaySnapshot {
        let lines = dumpsys.components(separatedBy: .newlines)
        var metadata: [Int: String] = [:]
        var physical: [String: String] = [:]
        for line in lines {
            if line.contains("mBaseDisplayInfo=DisplayInfo"),
               let value = captures(#"displayId (\d+)"#, in: line).first?.first, let id = Int(value) {
                metadata[id] = line
            }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("DisplayDeviceInfo{"),
               let uniqueID = captures(#"uniqueId="([^"]+)""#, in: line).first?.first {
                physical[uniqueID] = line
            }
        }
        let updated = displays.compactMap { original -> AndroidDisplay? in
            var display = original
            // Android 16 may expose the capture helper as another display. It
            // disappears when mirroring restarts and is not a usable source.
            if display.kind == "VIRTUAL", display.name == "scrcpy" { return nil }
            guard let base = metadata[display.id] else { return display }
            display.name = captures(#"DisplayInfo\{"([^"]+)""#, in: base).first?.first
            display.kind = captures(#", type ([A-Z_]+)"#, in: base).first?.first
            if display.kind == "VIRTUAL", display.name == "scrcpy" { return nil }
            let uniqueID = captures(#"uniqueId "([^"]+)""#, in: base).first?.first
            let physicalInfo = uniqueID.flatMap { physical[$0] } ?? base
            // Physical power state is authoritative. Some OEMs keep an inactive
            // logical override ON even while the folded panel is actually OFF.
            display.state = captures(#", state ([A-Z_]+)"#, in: physicalInfo).first?.first
            return display
        }
        let posture = captures(#"mDeviceState=DeviceState\{[^\n]*name='([^']+)'"#, in: dumpsys).first?.first
        // Only the current layout is authoritative. Other dump sections also
        // describe layouts for different fold states and must not be merged.
        let layout = lines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("mCurrentLayout=") } ?? ""
        let activeIDs = Set(captures(#"dispId:\s*(\d+)\(ON\)"#, in: layout).compactMap { Int($0[0]) })
        return DisplaySnapshot(displays: updated, posture: posture, activeLayoutIDs: activeIDs)
    }

    private static func captures(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (1..<match.numberOfRanges).map { ns.substring(with: match.range(at: $0)) }
        }
    }
}

public enum DisplayProbe {
    public static func list(device: AndroidDevice, tools: Toolchain) async throws -> DisplaySnapshot {
        let result = try await CommandRunner.run(tools.scrcpy,
            ["--serial=\(device.serial)", "--list-displays"], environment: tools.environment, timeout: .seconds(12))
        let displays = DisplayParser.scrcpyList(result.output)
        guard result.exitCode == 0, !displays.isEmpty else {
            throw DiscoveryError.adb(L10n.text("无法读取可镜像的屏幕。请检查 USB 连接与调试授权后重试。\n\(result.output)"))
        }
        return try await refresh(device: device, displays: displays, tools: tools)
    }

    public static func refresh(device: AndroidDevice, displays: [AndroidDisplay], tools: Toolchain) async throws -> DisplaySnapshot {
        let result = try await CommandRunner.run(tools.adb,
            ["-s", device.serial, "shell", "dumpsys", "display"], environment: tools.environment)
        guard result.exitCode == 0 else { return DisplaySnapshot(displays: displays) }
        return DisplayParser.enrich(displays, dumpsys: result.output)
    }
}
