import SwiftUI
#if canImport(AmossCore)
import AmossCore
#endif

struct DevicesView: View {
    @Bindable var model: AppModel
    @FocusState private var focusedDevice: String?
    @State private var hoveredDevice: String?

    var body: some View {
        @Bindable var mirrors = model.mirrors
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.text("设备")).font(.system(size: 20, weight: .semibold))
                Spacer()
                if !model.devices.isEmpty {
                    Text(L10n.text("\(model.devices.count) 台已连接")).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 16)

            if let error = model.connectionError {
                ConnectionBanner(message: error) { Task { await model.refresh() } }
                    .padding(.horizontal, 24).padding(.bottom, 12)
            } else if let notice = model.notice ?? model.mirrors.notice {
                HStack {
                    Image(systemName: "cable.connector.slash")
                    Text(notice)
                    Spacer()
                    Button { model.notice = nil; model.mirrors.clearNotice() } label: {
                        Image(systemName: "xmark")
                    }.buttonStyle(.plain).accessibilityLabel(L10n.text("关闭提示"))
                }
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 24).padding(.bottom, 8)
            }

            if model.devices.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.devices) { device in
                            DeviceRow(device: device, session: model.mirrors.sessions[device.id],
                                      isPreparing: model.preparing.contains(device.id),
                                      displayCount: model.displays[device.id]?.displays.count ?? 0,
                                      applicationsExpanded: model.expandedApplicationDeviceIDs.contains(device.id),
                                      emphasized: hoveredDevice == device.id || focusedDevice == device.id,
                                      available: model.connectionError == nil,
                                      clipboardEnabled: model.clipboard.isEnabled(device.id),
                                      clipboardStatus: model.clipboard.status(device.id),
                                      toggleClipboard: { model.clipboard.setEnabled(!model.clipboard.isEnabled(device.id), for: device.id) },
                                      retryClipboard: { model.clipboard.retry(device.id) },
                                      activate: { model.activate(device) },
                                      stop: { model.cancelLaunch(device.id) },
                                      screens: { model.chooseDisplay(device) },
                                      applications: { model.toggleApplications(device) },
                                      details: { model.detailDevice = device })
                                .focusable().focusEffectDisabled()
                                .focused($focusedDevice, equals: device.id)
                                .onHover { hoveredDevice = $0 ? device.id : nil }
                                .onKeyPress(.return) { model.activate(device); return .handled }
                                .accessibilityIdentifier("device-\(device.serial)")
                            if model.expandedApplicationDeviceIDs.contains(device.id) {
                                ApplicationsView(device: device, model: model,
                                                 search: Binding(
                                                    get: { model.applicationSearches[device.id, default: ""] },
                                                    set: { model.applicationSearches[device.id] = $0 }))
                                    .padding(.leading, 64).padding(.trailing, 12).padding(.bottom, 12)
                            }
                            if device.id != model.devices.last?.id {
                                Divider().padding(.leading, 64).padding(.trailing, 12)
                            }
                        }
                    }.padding(.horizontal, 12)
                }
                .onMoveCommand { direction in
                    guard !model.devices.isEmpty else { return }
                    let current = model.devices.firstIndex { $0.id == focusedDevice } ?? 0
                    if direction == .down { focusedDevice = model.devices[min(current + 1, model.devices.count - 1)].id }
                    if direction == .up { focusedDevice = model.devices[max(current - 1, 0)].id }
                }
            }

            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 7) {
                    Circle().fill(model.connectionError == nil ? Color.secondary : Color.orange).frame(width: 4, height: 4)
                    Text(model.connectionError == nil ? L10n.text("自动发现 USB 设备") : L10n.text("设备检测暂不可用"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.showingHelp = true } label: { Image(systemName: "questionmark.circle") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help(L10n.text("连接与操作帮助")).accessibilityLabel(L10n.text("连接与操作帮助"))
                }.padding(.vertical, 14)
            }.padding(.horizontal, 24)
        }
        .frame(minWidth: 460, minHeight: 300)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $model.showingHelp) { HelpView() }
        .sheet(item: $model.authorizationDevice) { device in AuthorizationView(device: device) }
        .sheet(item: $model.detailDevice) { device in DeviceDetailsView(device: device, model: model) }
        .sheet(item: $model.displayRequest) { device in DisplayPickerView(device: device, model: model) }
        .sheet(item: $mirrors.failure) { failure in
            FailureView(failure: failure) {
                model.mirrors.failure = nil
                if let current = model.devices.first(where: { $0.id == failure.device.id }) {
                    if let app = failure.application { model.openApplication(app, on: current) }
                    else { model.activate(current) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cable.connector")
                .font(.system(size: 36, weight: .light)).foregroundStyle(.tertiary)
                .padding(.bottom, 2)
            Text(model.hasScanned ? L10n.text("连接你的 Android") : L10n.text("正在查找设备…"))
                .font(.system(size: 17, weight: .semibold))
            Text(L10n.text("使用 USB 数据线连接设备，\n并在手机上开启 USB 调试。"))
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
            Button(L10n.text("连接帮助")) { model.showingHelp = true }
                .buttonStyle(.bordered).padding(.top, 6)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, 20)
    }
}

private struct DeviceRow: View {
    let device: AndroidDevice
    let session: MirrorSession?
    let isPreparing: Bool
    let displayCount: Int
    let applicationsExpanded: Bool
    let emphasized: Bool
    let available: Bool
    let clipboardEnabled: Bool
    let clipboardStatus: ClipboardSyncStatus
    let toggleClipboard: () -> Void
    let retryClipboard: () -> Void
    let activate: () -> Void
    let stop: () -> Void
    let screens: () -> Void
    let applications: () -> Void
    let details: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "smartphone")
                .font(.system(size: 25, weight: .light)).foregroundStyle(.secondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(device.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                HStack(spacing: 5) {
                    if session?.phase == .running {
                        Circle().fill(.green).frame(width: 5, height: 5)
                    }
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if isPreparing || (session != nil && session?.phase != .running) {
                ProgressView().controlSize(.small)
                Button(action: stop) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).disabled(session?.phase == .stopping)
                    .help(L10n.text("取消镜像")).accessibilityLabel(L10n.text("取消镜像"))
            } else if device.state == .unauthorized {
                Button(action: activate) {
                    HStack(spacing: 10) {
                        Text(L10n.text("待授权")).foregroundStyle(.orange)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
                    }
                }.buttonStyle(.plain)
            } else if device.state == .ready {
                Button(action: applications) {
                    HStack(spacing: 5) {
                        Text(L10n.text("应用"))
                        Image(systemName: applicationsExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                    .disabled(!available).help(applicationsExpanded ? L10n.text("收起应用列表") : L10n.text("展开应用列表"))
                    .accessibilityLabel(L10n.text("\(device.name) 的应用"))
                    .accessibilityValue(applicationsExpanded ? L10n.text("已展开") : L10n.text("已收起"))
                    .accessibilityIdentifier("toggle-applications-\(device.id)")
                Group {
                    if emphasized {
                        Button(session == nil ? L10n.text("镜像") : L10n.text("显示"), action: activate).buttonStyle(.borderedProminent)
                    } else {
                        Button(session == nil ? L10n.text("镜像") : L10n.text("显示"), action: activate).buttonStyle(.bordered)
                    }
                }.buttonBorderShape(.capsule).controlSize(.regular).disabled(!available)
                Menu {
                    Toggle(L10n.text("剪贴板同步"), isOn: Binding(get: { clipboardEnabled }, set: { _ in toggleClipboard() }))
                    Text(clipboardStatus.title)
                    if case .issue = clipboardStatus { Button(L10n.text("重新连接剪贴板"), action: retryClipboard) }
                    Divider()
                    Button(L10n.text("选择屏幕…"), action: screens)
                    Button(L10n.text("设备信息…"), action: details)
                    if session != nil { Divider(); Button(L10n.text("结束镜像"), role: .destructive, action: stop) }
                } label: { Image(systemName: "ellipsis").frame(width: 18) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help(L10n.text("设备选项")).accessibilityLabel(L10n.text("\(device.name) 的选项"))
            } else {
                Button(device.state.label, action: details).buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18).frame(height: 80)
        .background(emphasized ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture(perform: activate)
        .accessibilityElement(children: .contain)
    }

    private var subtitle: String {
        if isPreparing { return L10n.text("正在读取屏幕…") }
        if let session {
            switch session.phase {
            case .starting: return L10n.text("正在开启镜像…")
            case .running: return displayCount > 1 ? L10n.text("USB · 屏幕 \(session.displayID) 镜像中") : L10n.text("USB · 镜像中")
            case .stopping: return L10n.text("正在结束…")
            }
        }
        if device.state == .unauthorized { return "\(device.serial) · USB" }
        return displayCount > 1 ? L10n.text("USB · \(displayCount) 个屏幕") : "USB · \(device.state.label)"
    }
}

private struct ConnectionBanner: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(message).font(.callout).lineLimit(4).textSelection(.enabled)
            Spacer(minLength: 0)
            Button(L10n.text("重试"), action: retry).controlSize(.small)
        }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}
