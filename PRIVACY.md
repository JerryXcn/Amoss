# Privacy / 隐私说明

Amoss has no account system, analytics SDK, advertising or cloud synchronization.
Its application code uses the local ADB service and loopback connections to
communicate with authorized USB devices. Dependency downloads happen while
building, not as a requirement of using an installed app.

## Clipboard

- Newly authorized devices default to automatic text sync; each device has a persistent switch. A previous global opt-out is retained during migration.
- All enabled devices share the latest copied text through the Mac. Disable a device before copying sensitive text that should not reach it.
- Initial connection or re-enabling sync does not replace existing clipboards. Subsequent copies do.
- Only UTF-8 text, approximately 256 KB maximum, is forwarded. No image/file sync or clipboard history is provided. Amoss does not write clipboard bodies to logs or files.
- Mac changes are checked using public `NSPasteboard.changeCount`: every 2 seconds while idle, temporarily every 0.5 seconds after activity, and every 2 seconds in Low Power Mode. Checking pauses while sleeping, with the display off, with the user session inactive, or with no enabled connected devices. Wake and application-activation notifications can trigger an immediate check.
- Android sends clipboard events through a control-only scrcpy session. This does not create a mirror window, wake/unlock the phone or inject paste keys.
- macOS pasteboard permission and Android lock-screen restrictions apply. Manual mirror copy/paste remains available when automatic sync is off.

## Local state and diagnostics

Preferences are stored in the app's macOS UserDefaults domain. They include
language, mirror options, per-device clipboard/display choices keyed by device
identifier, and up to five recent app package names per device. The full app list
is cached in memory and discarded when the device disconnects. The shared ADB
service maintains its own authorization keys outside Amoss; Amoss does not bundle
or upload those keys.

Session diagnostics are bounded and can contain device names/identifiers,
package names and tool errors. Inspect and redact diagnostics before sharing.
Closing a mirror releases its session; quitting Amoss ends its own sessions and
forwards without shutting down the shared ADB server. OS clipboard data remains
under the control of macOS/Android and any other applications with access to it.

---

Amoss 没有账号系统、统计 SDK、广告或云端同步。应用通过本机 ADB 服务和回环连接与已授权的 USB 设备通信。依赖下载发生在开发构建阶段，已安装应用无需下载开发环境。

## 剪贴板

- 新授权设备默认开启自动文字同步，每台设备独立保存开关；迁移时保留旧版全局关闭选择。
- 所有开启的设备通过 Mac 共享最新复制的文字。复制不应传给某台设备的敏感文字前，请先关闭该设备开关。
- 刚连接或重新开启时不覆盖原有剪贴板，之后的新复制才会同步。
- 仅传输 UTF-8 文字，最大约 256 KB；不提供图片、文件同步或历史记录，不把剪贴板正文写入日志和文件。
- Mac 端通过公开 API 检查 `changeCount`：空闲每 2 秒一次，活跃后短暂加快至 0.5 秒；低电量模式保持 2 秒。睡眠、熄屏、用户会话切走或没有开启同步的设备时暂停检查；唤醒和应用激活事件可触发立即检查。
- Android 端通过仅控制连接的 scrcpy 服务推送事件，不创建镜像、不唤醒或解锁手机、不注入粘贴按键。
- 遵循 macOS 剪贴板权限和 Android 锁屏限制。关闭自动同步后仍可在镜像中手动复制粘贴。

## 本地数据与诊断

偏好保存在 macOS 的应用 UserDefaults 中，包括语言、镜像选项、按设备标识保存的剪贴板与显示屏选择，以及每台设备最多 5 个最近打开的应用包名。完整应用列表仅缓存在内存中，设备断开后清除。共享 ADB 服务自行管理授权密钥，Amoss 不内置或上传这些密钥。

会话诊断有大小限制，但可能包含设备名称、标识、包名和工具错误；分享前请检查并脱敏。关闭镜像释放对应会话，退出应用结束自建会话和转发，不停止共享 ADB 服务。系统剪贴板仍由 macOS、Android 及其他有权限的应用管理。
