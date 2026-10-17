import XCTest
@testable import AmossCore

final class MirrorWindowLayoutTests: XCTestCase {
    private let inner = MirrorWindowMetrics(videoWidth: 1080, videoHeight: 2520, titlebarHeight: 28)

    func testPhoneRatioExcludesToolbarAndTitlebar() {
        let size = MirrorWindowLayout.fittedSize(metrics: inner, maximum: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(size.height, 872)
        XCTAssertEqual(size.width, floor(800 * 1080 / 2520))
        XCTAssertEqual(size.width / (size.height - 72), inner.aspect, accuracy: 0.002)
    }

    func testBothWindowsFitAndMirrorIsOnRightAtScreenEdge() {
        for visible in [CGRect(x: 0, y: 60, width: 1440, height: 900), CGRect(x: -1280, y: 25, width: 1280, height: 720)] {
            let list = CGRect(x: visible.maxX - 570, y: visible.minY + 100, width: 560, height: 360)
            let pair = MirrorWindowLayout.pair(list: list, visible: visible, metrics: inner)
            XCTAssertTrue(visible.contains(pair.list))
            XCTAssertTrue(visible.contains(pair.mirror))
            XCTAssertEqual(pair.mirror.minX - pair.list.maxX, 16)
            XCTAssertEqual(pair.list.maxY, pair.mirror.maxY)
            XCTAssertEqual(pair.mirror.width / (pair.mirror.height - 72), inner.aspect, accuracy: 0.002)
        }
    }

    func testCoverAndLandscapeFitSmallerDesktopWithoutStretching() {
        let screen = CGRect(x: 0, y: 40, width: 1024, height: 700)
        for video in [CGSize(width: 382, height: 720), CGSize(width: 2520, height: 1080)] {
            let metrics = MirrorWindowMetrics(videoWidth: video.width, videoHeight: video.height)
            let pair = MirrorWindowLayout.pair(list: CGRect(x: 300, y: 100, width: 460, height: 320), visible: screen, metrics: metrics)
            XCTAssertTrue(screen.contains(pair.mirror))
            XCTAssertFalse(pair.list.intersects(pair.mirror))
            XCTAssertEqual(pair.mirror.width / (pair.mirror.height - metrics.chromeHeight), metrics.aspect, accuracy: 0.02)
        }
    }

    func testMaximizedListMakesRoomForMirror() {
        let screen = CGRect(x: 0, y: 40, width: 1024, height: 700)
        let pair = MirrorWindowLayout.pair(list: screen, visible: screen, metrics: inner)
        XCTAssertTrue(screen.contains(pair.list))
        XCTAssertTrue(screen.contains(pair.mirror))
        XCTAssertEqual(pair.mirror.minX - pair.list.maxX, 16)
        XCTAssertGreaterThanOrEqual(pair.list.width, 460)
    }

    func testWidthAndHeightDragsKeepFixedToolbarHeight() {
        let current = CGSize(width: 343, height: 872)
        for proposed in [CGSize(width: 300, height: 872), CGSize(width: 343, height: 720)] {
            let size = MirrorWindowLayout.resized(proposed, current: current, metrics: inner, maximum: CGSize(width: 1440, height: 900))
            XCTAssertEqual(size.width / (size.height - inner.chromeHeight), inner.aspect, accuracy: 0.003)
            XCTAssertLessThanOrEqual(size.height, 900)
        }
    }

    func testWindowMessagesRejectIncompleteOrInvalidMetrics() {
        let prefix = "INFO: Amoss window ready: "
        XCTAssertNil(MirrorWindowMetrics.from(log: prefix + "{\"videoWidth\":1080"))
        XCTAssertNil(MirrorWindowMetrics.from(log: prefix + "{\"videoWidth\":0,\"videoHeight\":1920,\"titlebarHeight\":28}"))
        let payload = String(data: try! JSONEncoder().encode(inner), encoding: .utf8)!
        XCTAssertEqual(MirrorWindowMetrics.from(log: "INFO: some log\n" + prefix + payload + "\n"), inner)
        let presentation = MirrorWindowPresentation(frame: CGRect(x: -1000, y: 40, width: 340, height: 872))
        XCTAssertEqual(MirrorWindowPresentation.decode(presentation.json)?.frame, presentation.frame)
        XCTAssertNil(MirrorWindowPresentation.decode("garbage"))
    }
}
