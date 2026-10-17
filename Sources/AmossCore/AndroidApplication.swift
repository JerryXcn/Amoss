import Foundation

public struct AndroidApplication: Identifiable, Equatable, Sendable {
    public let packageName: String
    public let name: String
    public let isSystem: Bool
    public var id: String { packageName }

    public init(packageName: String, name: String, isSystem: Bool = false) {
        self.packageName = packageName
        self.name = name
        self.isSystem = isSystem
    }

    public var isValid: Bool {
        packageName.range(of: #"^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+$"#,
                          options: .regularExpression) != nil
    }

    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || name.localizedStandardContains(query) || packageName.localizedStandardContains(query)
    }
}

public enum ApplicationDiscovery {
    public static func list(device: AndroidDevice, tools: Toolchain) async throws -> [AndroidApplication] {
        let result = try await CommandRunner.run(tools.scrcpy,
            ["--serial=\(device.serial)", "--list-apps"], environment: tools.environment, timeout: .seconds(30))
        guard result.exitCode == 0, result.output.contains("List of apps:") else {
            throw ApplicationDiscoveryError.failed(ScrcpyLog.failureMessage(result.output))
        }
        return parse(result.output)
    }

    /// scrcpy wraps the package onto a second line for labels of 30+ UTF-16 characters.
    public static func parse(_ output: String) -> [AndroidApplication] {
        var apps: [String: AndroidApplication] = [:]
        var pending: (name: String, system: Bool)?
        var inList = false
        for raw in output.components(separatedBy: .newlines) {
            if raw.contains("List of apps:") { inList = true; continue }
            guard inList else { continue }
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("* ") || line.hasPrefix("- ") {
                let label = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                let fields = label.split(whereSeparator: \.isWhitespace)
                if let last = fields.last, fields.count >= 2,
                   let range = label.range(of: String(last), options: .backwards) {
                    let name = String(label[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let app = AndroidApplication(packageName: String(last), name: name, isSystem: line.hasPrefix("*"))
                    if app.isValid { apps[app.id] = app; pending = nil; continue }
                }
                pending = (label, line.hasPrefix("*"))
            } else if let entry = pending {
                let app = AndroidApplication(packageName: line, name: entry.name, isSystem: entry.system)
                if app.isValid { apps[app.id] = app }
                pending = nil
            }
        }
        return apps.values.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.packageName < $1.packageName : order == .orderedAscending
        }
    }
}

public enum ApplicationDiscoveryError: LocalizedError {
    case failed(String)
    public var errorDescription: String? {
        switch self { case .failed(let detail): L10n.text("无法读取应用列表。\n\(detail)") }
    }
}
