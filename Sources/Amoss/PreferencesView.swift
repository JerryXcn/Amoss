import SwiftUI
#if canImport(AmossCore)
import AmossCore
#endif

struct PreferencesView: View {
    @Bindable var preferences: Preferences
    var body: some View {
        Form {
            Section {
                Picker(L10n.text("语言"), selection: $preferences.language) {
                    Text(L10n.text("跟随系统")).tag(AppLanguage.system)
                    Text("中文（简体）").tag(AppLanguage.chinese)
                    Text("English").tag(AppLanguage.english)
                }
                .accessibilityIdentifier("app-language")
            } header: { Text(L10n.text("通用")) } footer: {
                Text(L10n.text("语言切换立即生效。跟随系统时，中文系统显示中文，其他语言默认显示英文。"))
            }
            Section {
                Picker(L10n.text("画质"), selection: $preferences.quality) {
                    ForEach(MirrorQuality.allCases) { Text($0.title).tag($0) }
                }
                Text(preferences.quality.detail).font(.caption).foregroundStyle(.secondary)
                Toggle(L10n.text("播放手机声音"), isOn: $preferences.audio)
                Toggle(L10n.text("镜像时保持手机亮屏"), isOn: $preferences.stayAwake)
            } header: { Text(L10n.text("镜像")) } footer: { Text(L10n.text("声音转发需要 Android 11 或更新版本。")) }
            Section {
                Label(L10n.text("剪贴板按设备单独控制"), systemImage: "doc.on.clipboard")
            } footer: {
                Text(L10n.text("在菜单栏的设备子菜单或主界面设备选项中开关「剪贴板同步」。开启后无需镜像，Mac 与手机复制的文字会自动互通。开关立即生效。"))
            }
            Section {
                HStack {
                    Text(L10n.text("画质、声音和亮屏设置在下次开启镜像时生效。"))
                    Spacer()
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 530)
        .navigationTitle(L10n.text("设置"))
    }
}
