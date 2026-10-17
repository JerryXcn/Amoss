import Foundation
import Observation
import XCTest
@testable import AmossCore

final class LocalizationTests: XCTestCase {
    func testSystemPrimaryLanguageAndFallback() {
        for language in ["zh", "zh-CN", "zh-Hans", "zh-Hant-TW", "zh_HK", "ZH-cn"] {
            XCTAssertEqual(AppLanguage.resolve(.system, preferredLanguages: [language]), .chinese)
        }
        for languages in [["en"], ["en-GB"], ["fr-FR", "zh-Hans"], ["ja"], ["de", "en"], []] {
            XCTAssertEqual(AppLanguage.resolve(.system, preferredLanguages: languages), .english)
        }
        XCTAssertEqual(AppLanguage.resolve(.english, preferredLanguages: ["zh-CN"]), .english)
        XCTAssertEqual(AppLanguage.resolve(.chinese, preferredLanguages: ["en-US"]), .chinese)
    }

    func testSelectionPersistsAndSystemUpdatesOnlyAffectAutomaticChoice() {
        let name = "Amoss.LanguageTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = LanguageSettings(defaults: defaults, preferredLanguages: ["zh-Hant"])
        XCTAssertEqual(settings.selection, .system)
        XCTAssertEqual(settings.resolved, .chinese)
        settings.setSelection(.english)
        XCTAssertEqual(LanguageSettings(defaults: defaults, preferredLanguages: ["zh"]).selection, .english)
        settings.systemLanguageChanged(["zh-CN"])
        XCTAssertEqual(settings.resolved, .english)
        settings.setSelection(.system)
        settings.systemLanguageChanged(["fr", "zh"])
        XCTAssertEqual(settings.resolved, .english)
        settings.systemLanguageChanged(["zh-TW"])
        XCTAssertEqual(settings.resolved, .chinese)
        defaults.set("unknown", forKey: LanguageSettings.preferenceKey)
        XCTAssertEqual(LanguageSettings(defaults: defaults).selection, .system)
    }

    func testRemoteHelperUpdateDoesNotWritePreferences() {
        let name = "Amoss.LanguageTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("en", forKey: LanguageSettings.preferenceKey)
        let settings = LanguageSettings(defaults: defaults)
        settings.applyRemote(selection: .system, preferredLanguages: ["zh-Hans"])
        XCTAssertEqual(settings.resolved, .chinese)
        XCTAssertEqual(defaults.string(forKey: LanguageSettings.preferenceKey), "en")
    }

    func testObservableLanguageInvalidatesExistingViews() async {
        let name = "Amoss.LanguageTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = LanguageSettings(defaults: defaults, preferredLanguages: ["en"])
        let changed = expectation(description: "Existing view is invalidated")
        withObservationTracking {
            _ = settings.resolved
        } onChange: {
            changed.fulfill()
        }
        settings.setSelection(.chinese)
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(settings.resolved, .chinese)
    }

    func testCatalogCoverageAndPlaceholders() throws {
        let english = L10n.catalog(for: .english)
        let chinese = L10n.catalog(for: .chinese)
        XCTAssertGreaterThan(english.count, 250)
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        let pattern = try NSRegularExpression(pattern: #"\{\d+\}"#)
        func placeholders(_ value: String) -> [String] {
            let string = value as NSString
            return pattern.matches(in: value, range: NSRange(location: 0, length: string.length))
                .map { string.substring(with: $0.range) }.sorted()
        }
        for (key, value) in english {
            XCTAssertFalse(value.isEmpty, key)
            XCTAssertEqual(placeholders(key), placeholders(value), key)
            XCTAssertEqual(chinese[key], key)
        }
    }

    func testBothLanguagesAndOpaqueInterpolationArguments() {
        XCTAssertEqual(L10n.text("设置", language: .english), "Settings")
        XCTAssertEqual(L10n.text("设置", language: .chinese), "设置")
        let deviceName = "手机 {1} %@ 🙂"
        XCTAssertEqual(L10n.text("\(deviceName) · 屏幕 \(7) — Amoss", language: .english),
                       "手机 {1} %@ 🙂 · Display 7 — Amoss")
        XCTAssertEqual(L10n.text("\(deviceName) · 屏幕 \(7) — Amoss", language: .chinese),
                       "手机 {1} %@ 🙂 · 屏幕 7 — Amoss")
    }
}
