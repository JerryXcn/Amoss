// On-device integration harness. Uses a private Mac pasteboard, never the user's
// general pasteboard. Its JSON responses contain checks, not clipboard text.
import AppKit
import Foundation

@main
struct ClipboardSmoke {
    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let serial = CommandLine.arguments[2]
        let tools = Toolchain(directory: directory)
        let device = AndroidDevice(serial: serial, state: .ready, model: "Clipboard Test", usbPath: "test")
        let suite = "AmossClipboardSmoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let pasteboard = NSPasteboard(name: .init(suite))
        let store = ClipboardSyncStore(defaults: defaults, pasteboard: pasteboard)
        defer { defaults.removePersistentDomain(forName: suite); pasteboard.releaseGlobally() }
        store.reconcile([device], tools: tools)
        while let line = await Task.detached(operation: { readLine() }).value {
            guard let data = line.data(using: .utf8), let command = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let action = command["action"] as? String ?? ""
            switch action {
            case "copy":
                pasteboard.clearContents()
                pasteboard.setString(command["text"] as? String ?? "", forType: .string)
            case "enabled": store.setEnabled(command["value"] as? Bool ?? false, for: device.id)
            case "disconnect": store.reconcile([], tools: tools)
            case "connect": store.reconcile([device], tools: tools)
            case "shutdown": store.shutdown()
            default: break
            }
            var reply: [String: Any] = ["status": store.status(device.id).title,
                "ready": store.status(device.id) == .ready, "enabled": store.isEnabled(device.id),
                "pending": store.hasPendingShutdown, "changes": pasteboard.changeCount]
            if action == "expect" { reply["matches"] = pasteboard.string(forType: .string) == command["text"] as? String }
            let response = try JSONSerialization.data(withJSONObject: reply, options: .sortedKeys)
            FileHandle.standardOutput.write(response + Data([10]))
            if action == "exit" { store.shutdown(); break }
        }
    }
}
