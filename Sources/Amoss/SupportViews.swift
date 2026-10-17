import SwiftUI
#if canImport(AmossCore)
import AmossCore
#endif

struct HelpView: View {
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 18) {
          ScrollView {
           VStack(alignment: .leading, spacing: 20) {
            Label(L10n.text("连接与操作"), systemImage: "cable.connector").font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("1. 在手机的开发者选项中开启 USB 调试。"))
                Text(L10n.text("2. 使用支持数据传输的 USB 线连接 Mac。"))
                Text(L10n.text("3. 解锁手机，允许这台电脑进行 USB 调试。"))
            }.font(.callout)
            Text(L10n.text("Amoss 默认驻留菜单栏。点击菜单栏图标即可打开设备镜像或独立应用；只有选择「主界面」才打开完整设备列表。关闭主界面会回到菜单栏，退出 Amoss 才结束全部窗口。"))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                shortcut(L10n.text("点击、拖动、滚动"), L10n.text("操作手机"))
                shortcut(L10n.text("右键 / ⌘B"), L10n.text("返回"))
                shortcut("⌘H", L10n.text("主屏幕"))
                shortcut("⌘S", L10n.text("最近使用的应用"))
                shortcut("⌘C / ⌘V", L10n.text("复制 / 粘贴文字"))
                shortcut("⌘F", L10n.text("全屏镜像"))
            }.font(.callout)
            Text(L10n.text("镜像底部图标依次为返回、主页、多任务、熄屏，悬停可查看提示。熄屏只关闭手机实体屏幕，Mac 上继续镜像；再次点击亮屏图标恢复。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(L10n.text("手机已熄屏时可直接开启镜像，Amoss 会唤醒系统并保持实体屏幕关闭。部分机型唤醒时可能短暂亮屏；手机已锁定时，需要正常完成解锁。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(L10n.text("每台设备都有「剪贴板同步」开关，开启后无需镜像即可双向同步文字。多台开启的设备共享剪贴板。连接或开启开关后，从下一次复制开始同步；关闭后仍可在镜像中使用 ⌘C / ⌘V 手动复制粘贴。暂不支持图片和文件。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(L10n.text("折叠屏与多屏设备：从菜单栏开启镜像默认自动选屏；主界面首次镜像可选择屏幕，也可以从设备菜单切换。选择「自动选择屏幕」后，跟随亮屏或当前折叠布局切换；手机熄屏时也可开启镜像。手动选择则固定镜像该屏幕。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(L10n.text("设备页面的应用列表支持搜索和独立窗口。同一应用再次点击会显示已有窗口；关闭窗口只结束该窗口。应用窗口暂不转发声音，也不控制手机实体屏电源。同一应用可能从手机移入窗口，具体取决于手机系统和应用。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
           }.frame(maxWidth: .infinity, alignment: .leading)
          }
            Divider()
            HStack { Spacer(); Button(L10n.text("完成")) { if let onClose { onClose() } else { dismiss() } }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 560, height: 720)
    }
    private func shortcut(_ key: String, _ text: String) -> some View {
        GridRow { Text(key).foregroundStyle(.secondary); Text(text) }
    }
}

struct AuthorizationView: View {
    let device: AndroidDevice
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(.secondary)
            Text(L10n.text("请在手机上允许连接")).font(.title2.weight(.semibold))
            Text(L10n.text("解锁手机，在「允许 USB 调试？」提示中点按「允许」。授权后，设备列表会自动更新。"))
                .fixedSize(horizontal: false, vertical: true)
            Text(device.serial).font(.caption.monospaced()).foregroundStyle(.secondary)
            Text(L10n.text("没有看到提示？请重新插拔数据线，并检查 USB 调试是否已开启。"))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button(L10n.text("知道了")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 380)
    }
}

struct DeviceDetailsView: View {
    let device: AndroidDevice
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(device.name, systemImage: "smartphone").font(.title2.weight(.semibold))
            LabeledContent(L10n.text("连接"), value: "USB")
            LabeledContent(L10n.text("状态"), value: model.devices.first(where: { $0.id == device.id })?.state.label ?? L10n.text("已断开"))
            LabeledContent(L10n.text("序列号")) { Text(device.serial).textSelection(.enabled).font(.callout.monospaced()) }
            Divider()
            Toggle(L10n.text("剪贴板同步"), isOn: Binding(
                get: { model.clipboard.isEnabled(device.id) },
                set: { model.clipboard.setEnabled($0, for: device.id) }))
                .toggleStyle(.switch)
            Text(model.clipboard.status(device.id).title).font(.caption).foregroundStyle(.secondary)
            if model.mirrors.sessions[device.id] != nil {
                Divider()
                if let session = model.mirrors.sessions[device.id] {
                    LabeledContent(L10n.text("镜像屏幕"), value: L10n.text("屏幕 \(session.displayID)"))
                }
                Button(L10n.text("结束镜像"), role: .destructive) { model.mirrors.stop(device.id); dismiss() }
            }
            HStack { Spacer(); Button(L10n.text("完成")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 380)
    }
}

struct FailureView: View {
    let failure: MirrorFailure
    let retry: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showDetails = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(failure.application == nil ? L10n.text("无法开启镜像") : L10n.text("无法打开应用窗口"), systemImage: "exclamationmark.triangle").font(.title2.weight(.semibold))
            Text(failure.application.map { "\($0.name) · \(failure.device.name)" } ?? failure.device.name).font(.headline)
            Text(failure.message).fixedSize(horizontal: false, vertical: true)
            if !failure.log.isEmpty {
                DisclosureGroup(L10n.text("运行详情"), isExpanded: $showDetails) {
                    ScrollView {
                        Text(failure.log).font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 180).padding(.top, 8)
                }.font(.callout)
            }
            HStack {
                Spacer()
                Button(L10n.text("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("重试"), action: retry).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 420)
    }
}

struct DisplayPickerView: View {
    let device: AndroidDevice
    @Bindable var model: AppModel
    @State private var selection: DisplaySelection = .automatic
    @Environment(\.dismiss) private var dismiss

    private var snapshot: DisplaySnapshot { model.displays[device.id] ?? .init(displays: []) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("选择镜像屏幕")).font(.title2.weight(.semibold))
                    Text(device.name).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.chooseDisplay(device) } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(model.preparing.contains(device.id)).help(L10n.text("重新读取屏幕"))
            }
            if let error = model.displayError {
                Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    .lineLimit(5)
            }
            ScrollView {
                VStack(spacing: 5) {
                    option(.automatic, title: L10n.text("自动选择屏幕"), subtitle: automaticSubtitle,
                           symbol: "rectangle.2.swap")
                    Divider().padding(.vertical, 5)
                    ForEach(snapshot.displays) { display in
                        option(.fixed(display.id), title: display.title,
                               subtitle: "\(display.resolution) · \(display.status)",
                               symbol: "smartphone")
                    }
                }
            }.frame(height: min(CGFloat(snapshot.displays.count + 1) * 66 + 20, 300))
            Text(L10n.text("自动模式在屏幕切换后重新开启镜像。手动选择会固定屏幕；系统未提供内外屏名称时，以编号和分辨率区分。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if model.preparing.contains(device.id) { ProgressView().controlSize(.small) }
                Spacer()
                Button(L10n.text("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.mirrors.sessions[device.id] == nil ? L10n.text("开启镜像") : L10n.text("切换屏幕")) {
                    model.startDisplay(device, selection: selection)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection.resolve(in: snapshot) == nil || model.preparing.contains(device.id))
            }
        }
        .padding(24).frame(width: 440)
        .onAppear { selection = model.savedSelection(for: device) ?? .automatic }
    }

    private var automaticSubtitle: String {
        if let display = snapshot.automaticDisplay() {
            let off = display.state == "OFF" || display.state?.hasPrefix("DOZE") == true
            let detail = off ? L10n.text("\(display.resolution) · 保持熄屏") : display.resolution
            return L10n.text("当前：\(display.title) · \(detail)")
        }
        return L10n.text("无法判断当前屏幕，可直接选择下方屏幕")
    }

    private func option(_ value: DisplaySelection, title: String, subtitle: String, symbol: String) -> some View {
        Button { selection = value } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title3).foregroundStyle(.secondary).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selection == value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selection == value ? Color.accentColor : Color.secondary.opacity(0.3))
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(selection == value ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(title)，\(subtitle)")
    }
}
