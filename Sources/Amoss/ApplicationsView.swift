import SwiftUI
#if canImport(AmossCore)
import AmossCore
#endif

struct ApplicationsView: View {
    let device: AndroidDevice
    @Bindable var model: AppModel
    @Binding var search: String

    private var allApps: [AndroidApplication] { model.applications[device.id] ?? [] }
    private var results: [AndroidApplication] { allApps.filter { $0.matches(search) } }
    private var loading: Bool { model.loadingApplications.contains(device.id) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.text("\(allApps.count) 个应用")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if loading { ProgressView().controlSize(.mini) }
                Button { model.refreshApplications(device) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(loading).help(L10n.text("刷新应用列表"))
                    .accessibilityLabel(L10n.text("刷新应用列表"))
            }.padding(.bottom, 12)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L10n.text("搜索应用名称或包名"), text: $search).textFieldStyle(.plain)
                    .accessibilityIdentifier("application-search")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(L10n.text("清除应用搜索"))
                }
            }
            .padding(9).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .padding(.bottom, 10)
            if let error = model.applicationErrors[device.id] {
                HStack(alignment: .top) {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.text("重试")) { model.refreshApplications(device) }.controlSize(.small)
                }.padding(.vertical, 8)
            }
            if allApps.isEmpty && loading {
                Text(L10n.text("正在读取手机应用…")).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).frame(height: 100)
            } else if results.isEmpty {
                Text(search.isEmpty ? L10n.text("没有可打开的应用") : L10n.text("没有找到匹配的应用"))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 100)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(results) { app in
                            ApplicationRow(application: app,
                                           session: model.mirrors.session(for: app, device: device),
                                           available: model.connectionError == nil,
                                           open: { model.openApplication(app, on: device) },
                                           close: { model.mirrors.stop(MirrorSessionStore.sessionID(device: device, application: app)) })
                        }
                    }
                }
                .frame(height: min(CGFloat(results.count) * 52, 286))
            }
            Text(L10n.text("点击应用，在独立窗口中打开。手机可同时使用其他应用。"))
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10).padding(.bottom, 12)
        }
        .padding(.horizontal, 12).padding(.top, 12)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("\(device.name) 的应用列表"))
    }
}

private struct ApplicationRow: View {
    let application: AndroidApplication
    let session: MirrorSession?
    let available: Bool
    let open: () -> Void
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Text(String(application.name.prefix(1))).font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary).frame(width: 34, height: 34)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(application.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(application.packageName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let session {
                        if session.phase == .running {
                            Text(L10n.text("已打开")).font(.caption).foregroundStyle(.secondary)
                        } else { ProgressView().controlSize(.small) }
                    } else {
                        Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8).padding(.leading, 8).padding(.trailing, 10).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(!available || session?.phase == .stopping)
            .help(session == nil ? L10n.text("在独立窗口打开\(application.name)") : L10n.text("显示\(application.name)窗口"))
            .accessibilityLabel(L10n.text("\(session == nil ? L10n.text("打开") : L10n.text("显示"))\(application.name)，独立窗口"))
            .accessibilityIdentifier("application-\(application.packageName)")
            if session != nil {
                Button(action: close) { Image(systemName: "xmark").font(.caption).frame(width: 24, height: 28) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).padding(.trailing, 4)
                    .disabled(session?.phase == .stopping).help(L10n.text("关闭应用窗口"))
                    .accessibilityLabel(L10n.text("关闭\(application.name)窗口"))
            }
        }
        .background(hovering ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
    }
}
