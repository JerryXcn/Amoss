import AppKit
import SwiftUI
#if canImport(AmossCore)
import AmossCore
#endif

struct AboutView: View {
    let onHelp: () -> Void
    let onClose: () -> Void
    @State private var page = Page.overview

    private enum Page: String, CaseIterable, Identifiable {
        case overview, acknowledgements
        var id: Self { self }
        var title: String {
            switch self { case .overview: L10n.text("简介"); case .acknowledgements: L10n.text("开源致谢") }
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? L10n.text("开发版本")
        guard let build = info["CFBundleVersion"] as? String else { return version }
        return L10n.text("版本 \(version)（\(build)）")
    }

    private var licensesURL: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Licenses", isDirectory: true),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 18) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().interpolation(.high)
                    .frame(width: 76, height: 76)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Amoss").font(.system(size: 29, weight: .bold))
                    Text(L10n.text("让 Android 成为 Mac 工作空间的一部分。"))
                        .font(.callout).foregroundStyle(.secondary)
                    Text(version).font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }

            Picker(L10n.text("关于 Amoss 的内容"), selection: $page) {
                ForEach(Page.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 240)

            ScrollView {
                Group {
                    switch page {
                    case .overview: overview
                    case .acknowledgements: acknowledgements
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                Button(L10n.text("使用帮助"), action: onHelp)
                    .help(L10n.text("查看连接步骤、操作方式和快捷键"))
                Spacer()
                Button(L10n.text("完成"), action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 616)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand(perform: onClose)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                (
                    initial("A") + Text("ndroid & ") + initial("M") + Text("ac, ")
                    + initial("O") + Text("ne ") + initial("S") + Text("hared ")
                    + initial("S") + Text("pace")
                )
                .font(.system(size: 18, weight: .medium))
                .textSelection(.enabled)
                .accessibilityLabel(L10n.text("Amoss 名字的含义：Android and Mac, One Shared Space。首字母 A、M、O、S、S。"))
                Text(L10n.text("Android 与 Mac，共享一个工作空间。"))
                    .font(.callout).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 15) {
                feature(L10n.text("设备镜像"), symbol: "display",
                        detail: L10n.text("用 Mac 键鼠操作手机，支持折叠屏与多显示屏。"))
                feature(L10n.text("独立应用窗口"), symbol: "macwindow",
                        detail: L10n.text("在 Mac 上打开支持的 Android 应用，手机可同时使用其他应用。"))
                feature(L10n.text("后台剪贴板"), symbol: "doc.on.clipboard",
                        detail: L10n.text("无需开启镜像即可双向同步文字，每台设备单独控制。"))
            }

            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Label(L10n.text("常驻菜单栏，随用随开"), systemImage: "menubar.rectangle")
                    .font(.callout.weight(.medium))
                Text(L10n.text("通过 USB 连接已授权的设备。ADB 与 scrcpy 已内置，无需另外安装环境。"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func initial(_ letter: String) -> Text {
        Text(letter).bold().foregroundColor(.accentColor)
    }

    private func feature(_ title: String, symbol: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18))
                .foregroundStyle(.secondary).frame(width: 26, height: 23)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var acknowledgements: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("Amoss 基于以下开源项目构建，感谢维护者与社区的贡献。"))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                component("ADB", version: "37.0.1", role: L10n.text("Android 设备连接与通信"), license: L10n.text("Apache 2.0 等"))
                component("scrcpy", version: "5.0.1", role: L10n.text("镜像、设备控制与剪贴板传输"), license: "Apache 2.0")
                component("FFmpeg", version: "9.0.2", role: L10n.text("视频解码"), license: "LGPL 2.1+")
                component("SDL", version: "3.4.18", role: L10n.text("镜像窗口渲染与输入"), license: "zlib")
                component("dav1d", version: "1.5.4", role: L10n.text("AV1 视频解码"), license: "BSD 2-Clause")
            }

            Divider()
            Text(L10n.text("Amoss 对 scrcpy 客户端进行了原生窗口与操作栏适配。完整许可随应用提供，对应源码与构建说明随安装包附带。"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(L10n.text("查看许可文件…"), systemImage: "folder") {
                if let licensesURL { NSWorkspace.shared.open(licensesURL) }
            }
            .disabled(licensesURL == nil)
            .help(L10n.text("在 Finder 中打开随应用附带的开源许可与致谢文件"))
        }
    }

    private func component(_ name: String, version: String, role: String, license: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.callout.weight(.semibold))
                Text(version).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Text(license).font(.caption).foregroundStyle(.secondary)
            }
            Text(role).font(.caption).foregroundStyle(.secondary)
        }
    }
}
