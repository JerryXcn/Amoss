import Foundation

public enum DeviceState: String, Sendable, Codable {
    case ready = "device"
    case unauthorized, offline, recovery, sideload, bootloader
    case noPermissions = "no permissions"
    case unknown

    public var label: String {
        switch self {
        case .ready: L10n.text("就绪")
        case .unauthorized: L10n.text("待授权")
        case .offline: L10n.text("离线")
        case .recovery: L10n.text("恢复模式")
        case .sideload: L10n.text("更新模式")
        case .bootloader: L10n.text("引导模式")
        case .noPermissions: L10n.text("无法访问")
        case .unknown: L10n.text("尚未就绪")
        }
    }
}

public struct AndroidDevice: Identifiable, Equatable, Sendable {
    public var id: String { serial }
    public let serial: String
    public var state: DeviceState
    public var model: String?
    public var usbPath: String?
    public var transportID: String?

    public init(serial: String, state: DeviceState, model: String? = nil,
                usbPath: String? = nil, transportID: String? = nil) {
        self.serial = serial
        self.state = state
        self.model = model
        self.usbPath = usbPath
        self.transportID = transportID
    }

    public var name: String {
        guard state != .unauthorized, let model, !model.isEmpty else { return L10n.text("Android 设备") }
        return model.replacingOccurrences(of: "_", with: " ")
    }

    public var isUSB: Bool { usbPath?.isEmpty == false }
    public var selector: [String] {
        if let transportID { return ["-t", transportID] }
        return ["-s", serial]
    }
}

public enum ADBDeviceParser {
    /// Keep transport identity separate from a display name. Never assume that a
    /// serial without an IP address is USB: mDNS transports also have serials.
    public static func parse(_ output: String) -> [AndroidDevice] {
        var seen = Set<String>()
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2,
                  !line.hasPrefix("List of devices"), !line.hasPrefix("*"),
                  let state = DeviceState(rawValue: fields[1]) ??
                    (fields[1] == "no" && fields.dropFirst(2).first == "permissions" ? .noPermissions : nil),
                  seen.insert(fields[0]).inserted else { return nil }
            var values: [String: String] = [:]
            for field in fields.dropFirst(2) {
                let pair = field.split(separator: ":", maxSplits: 1).map(String.init)
                if pair.count == 2 { values[pair[0]] = pair[1] }
            }
            return AndroidDevice(serial: fields[0], state: state,
                                 model: values["model"], usbPath: values["usb"],
                                 transportID: values["transport_id"])
        }
    }

    public static func usbPath(fromDevPath output: String) -> String? {
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("usb:"), value.count > 4 else { return nil }
        return String(value.dropFirst(4))
    }
}
