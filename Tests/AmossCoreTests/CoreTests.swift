import XCTest
import AppKit
@testable import AmossCore

final class DeviceParserTests: XCTestCase {
    func testMixedTransportsAndAuthorization() {
        let records = ADBDeviceParser.parse("""
        * daemon started successfully *
        List of devices attached
        USB1 device usb:0-1 product:p model:Pixel_9_Pro device:p transport_id:1
        USB2 unauthorized usb:0-2 transport_id:2
        USB3 offline usb:0-3 transport_id:3
        192.168.0.2:5555 device product:p model:Wireless transport_id:4
        adb-serial-random._adb-tls-connect._tcp device model:Wireless transport_id:5
        emulator-5554 device model:Emulator transport_id:6
        USB1 device usb:0-1 model:Duplicate transport_id:1
        """)
        XCTAssertEqual(records.count, 6)
        XCTAssertEqual(records.filter(\.isUSB).count, 3)
        XCTAssertEqual(records[0].name, "Pixel 9 Pro")
        XCTAssertEqual(records[1].name, L10n.text("Android 设备"))
        XCTAssertEqual(records[1].state, .unauthorized)
        XCTAssertEqual(records[2].state, .offline)
        XCTAssertEqual(records[0].selector, ["-t", "1"])
    }

    func testNoTransportGuessingAndDevPathConfirmation() {
        let device = ADBDeviceParser.parse("serial device model:Phone transport_id:10").first!
        XCTAssertFalse(device.isUSB)
        XCTAssertEqual(ADBDeviceParser.usbPath(fromDevPath: "usb:0-1\n"), "0-1")
        XCTAssertNil(ADBDeviceParser.usbPath(fromDevPath: "unknown"))
        XCTAssertNil(ADBDeviceParser.usbPath(fromDevPath: "error: device unauthorized"))
        XCTAssertTrue(ADBDeviceParser.parse("List of devices attached\n").isEmpty)
    }

    func testSpecialDeviceStates() {
        let values = ADBDeviceParser.parse("a recovery usb:1\nb sideload usb:2\nc no permissions usb:3\n")
        XCTAssertEqual(values.map(\.state), [.recovery, .sideload, .noPermissions])
    }
}

final class MirrorOptionsTests: XCTestCase {
    func testMirrorsKeepManualClipboardAndDelegateAutosyncToBackgroundService() {
        let device = AndroidDevice(serial: "serial with ' quotes;$()", state: .ready, model: "My_Phone")
        let args = MirrorOptions().arguments(for: device)
        XCTAssertTrue(args.contains("--serial=serial with ' quotes;$()"))
        XCTAssertTrue(args.contains("--window-title=" + L10n.text("\("My Phone") · 屏幕 \(0) — Amoss")))
        XCTAssertTrue(args.contains("--display-id=0"))
        XCTAssertTrue(args.contains("--shortcut-mod=lsuper,rsuper"))
        XCTAssertTrue(args.contains("--keyboard=sdk"))
        XCTAssertTrue(args.contains("--mouse=sdk"))
        XCTAssertFalse(args.contains("--no-control"))
        XCTAssertTrue(args.contains("--no-clipboard-autosync"))
        let app = AndroidApplication(packageName: "com.example.calculator", name: "Calculator")
        XCTAssertTrue(MirrorOptions().arguments(for: device, application: app).contains("--no-clipboard-autosync"))
        XCTAssertFalse(args.contains("--kill-adb-on-close"))
        XCTAssertFalse(args.contains("--require-audio"))
    }

    func testOptionsAreMappedIndependently() {
        let args = MirrorOptions(quality: .smooth, audio: false, stayAwake: true)
            .arguments(for: .init(serial: "1", state: .ready))
        for option in ["--max-size=1280", "--max-fps=30", "--no-audio", "--stay-awake", "--no-clipboard-autosync"] {
            XCTAssertTrue(args.contains(option), option)
        }
        XCTAssertTrue(MirrorQuality.sharp.arguments.contains("--max-size=0"))
    }

    func testScreenOffStartupDoesNotAutomaticallyPowerOnPhone() {
        let device = AndroidDevice(serial: "sleeping", state: .ready)
        let args = MirrorOptions(startWithScreenOff: true).arguments(for: device, displayID: 7)
        XCTAssertTrue(args.contains("--no-power-on"))
        XCTAssertTrue(args.contains("--turn-screen-off"))
        XCTAssertTrue(args.contains("--stay-awake"))
        XCTAssertTrue(args.contains("--display-id=7"))
        XCTAssertFalse(MirrorOptions().arguments(for: device).contains("--turn-screen-off"))
    }

    func testLatestPanelChoiceSurvivesFoldRestart() {
        XCTAssertNil(ScrcpyLog.requestedDisplayOff("INFO: unrelated output\n"))
        XCTAssertEqual(ScrcpyLog.requestedDisplayOff("INFO: Amoss display power: off\n"), true)
        XCTAssertEqual(ScrcpyLog.requestedDisplayOff("INFO: Amoss display power: off\nINFO: Amoss display power: on\n"), false)
        XCTAssertEqual(ScrcpyLog.requestedDisplayOff("INFO: Amoss display power: on\nINFO: Amoss display power: off\n"), true)
    }

    func testBundledPathsWithSpacesAndNoHomebrew() {
        let tools = Toolchain(directory: URL(fileURLWithPath: "/Applications/My Amoss.app/Contents/Resources/Tools"))
        XCTAssertEqual(tools.environment["ADB"], tools.adb.path)
        XCTAssertEqual(tools.environment["SCRCPY_SERVER_PATH"], tools.server.path)
        XCTAssertFalse(tools.environment["PATH"]!.contains("homebrew"))
        XCTAssertFalse(tools.environment["PATH"]!.contains("/usr/local/bin"))
    }
}

final class DisplayTests: XCTestCase {
    func testScrcpyEnumerationUsesReportedIDs() {
        let displays = DisplayParser.scrcpyList("[server] INFO: List of displays:\n --display-id=0 (1080x2520)\n --display-id=7 (382x720)\n")
        XCTAssertEqual(displays.map(\.id), [0, 7])
        XCTAssertEqual(displays[1].resolution, "382 × 720")
        let args = MirrorOptions().arguments(for: .init(serial: "one", state: .ready), displayID: 7)
        XCTAssertTrue(args.contains("--display-id=7"))
    }

    func testPhysicalStateOverridesStaleLogicalON() {
        let raw = """
        DisplayDeviceInfo{"内置屏幕": uniqueId="local:inner", 1080 x 2520, type INTERNAL, state OFF, committedState OFF}
        DisplayDeviceInfo{"内置屏幕": uniqueId="local:outer", 382 x 720, type INTERNAL, state ON, committedState ON}
        mBaseDisplayInfo=DisplayInfo{"内置屏幕", displayId 0, real 1080 x 2520, state OFF, type INTERNAL, uniqueId "local:inner"}
        mOverrideDisplayInfo=DisplayInfo{"内置屏幕", displayId 0, real 1080 x 2520, state ON, type INTERNAL, uniqueId "local:inner"}
        mBaseDisplayInfo=DisplayInfo{"内置屏幕", displayId 7, real 382 x 720, state OFF, type INTERNAL, uniqueId "local:outer"}
        mDeviceState=DeviceState{identifier=0, name='CLOSED', app_accessible=true}
        """
        let displays = DisplayParser.scrcpyList("--display-id=0 (1080x2520)\n--display-id=7 (382x720)")
        let snapshot = DisplayParser.enrich(displays, dumpsys: raw)
        XCTAssertEqual(snapshot.automaticDisplay()?.id, 7)
        XCTAssertEqual(snapshot.posture, "CLOSED")
        XCTAssertEqual(snapshot.displays[0].state, "OFF")
    }

    func testSleepingFoldableWithoutLayoutAllowsFixedChoiceAndKeepsExistingSession() {
        let snapshot = DisplaySnapshot(displays: [
            .init(id: 0, width: 1080, height: 2520, kind: "INTERNAL", state: "OFF"),
            .init(id: 1, width: 382, height: 720, kind: "INTERNAL", state: "OFF")
        ])
        XCTAssertNil(snapshot.automaticDisplay())
        XCTAssertEqual(snapshot.automaticDisplay(keeping: 1)?.id, 1)
        XCTAssertEqual(DisplaySelection.fixed(1).resolve(in: snapshot)?.id, 1)
        XCTAssertNil(DisplaySelection.fixed(99).resolve(in: snapshot))
        XCTAssertEqual(DisplaySelection(stored: "auto"), .automatic)
        XCTAssertEqual(DisplaySelection(stored: "7"), .fixed(7))
    }

    func testSleepingFoldableUsesCurrentLayoutAndFollowsPosture() {
        let raw = """
        mCurrentLayout=[{dispId: 7(ON), addr: {port=3}}, {dispId: 0(OFF), addr: {port=0}}]
        otherLayout=[{dispId: 0(ON)}, {dispId: 7(OFF)}]
        mBaseDisplayInfo=DisplayInfo{"内置屏幕", displayId 0, state OFF, type INTERNAL, uniqueId "local:inner"}
        mBaseDisplayInfo=DisplayInfo{"内置屏幕", displayId 7, state OFF, type INTERNAL, uniqueId "local:outer"}
        mDeviceState=DeviceState{identifier=0, name='CLOSED', app_accessible=true}
        """
        let displays = DisplayParser.scrcpyList("--display-id=0 (1080x2520)\n--display-id=7 (382x720)")
        let folded = DisplayParser.enrich(displays, dumpsys: raw)
        XCTAssertEqual(folded.activeLayoutIDs, [7])
        XCTAssertEqual(DisplaySelection.automatic.resolve(in: folded)?.id, 7)
        XCTAssertEqual(folded.automaticDisplay(keeping: 0)?.id, 7)
        var unfolded = folded
        unfolded.activeLayoutIDs = [0]
        XCTAssertEqual(unfolded.automaticDisplay(keeping: 7)?.id, 0)
        XCTAssertEqual(DisplaySelection.fixed(7).resolve(in: unfolded)?.id, 7)
    }

    func testLayoutCannotChooseMissingDisabledOrVirtualDisplay() {
        let displays: [AndroidDisplay] = [
            .init(id: 0, width: 1080, height: 2520, kind: "INTERNAL", state: "OFF"),
            .init(id: 7, width: 382, height: 720, kind: "INTERNAL", state: "OFF"),
            .init(id: 8, width: 382, height: 720, kind: "INTERNAL", state: "OFF", enabled: false),
            .init(id: 9, width: 1080, height: 1920, kind: "VIRTUAL", state: "ON")
        ]
        let snapshot = DisplaySnapshot(displays: displays, activeLayoutIDs: [8, 9, 99])
        XCTAssertNil(snapshot.automaticDisplay())
        XCTAssertNil(snapshot.automaticDisplay(keeping: 0))
    }

    func testAutoDoesNotJumpToVirtualScreenOrBetweenTwoOnScreens() {
        let snapshot = DisplaySnapshot(displays: [
            .init(id: 0, width: 1080, height: 2520, kind: "INTERNAL", state: "ON"),
            .init(id: 1, width: 382, height: 720, kind: "INTERNAL", state: "ON"),
            .init(id: 2, width: 1920, height: 1080, kind: "VIRTUAL", state: "ON")
        ])
        XCTAssertEqual(snapshot.automaticDisplay(keeping: 1)?.id, 1)
        XCTAssertEqual(snapshot.automaticDisplay()?.id, 0)
    }

    func testCaptureHelperIsNotOfferedAsAnotherScreen() {
        let raw = """
        mBaseDisplayInfo=DisplayInfo{"内置屏幕", displayId 1, state ON, type INTERNAL, uniqueId "local:cover"}
        mBaseDisplayInfo=DisplayInfo{"scrcpy", displayId 12, state ON, type VIRTUAL, uniqueId "virtual:com.android.shell,2000,scrcpy,7"}
        mBaseDisplayInfo=DisplayInfo{"Presentation", displayId 13, state ON, type VIRTUAL, uniqueId "virtual:presentation"}
        """
        let displays = DisplayParser.scrcpyList("--display-id=1 (382x720)\n--display-id=12 (382x720)\n--display-id=13 (1920x1080)")
        let snapshot = DisplayParser.enrich(displays, dumpsys: raw)
        XCTAssertEqual(snapshot.displays.map(\.id), [1, 13])
        XCTAssertEqual(snapshot.automaticDisplay()?.id, 1)
        // A cached helper also stays excluded after its Android display is gone.
        let oldHelper = AndroidDisplay(id: 12, width: 382, height: 720, name: "scrcpy", kind: "VIRTUAL", state: "ON")
        XCTAssertTrue(DisplayParser.enrich([oldHelper], dumpsys: "").displays.isEmpty)
    }
}

final class ProcessTests: XCTestCase {
    func testDrainsLargeOutputAndReturnsExitStatus() async throws {
        let result = try await CommandRunner.run(URL(fileURLWithPath: "/bin/sh"),
            ["-c", "i=0; while [ $i -lt 12000 ]; do echo line-from-child; i=$((i+1)); done; echo last-line >&2; exit 7"])
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertTrue(result.output.contains("last-line"))
    }

    @MainActor
    func testFastCommandsFinishDuringMenuTracking() {
        let result = TrackingResult()
        Task.detached {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for _ in 0..<30 {
                        group.addTask {
                            let value = try await CommandRunner.run(URL(fileURLWithPath: "/bin/sh"),
                                ["-c", "printf complete; exit 7"], timeout: .seconds(2))
                            guard value.exitCode == 7, value.output == "complete" else { throw CommandError.noResult }
                        }
                    }
                    try await group.waitForAll()
                }
                result.finish(error: nil)
            } catch { result.finish(error: error.localizedDescription) }
        }
        // Keep the normal run-loop mode unavailable, as a native menu does.
        let timer = Timer(timeInterval: 0.01, repeats: true) { _ in }
        RunLoop.main.add(timer, forMode: .eventTracking)
        let deadline = Date().addingTimeInterval(4)
        while !result.done && Date() < deadline {
            RunLoop.main.run(mode: .eventTracking, before: Date().addingTimeInterval(0.05))
        }
        timer.invalidate()
        XCTAssertTrue(result.done, "Commands must complete while the menu remains open")
        XCTAssertNil(result.error)
    }

    func testTimeoutStopsHungChild() async throws {
        do {
            _ = try await CommandRunner.run(URL(fileURLWithPath: "/bin/sleep"), ["30"], timeout: .milliseconds(80))
            XCTFail("Expected timeout")
        } catch CommandError.timeout { }
    }

    func testCancellationStopsCommand() async throws {
        let task = Task { try await CommandRunner.run(URL(fileURLWithPath: "/bin/sleep"), ["30"]) }
        try await Task.sleep(for: .milliseconds(80))
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
    }
}

private final class TrackingResult: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var failure: String?
    var done: Bool { lock.withLock { completed } }
    var error: String? { lock.withLock { failure } }
    func finish(error: String?) { lock.withLock { completed = true; failure = error } }
}

@MainActor
final class SessionTests: XCTestCase {
    private func fakeTools(script: String) throws -> (Toolchain, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AmossTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("scrcpy")
        try ("#!/bin/sh\n" + script).write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (Toolchain(directory: directory), directory)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("State did not arrive within 3 seconds")
    }

    func testDuplicateLaunchAndIndependentSessions() async throws {
        let (tools, dir) = try fakeTools(script: "echo 'INFO: Texture: 1080x1920'\nexec /bin/sleep 30\n")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MirrorSessionStore()
        let first = AndroidDevice(serial: "one", state: .ready)
        let second = AndroidDevice(serial: "two", state: .ready)
        let pid = store.start(first, tools: tools, options: .init())
        XCTAssertEqual(pid, store.start(first, tools: tools, options: .init()))
        store.start(second, tools: tools, options: .init())
        try await waitUntil { store.sessions.values.allSatisfy { $0.phase == .running } }
        XCTAssertEqual(store.sessions.count, 2)
        store.stop(first.id)
        try await waitUntil { store.sessions[first.id] == nil }
        XCTAssertEqual(store.sessions[second.id]?.phase, .running)
        XCTAssertNil(store.failure)
        store.shutdown()
        try await waitUntil { store.sessions.isEmpty }
    }

    func testApplicationsAndMirrorOnOneDeviceHaveIndependentLifecycles() async throws {
        let (tools, dir) = try fakeTools(script: """
        echo "mode=$AMOSS_APP_WINDOW wake=$AMOSS_WAKE_MIRROR"
        echo 'INFO: Texture: 1080x1920'
        exec /bin/sleep 30
        """)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MirrorSessionStore()
        let device = AndroidDevice(serial: "one", state: .ready)
        let first = AndroidApplication(packageName: "com.example.first", name: "First")
        let second = AndroidApplication(packageName: "com.example.second", name: "Second")
        store.start(device, tools: tools, options: .init())
        let firstPID = store.start(device, tools: tools, options: .init(startWithScreenOff: true), application: first)
        XCTAssertEqual(firstPID, store.start(device, tools: tools, options: .init(), application: first))
        store.start(device, tools: tools, options: .init(), application: second)
        try await waitUntil { store.sessions.count == 3 && store.sessions.values.allSatisfy { $0.phase == .running } }
        store.reconcile([device])
        XCTAssertEqual(store.sessions.count, 3)
        XCTAssertTrue(store.session(for: first, device: device)!.log.contains("mode=1 wake=0"))
        XCTAssertFalse(store.session(for: first, device: device)!.followsActiveDisplay)
        store.stop(MirrorSessionStore.sessionID(device: device, application: first))
        try await waitUntil { store.session(for: first, device: device) == nil }
        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertEqual(store.sessions[device.id]?.phase, .running)
        store.reconcile([])
        try await waitUntil { store.sessions.isEmpty }
        XCTAssertNil(store.failure)
    }

    func testApplicationFailureKeepsRetryTarget() async throws {
        let (tools, dir) = try fakeTools(script: "echo 'ERROR: Could not start app'\nexit 1\n")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MirrorSessionStore()
        let device = AndroidDevice(serial: "one", state: .ready)
        let app = AndroidApplication(packageName: "com.example.app", name: "Test")
        store.start(device, tools: tools, options: .init(), application: app)
        try await waitUntil { store.failure != nil }
        XCTAssertEqual(store.failure?.application, app)
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertNil(store.start(device, tools: tools, options: .init(),
                                 application: .init(packageName: "+com.example.app", name: "Invalid")))
    }

    func testWakeIntentIsExplicitAndToolbarChoiceUpdatesOnlyItsSession() async throws {
        let (tools, dir) = try fakeTools(script: """
        if [ "$AMOSS_WAKE_MIRROR" = "1" ]; then
          echo 'INFO: Amoss display power: on'
        else
          echo 'INFO: Amoss display power: off'
        fi
        echo 'INFO: Texture: 382x720'
        exec /bin/sleep 30
        """)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MirrorSessionStore()
        store.start(.init(serial: "sleeping", state: .ready), tools: tools,
                    options: .init(startWithScreenOff: true))
        store.start(.init(serial: "awake", state: .ready), tools: tools, options: .init())
        try await waitUntil { store.sessions.count == 2 && store.sessions.values.allSatisfy { $0.phase == .running } }
        XCTAssertEqual(store.sessions["sleeping"]?.options.startWithScreenOff, false)
        XCTAssertEqual(store.sessions["awake"]?.options.startWithScreenOff, true)
        store.shutdown()
        try await waitUntil { store.sessions.isEmpty }
    }

    func testWindowReadinessDoesNotRepeatedlyStealFocusOnLaterLogs() async throws {
        let (tools, dir) = try fakeTools(script: """
        echo 'INFO: Amoss window ready: {"videoWidth":816,"videoHeight":1920,"titlebarHeight":28}'
        sleep 0.1
        echo 'INFO: Amoss window ready: {"videoWidth":816,"videoHeight":1920,"titlebarHeight":28}'
        echo 'INFO: later log'
        exec /bin/sleep 30
        """)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MirrorSessionStore()
        var readyCount = 0
        store.onWindowReady = { session in
            readyCount += 1
            XCTAssertEqual(session.phase, .running)
            XCTAssertEqual(session.windowMetrics?.videoWidth, 816)
        }
        store.start(.init(serial: "one", state: .ready), tools: tools, options: .init())
        try await waitUntil { store.sessions["one"]?.log.contains("later log") == true }
        XCTAssertEqual(readyCount, 1)
        store.shutdown()
        try await waitUntil { store.sessions.isEmpty }
    }

    func testFailureIsReportedAndCanRetry() async throws {
        let (tools, dir) = try fakeTools(script: "echo 'ERROR: Device unauthorized'\nexit 1\n")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MirrorSessionStore()
        let device = AndroidDevice(serial: "one", state: .ready)
        store.start(device, tools: tools, options: .init())
        try await waitUntil { store.failure != nil }
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertTrue(store.failure!.message.contains(L10n.settings.resolved == .chinese ? "允许 USB 调试" : "allow USB debugging"))
        store.failure = nil
        store.start(device, tools: tools, options: .init())
        try await waitUntil { store.failure != nil }
    }

    func testDisconnectAndUnauthorizedDoNotLaunch() async throws {
        let (tools, dir) = try fakeTools(script: "echo 'INFO: Texture: 1080x1920'\nexec /bin/sleep 30\n")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MirrorSessionStore()
        XCTAssertNil(store.start(.init(serial: "locked", state: .unauthorized), tools: tools, options: .init()))
        store.start(.init(serial: "one", state: .ready), tools: tools, options: .init())
        store.reconcile([])
        try await waitUntil { store.sessions.isEmpty }
        XCTAssertNil(store.failure)
        XCTAssertNotNil(store.notice)
    }
}
