import Foundation

public struct MirrorWindowMetrics: Codable, Equatable, Sendable {
    public var videoWidth: Double
    public var videoHeight: Double
    public var titlebarHeight: Double

    public init(videoWidth: Double, videoHeight: Double, titlebarHeight: Double = 28) {
        self.videoWidth = videoWidth; self.videoHeight = videoHeight; self.titlebarHeight = titlebarHeight
    }
    public var isValid: Bool {
        videoWidth.isFinite && videoHeight.isFinite && titlebarHeight.isFinite &&
        videoWidth > 0 && videoHeight > 0 && titlebarHeight >= 0 && titlebarHeight < 200
    }
    public var aspect: Double { videoWidth / videoHeight }
    public var chromeHeight: Double { titlebarHeight + MirrorWindowLayout.toolbarHeight }

    public static func from(log: String) -> Self? {
        let prefix = "INFO: Amoss window ready: "
        for line in log.split(separator: "\n").reversed() where line.hasPrefix(prefix) {
            let value = try? JSONDecoder().decode(Self.self, from: Data(line.dropFirst(prefix.count).utf8))
            if let value, value.isValid { return value }
        }
        return nil
    }
}

public struct MirrorWindowPresentation: Codable, Sendable {
    public static let notification = "com.amoss.mirror.present"
    public var frame: CGRect
    public init(frame: CGRect) { self.frame = frame }
    public var json: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }
    public static func decode(_ json: String?) -> Self? {
        guard let json, let value = try? JSONDecoder().decode(Self.self, from: Data(json.utf8)),
              [value.frame.minX, value.frame.minY, value.frame.width, value.frame.height].allSatisfy(\.isFinite),
              value.frame.width > 0, value.frame.height > 0 else { return nil }
        return value
    }
}

public enum MirrorWindowLayout {
    public static let toolbarHeight: Double = 44
    public static let gap: Double = 16

    /// The phone image alone has a fixed aspect ratio; titlebar and controls do not scale.
    public static func fittedSize(metrics: MirrorWindowMetrics, maximum: CGSize, preferredVideoHeight: Double = 800) -> CGSize {
        guard metrics.isValid else { return .zero }
        let height = floor(max(1, min(preferredVideoHeight, maximum.height - metrics.chromeHeight, maximum.width / metrics.aspect)))
        return CGSize(width: floor(height * metrics.videoWidth / metrics.videoHeight), height: height + metrics.chromeHeight)
    }

    public static func pair(list: CGRect, visible: CGRect, metrics: MirrorWindowMetrics) -> (list: CGRect, mirror: CGRect) {
        let safe = visible.insetBy(dx: 16, dy: 16)
        let listWidth = min(list.width, max(460, safe.width - gap - 160))
        let listHeight = min(list.height, safe.height)
        let available = CGSize(width: max(1, safe.width - listWidth - gap), height: safe.height)
        let mirrorSize = fittedSize(metrics: metrics, maximum: available)
        let totalWidth = listWidth + gap + mirrorSize.width
        let x = max(safe.minX, min(list.minX, safe.maxX - totalWidth))
        let top = min(safe.maxY, max(list.maxY, safe.minY + max(listHeight, mirrorSize.height)))
        return (
            CGRect(x: x, y: top - listHeight, width: listWidth, height: listHeight),
            CGRect(x: x + listWidth + gap, y: top - mirrorSize.height, width: mirrorSize.width, height: mirrorSize.height)
        )
    }

    public static func resized(_ proposed: CGSize, current: CGSize, metrics: MirrorWindowMetrics, maximum: CGSize) -> CGSize {
        let widthChange = abs(proposed.width - current.width)
        let heightChange = abs(proposed.height - current.height) * metrics.aspect
        let videoHeight = widthChange >= heightChange ? proposed.width / metrics.aspect : proposed.height - metrics.chromeHeight
        return fittedSize(metrics: metrics, maximum: maximum, preferredVideoHeight: max(160, 160 / metrics.aspect, videoHeight))
    }
}
