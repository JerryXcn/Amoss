import CryptoKit
import Foundation

/// Stores fingerprints, never clipboard history. Transport acknowledgements and
/// pasteboard change counts live outside the router.
public struct ClipboardRouting: Sendable {
    public struct Change: Equatable, Sendable {
        public var updateMac: Bool
        public var destinations: Set<String>
        public static let none = Self(updateMac: false, destinations: [])
    }
    private var devices: [String: String] = [:]
    private var macFingerprint: String?
    public init() {}

    public mutating func connect(_ id: String) { devices[id] = "" }
    public mutating func disconnect(_ id: String) { devices.removeValue(forKey: id) }

    public mutating func copiedOnMac(_ text: String) -> Change {
        let fingerprint = digest(text)
        macFingerprint = fingerprint
        return route(fingerprint, updateMac: false)
    }

    public mutating func copiedOnDevice(_ text: String, id: String) -> Change {
        guard let previous = devices[id] else { return .none }
        let fingerprint = digest(text)
        guard previous != fingerprint else { return .none } // Ignore our own echo.
        devices[id] = fingerprint
        let updateMac = fingerprint != macFingerprint
        macFingerprint = fingerprint
        return route(fingerprint, updateMac: updateMac)
    }

    /// Non-text copies must invalidate the Mac fingerprint too; a subsequent
    /// device copy can then replace that image/file with the intended text.
    public mutating func macContainsNonText() {
        macFingerprint = nil
        for id in devices.keys { devices[id] = "" }
    }

    private mutating func route(_ fingerprint: String, updateMac: Bool) -> Change {
        let destinations = Set(devices.keys.filter { devices[$0] != fingerprint })
        for id in destinations { devices[id] = fingerprint }
        return Change(updateMac: updateMac, destinations: destinations)
    }
    private func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Migrate the previous global preference as the initial choice only. Each
/// serial gets its own persisted value, including while disconnected.
public struct ClipboardDevicePreferences {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func isEnabled(_ id: String) -> Bool {
        if let value = defaults.object(forKey: "clipboard.device.\(id)") as? Bool { return value }
        return defaults.object(forKey: "clipboard") as? Bool ?? true
    }
    public func setEnabled(_ enabled: Bool, for id: String) {
        defaults.set(enabled, forKey: "clipboard.device.\(id)")
    }
}

/// Some Android builds deliver their clipboard listener after SET_CLIPBOARD's
/// acknowledgement. Suppress those delayed echoes, including a preceding write
/// while a newer copy is queued. Only short-lived hashes are retained.
public struct ClipboardEchoFilter: Sendable {
    private var writes: [(fingerprint: SHA256.Digest, date: Date)] = []
    public init() {}
    public mutating func sent(_ text: String, at date: Date = Date()) {
        writes.removeAll { date.timeIntervalSince($0.date) > 2 }
        writes.append((SHA256.hash(data: Data(text.utf8)), date))
        if writes.count > 16 { writes.removeFirst(writes.count - 16) }
    }
    public mutating func isEcho(_ text: String, at date: Date = Date()) -> Bool {
        writes.removeAll { date.timeIntervalSince($0.date) > 2 }
        let fingerprint = SHA256.hash(data: Data(text.utf8))
        if writes.contains(where: { $0.fingerprint == fingerprint }) { return true }
        // A different phone copy starts a new sequence of user changes.
        writes.removeAll()
        return false
    }
}
