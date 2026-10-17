import Foundation
import AppKit
import XCTest
@testable import AmossCore

final class ClipboardProtocolTests: XCTestCase {
    func testSetTextUsesUTF8LengthBigEndianSequenceAndNeverPastes() throws {
        let bytes = try ClipboardProtocol.setText("中文🙂\n", sequence: 0x0102030405060708)
        XCTAssertEqual(Array(bytes.prefix(14)), [9, 1, 2, 3, 4, 5, 6, 7, 8, 0, 0, 0, 0, 11])
        XCTAssertEqual(String(data: bytes.dropFirst(14), encoding: .utf8), "中文🙂\n")
    }

    func testFragmentedAndCoalescedDeviceMessages() throws {
        var decoder = ClipboardProtocol.Decoder()
        let text = Data("手机\n🙂".utf8)
        let frame = Data([0, 0, 0, 0, UInt8(text.count)]) + text + Data([1, 0, 0, 0, 0, 0, 0, 0, 9])
        var messages: [ClipboardProtocol.Message] = []
        for byte in frame { messages += try decoder.append(Data([byte])) }
        XCTAssertEqual(messages, [.text("手机\n🙂"), .acknowledgement(9)])
        XCTAssertEqual(try decoder.append(frame + frame), messages + messages)
        XCTAssertTrue(try decoder.append(Data()).isEmpty)
    }

    func testRejectsOversizedInvalidAndUnknownFrames() {
        for bytes: [UInt8] in [[0, 0, 4, 0, 0], [0, 0, 0, 0, 1, 255], [99]] {
            var decoder = ClipboardProtocol.Decoder()
            XCTAssertThrowsError(try decoder.append(Data(bytes)))
        }
        XCTAssertThrowsError(try ClipboardProtocol.setText(String(repeating: "a", count: ClipboardProtocol.maximumTextBytes + 1), sequence: 1))
        XCTAssertNoThrow(try ClipboardProtocol.setText(String(repeating: "a", count: ClipboardProtocol.maximumTextBytes), sequence: 1))
    }

    func testEmptyTextDoesNotDesynchronizeFollowingAck() throws {
        var decoder = ClipboardProtocol.Decoder()
        XCTAssertEqual(try decoder.append(Data([0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2])), [.text(""), .acknowledgement(2)])
    }
}

final class ClipboardRoutingTests: XCTestCase {
    func testNewPhoneJoinsExistingSharedClipboardWithoutChangingOldDevice() {
        var router = ClipboardRouting()
        router.connect("existing")
        _ = router.copiedOnMac("before connection")
        router.connect("new phone")
        XCTAssertEqual(router.copiedOnMac("next copy").destinations, ["existing", "new phone"])
        router.disconnect("new phone")
        XCTAssertEqual(router.copiedOnMac("after disabling").destinations, ["existing"])
    }
    func testDelayedEchoDoesNotOverrideNewerCopyAndExpires() {
        var echoes = ClipboardEchoFilter()
        let start = Date(timeIntervalSince1970: 1000)
        echoes.sent("first", at: start)
        echoes.sent("second", at: start.addingTimeInterval(0.1))
        XCTAssertTrue(echoes.isEcho("first", at: start.addingTimeInterval(0.2)))
        XCTAssertTrue(echoes.isEcho("second", at: start.addingTimeInterval(0.3)))
        XCTAssertFalse(echoes.isEcho("first", at: start.addingTimeInterval(3)))
        echoes.sent("Mac", at: start.addingTimeInterval(4))
        XCTAssertFalse(echoes.isEcho("Phone", at: start.addingTimeInterval(4.1)))
        XCTAssertFalse(echoes.isEcho("Mac", at: start.addingTimeInterval(4.2)))
    }
    func testMacCopyBroadcastAndDeviceEchoSuppression() {
        var router = ClipboardRouting()
        router.connect("A"); router.connect("B")
        XCTAssertEqual(router.copiedOnMac("Mac 文本"), .init(updateMac: false, destinations: ["A", "B"]))
        XCTAssertEqual(router.copiedOnDevice("Mac 文本", id: "A"), .none)
        XCTAssertEqual(router.copiedOnDevice("Mac 文本", id: "B"), .none)
        XCTAssertEqual(router.copiedOnMac("Mac 文本"), .none)
    }

    func testPhoneCopyUpdatesMacAndOnlyOtherEnabledDevices() {
        var router = ClipboardRouting()
        router.connect("A"); router.connect("B"); router.connect("C")
        router.disconnect("C")
        XCTAssertEqual(router.copiedOnDevice("手机文字", id: "A"), .init(updateMac: true, destinations: ["B"]))
        XCTAssertEqual(router.copiedOnMac("手机文字"), .none)
        XCTAssertEqual(router.copiedOnDevice("手机文字", id: "B"), .none)
        XCTAssertEqual(router.copiedOnDevice("停用设备", id: "C"), .none)
    }

    func testReconnectWaitsForNextCopyAndAcceptsSameTextAgain() {
        var router = ClipboardRouting()
        router.connect("A")
        _ = router.copiedOnMac("text")
        router.disconnect("A")
        XCTAssertEqual(router.copiedOnMac("other"), .none)
        router.connect("A")
        XCTAssertEqual(router.copiedOnMac("text").destinations, ["A"])
    }

    func testCopyingAnImageThenSamePhoneTextStillUpdatesMac() {
        var router = ClipboardRouting()
        router.connect("A")
        _ = router.copiedOnDevice("same", id: "A")
        router.macContainsNonText()
        XCTAssertTrue(router.copiedOnDevice("same", id: "A").updateMac)
    }

    func testRapidAlternateCopiesDoNotCreateAnEchoLoop() {
        var router = ClipboardRouting()
        router.connect("A"); router.connect("B")
        for index in 0..<100 {
            let text = "\(index) 文本"
            if index.isMultiple(of: 2) {
                _ = router.copiedOnMac(text)
                XCTAssertEqual(router.copiedOnDevice(text, id: "A"), .none)
            } else {
                XCTAssertTrue(router.copiedOnDevice(text, id: "A").updateMac)
                XCTAssertEqual(router.copiedOnMac(text), .none)
            }
            XCTAssertEqual(router.copiedOnDevice(text, id: "B"), .none)
        }
    }
}

final class ClipboardPollingTests: XCTestCase {
    func testIdleBurstAndLowPowerCadence() {
        var policy = ClipboardPollingPolicy()
        XCTAssertEqual(policy.interval(at: 100, lowPower: false), 2)
        policy.recordActivity(at: 100)
        XCTAssertEqual(policy.interval(at: 100, lowPower: false), 0.5)
        XCTAssertEqual(policy.interval(at: 109, lowPower: false), 0.5)
        XCTAssertEqual(policy.interval(at: 110, lowPower: false), 2)
        XCTAssertEqual(policy.interval(at: 101, lowPower: true), 2)
        XCTAssertEqual(policy.tolerance(at: 101, lowPower: false), 0.05)
        XCTAssertEqual(policy.tolerance(at: 120, lowPower: false), 0.2)
    }

    @MainActor func testSleepPausesPollingWakeChecksImmediatelyAndStopRemovesObservers() async throws {
        let workspace = NotificationCenter()
        let process = NotificationCenter()
        var checks = 0
        let monitor = ClipboardMonitor(workspaceCenter: workspace, processCenter: process,
                                       lowPower: { false }, screenIsAsleep: { false }) {
            checks += 1
            return false
        }
        defer { monitor.stop() }
        monitor.start()
        XCTAssertEqual(checks, 1)
        monitor.start() // A second device must not create a second polling loop.
        XCTAssertEqual(checks, 1)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertGreaterThanOrEqual(checks, 2)
        workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(monitor.isPolling)
        let pausedCount = checks
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(checks, pausedCount)
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(monitor.isPolling)
        XCTAssertGreaterThan(checks, pausedCount)
        monitor.stop()
        let stoppedCount = checks
        workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(checks, stoppedCount)
    }

    @MainActor func testStartingWhileDisplayAsleepDoesNotPoll() async throws {
        let workspace = NotificationCenter()
        var checks = 0
        let monitor = ClipboardMonitor(workspaceCenter: workspace, processCenter: NotificationCenter(),
                                       lowPower: { false }, screenIsAsleep: { true }) {
            checks += 1
            return false
        }
        defer { monitor.stop() }
        monitor.start()
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertFalse(monitor.isPolling)
        XCTAssertEqual(checks, 0)
    }
}

final class ClipboardDevicePreferenceTests: XCTestCase {
    func testPerDeviceSettingsPersistIndependently() {
        let suite = "AmossClipboardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ClipboardDevicePreferences(defaults: defaults)
        XCTAssertTrue(preferences.isEnabled("new"))
        preferences.setEnabled(false, for: "A")
        preferences.setEnabled(true, for: "B")
        let reloaded = ClipboardDevicePreferences(defaults: defaults)
        XCTAssertFalse(reloaded.isEnabled("A"))
        XCTAssertTrue(reloaded.isEnabled("B"))
    }

    func testPreviousGlobalOffMigratesWithoutOverridingExplicitDeviceChoice() {
        let suite = "AmossClipboardMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "clipboard")
        let preferences = ClipboardDevicePreferences(defaults: defaults)
        XCTAssertFalse(preferences.isEnabled("new"))
        preferences.setEnabled(true, for: "new")
        XCTAssertTrue(preferences.isEnabled("new"))
        XCTAssertFalse(preferences.isEnabled("another"))
    }
}
