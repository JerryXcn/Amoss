import Foundation
import Observation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, chinese = "zh-Hans", english = "en"
    public var id: Self { self }
    public static func resolve(_ selection: Self, preferredLanguages: [String]) -> Self {
        guard selection == .system else { return selection }
        let first = preferredLanguages.first?.replacingOccurrences(of: "_", with: "-").lowercased() ?? ""
        return first == "zh" || first.hasPrefix("zh-") ? .chinese : .english
    }
}

/// A single observable language setting also used from background error paths.
/// The lock protects stored values; Observation invalidates only views that read them.
public final class LanguageSettings: Observable, @unchecked Sendable {
    public static let preferenceKey = "appLanguage"
    public static let changed = Notification.Name("com.amoss.languageChanged")
    private let registrar = ObservationRegistrar()
    private let lock = NSLock()
    private let defaults: UserDefaults
    private let notify: Bool
    private var storedSelection: AppLanguage
    private var systemLanguages: [String]

    public init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages,
                initialSelection: AppLanguage? = nil, notify: Bool = false) {
        self.defaults = defaults
        self.notify = notify
        storedSelection = initialSelection ?? AppLanguage(rawValue: defaults.string(forKey: Self.preferenceKey) ?? "") ?? .system
        systemLanguages = preferredLanguages
    }

    public var selection: AppLanguage {
        registrar.access(self, keyPath: \.selection)
        return lock.withLock { storedSelection }
    }
    public var resolved: AppLanguage {
        registrar.access(self, keyPath: \.selection)
        return lock.withLock { AppLanguage.resolve(storedSelection, preferredLanguages: systemLanguages) }
    }

    public func setSelection(_ value: AppLanguage) {
        guard value != selection else { return }
        update(selection: value, preferredLanguages: nil)
        defaults.set(value.rawValue, forKey: Self.preferenceKey)
        if notify { NotificationCenter.default.post(name: Self.changed, object: nil) }
    }

    public func systemLanguageChanged(_ preferredLanguages: [String] = Locale.preferredLanguages) {
        update(selection: selection, preferredLanguages: preferredLanguages)
        if notify { NotificationCenter.default.post(name: Self.changed, object: nil) }
    }

    /// Mirroring helpers receive the selection without writing it back or rebroadcasting.
    public func applyRemote(selection: AppLanguage, preferredLanguages: [String]) {
        update(selection: selection, preferredLanguages: preferredLanguages)
    }

    private func update(selection: AppLanguage, preferredLanguages: [String]?) {
        registrar.withMutation(of: self, keyPath: \.selection) {
            lock.withLock {
                storedSelection = selection
                if let preferredLanguages { systemLanguages = preferredLanguages }
            }
        }
    }
}

/// Preserve interpolation arguments as data. Never translate device/app names,
/// protocol arguments, diagnostic output, or copied text.
public struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
    public let key: String
    public let arguments: [String]
    public init(stringLiteral value: String) { key = value; arguments = [] }
    public init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key; arguments = stringInterpolation.arguments
    }
    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity)
            arguments.reserveCapacity(interpolationCount)
        }
        public mutating func appendLiteral(_ literal: String) { key += literal }
        public mutating func appendInterpolation<T>(_ value: T) {
            key += "{\(arguments.count)}"
            arguments.append(String(describing: value))
        }
    }
}

public enum L10n {
    public static let settings = LanguageSettings(
        initialSelection: ProcessInfo.processInfo.environment["AMOSS_LANGUAGE"].flatMap(AppLanguage.init(rawValue:)),
        notify: true)

    public static func text(_ message: LocalizedMessage) -> String {
        text(message, language: settings.resolved)
    }

    public static func text(_ message: LocalizedMessage, language: AppLanguage) -> String {
        let resolved = AppLanguage.resolve(language, preferredLanguages: Locale.preferredLanguages)
        let template = catalog(for: resolved)[message.key] ?? english[message.key] ?? message.key
        return interpolate(template, arguments: message.arguments)
    }

    public static func catalog(for language: AppLanguage) -> [String: String] {
        language == .chinese ? chinese : english
    }

    private static let english = load("en")
    private static let chinese = load("zh-Hans")
    private static func load(_ language: String) -> [String: String] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.resourceURL?.appendingPathComponent("\(language).lproj/Localizable.strings"),
              let data = try? Data(contentsOf: url),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let strings = value as? [String: String] else { return [:] }
        return strings
    }

    private static func interpolate(_ template: String, arguments: [String]) -> String {
        // Scan the template once, so a name containing "{1}" is not reinterpreted.
        var output = ""
        var position = template.startIndex
        while position < template.endIndex {
            if template[position] == "{", let end = template[position...].firstIndex(of: "}"),
               let index = Int(template[template.index(after: position)..<end]), arguments.indices.contains(index) {
                output += arguments[index]
                position = template.index(after: end)
            } else {
                output.append(template[position])
                position = template.index(after: position)
            }
        }
        return output
    }
}
