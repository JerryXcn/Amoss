import Foundation

public struct Toolchain: Sendable {
    public let adb: URL
    public let scrcpy: URL
    public let server: URL
    public let resources: URL

    public init(directory: URL, mirrorExecutable: URL? = nil) {
        resources = directory
        adb = directory.appendingPathComponent("adb")
        scrcpy = mirrorExecutable ?? directory.appendingPathComponent("scrcpy")
        server = directory.appendingPathComponent("scrcpy-server")
    }

    public static func bundled(in bundle: Bundle = .main) throws -> Self {
        guard let resources = bundle.resourceURL else { throw ToolchainError.incomplete }
        let helper = bundle.bundleURL.appendingPathComponent("Contents/Helpers/Amoss Mirror.app/Contents/MacOS/scrcpy")
        let tools = Self(directory: resources.appendingPathComponent("Tools"), mirrorExecutable: helper)
        try tools.validate()
        return tools
    }

    public func validate() throws {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: adb.path),
              fm.isExecutableFile(atPath: scrcpy.path),
              fm.fileExists(atPath: server.path) else { throw ToolchainError.incomplete }
    }

    public var environment: [String: String] {
        // Finder has a different PATH from Terminal. Every executable and server
        // file is resolved within the app, even on Macs with no developer tools.
        var values = ProcessInfo.processInfo.environment
        for key in ["ANDROID_SERIAL", "ANDROID_ADB_SERVER_PORT", "ADB_SERVER_SOCKET",
                    "ADB_SERVER_PORT", "ANDROID_ADB_SERVER_ADDRESS", "ADB_VENDOR_KEYS",
                    "ADB_TRACE", "SCRCPY_SERVER_PATH", "SCRCPY_ICON_DIR",
                    "DYLD_LIBRARY_PATH", "DYLD_INSERT_LIBRARIES", "AMOSS_WAKE_MIRROR",
                    "AMOSS_SESSION_TOKEN", "AMOSS_WINDOW_PRESENTATION", "AMOSS_APP_WINDOW"] {
            values.removeValue(forKey: key)
        }
        values["PATH"] = "\(resources.path):/usr/bin:/bin:/usr/sbin:/sbin"
        values["ADB"] = adb.path
        values["SCRCPY_SERVER_PATH"] = server.path
        values["SCRCPY_ICON_DIR"] = resources.path
        return values
    }
}

public enum ToolchainError: LocalizedError {
    case incomplete
    public var errorDescription: String? {
        L10n.text("Amoss 的运行文件不完整。请重新安装完整的 Amoss 应用。")
    }
}
