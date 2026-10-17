import Foundation
import IOKit

public struct DiscoveryResult: Sendable {
    public let devices: [AndroidDevice]
}

public enum DiscoveryError: LocalizedError {
    case adb(String)
    public var errorDescription: String? {
        switch self { case .adb(let detail): L10n.text("无法读取设备列表。\n\(detail)") }
    }
}

public enum DeviceDiscovery {
    public static func scan(using tools: Toolchain) async throws -> DiscoveryResult {
        let result = try await CommandRunner.run(tools.adb, ["devices", "-l"], environment: tools.environment)
        guard result.exitCode == 0 else { throw DiscoveryError.adb(result.output) }
        var records = ADBDeviceParser.parse(result.output)
        // Some macOS ADB backends omit usb: in devices -l, especially before RSA
        // authorization. Confirm with the host devpath or the physical USB registry.
        let usbSerials = USBRegistry.serialNumbers()
        for index in records.indices where !records[index].isUSB {
            let device = records[index]
            if usbSerials.contains(device.serial),
               !device.serial.hasPrefix("emulator-"), !device.serial.contains(":") {
                records[index].usbPath = "physical"
            } else if let path = try? await CommandRunner.run(
                tools.adb, device.selector + ["get-devpath"], environment: tools.environment,
                timeout: .seconds(2)), path.exitCode == 0 {
                records[index].usbPath = ADBDeviceParser.usbPath(fromDevPath: path.output)
            }
        }
        return DiscoveryResult(devices: records.filter(\.isUSB).sorted {
            if $0.state == .ready && $1.state != .ready { return true }
            if $1.state == .ready && $0.state != .ready { return false }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        })
    }
}

enum USBRegistry {
    static func serialNumbers() -> Set<String> {
        var result = Set<String>()
        for serviceClass in ["IOUSBHostDevice", "IOUSBDevice"] {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(serviceClass), &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            var service = IOIteratorNext(iterator)
            while service != 0 {
                if let value = IORegistryEntryCreateCFProperty(service, "USB Serial Number" as CFString,
                                                              kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                    result.insert(value.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
        }
        return result
    }
}
