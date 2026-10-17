import XCTest
@testable import AmossCore

final class ApplicationTests: XCTestCase {
    func testEnumerationKeepsNamesAndWrappedLabelsAndIgnoresNoise() {
        let apps = ApplicationDiscovery.parse("""
        * daemon started successfully *
        [server] INFO: List of apps:
         * 设置                             com.android.settings
         - My Notes                       com.example.notes
         - A very long application name that wraps to the next line
                                         com.example.longname
         - Duplicate                      com.example.notes
         - Invalid                        +com.example.stop
        [server] ERROR: ignore this line
        """)
        XCTAssertEqual(apps.count, 3)
        XCTAssertEqual(apps.first { $0.id == "com.android.settings" }?.name, "设置")
        XCTAssertEqual(apps.first { $0.id == "com.android.settings" }?.isSystem, true)
        XCTAssertEqual(apps.first { $0.id == "com.example.longname" }?.name,
                       "A very long application name that wraps to the next line")
        XCTAssertTrue(ApplicationDiscovery.parse("- Ignore com.example.noheader").isEmpty)
    }

    func testSearchAndPackageValidation() {
        let app = AndroidApplication(packageName: "com.example.Calculator", name: "计算器")
        XCTAssertTrue(app.matches("计算"))
        XCTAssertTrue(app.matches(" calculator "))
        XCTAssertFalse(app.matches("设置"))
        for package in ["+com.example.app", "?Calculator", "com.example;reboot", "com.foo\nbar", "com.example.app --display-id=0"] {
            XCTAssertFalse(AndroidApplication(packageName: package, name: "Name").isValid)
        }
    }

    func testAppWindowNeverUsesPhysicalScreenPowerAudioOrForceStop() {
        let options = MirrorOptions(audio: true, stayAwake: true, startWithScreenOff: true)
        let args = options.arguments(for: .init(serial: "one", state: .ready),
                                     application: .init(packageName: "com.example.app", name: "An App"))
        for arg in ["--new-display", "--start-app=com.example.app", "--no-power-on", "--no-audio", "--display-ime-policy=local", "--no-clipboard-autosync", "--no-mouse-hover"] {
            XCTAssertTrue(args.contains(arg), arg)
        }
        for arg in ["--display-id=0", "--turn-screen-off", "--stay-awake", "--start-app=+com.example.app", "--no-vd-destroy-content"] {
            XCTAssertFalse(args.contains(arg), arg)
        }
    }
}
