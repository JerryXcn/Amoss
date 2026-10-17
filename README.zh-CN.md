# Amoss

**Android & Mac, One Shared Space —— Android 与 Mac，共享一个工作空间。**

[English](README.md)

Amoss 是通过 USB 连接安卓设备的原生 macOS 菜单栏应用。它支持设备镜像、独立应用窗口和后台文字剪贴板同步。安装包内置 ADB、scrcpy 及所需运行库。

## 功能

- **菜单栏驻留**：自动发现已连接的 USB 设备，无需一直打开主界面。
- **设备镜像**：使用 Mac 键鼠操作手机，底部提供原生导航图标和悬停提示。
- **折叠屏与多显示屏**：自动跟随物理亮屏，也可手动固定屏幕。
- **独立应用窗口**：查看、搜索可启动应用；支持的应用运行在虚拟显示屏中，手机可同时操作其他应用。
- **后台剪贴板**：无需镜像即可双向同步文字，每台设备独立保存开关。
- **中英文切换**：在设置中切换；默认跟随系统，中文系统使用简体中文，其他语言系统使用英文。
- **完整安装包**：使用者无需安装 Homebrew、Android SDK、Java 或 Xcode。

## 安装要求

- Apple Silicon Mac，macOS 15 或更新版本。界面随系统版本与外观设置变化。
- 开启 USB 调试的安卓设备，以及支持数据传输的 USB 线。
- 当前发布目标为 **0.5.0**。Intel 构建仍属实验支持，需要在 Intel Mac 上编译，尚未验证。

从本仓库的 **Releases** 页面下载 ARM64 DMG 和对应的 `.sha256` 文件。在下载目录运行：

```sh
shasum -a 256 -c Amoss-0.5.0-arm64.dmg.sha256
```

打开 DMG，将 Amoss 拖入 Applications，再启动应用。连接手机并允许 USB 调试授权。Amoss 默认出现在菜单栏中，选择设备即可开启镜像，选择「主界面」才显示完整设备列表。

本地构建默认使用 ad-hoc 签名，未经过 Apple 公证。只有发布说明明确标注时，该安装包才是已公证版本。对于你信任但未公证的安装包，首次启动被阻止后，可能需要在「系统设置 → 隐私与安全性」中选择「仍要打开」。不要全局关闭 Gatekeeper。

## 日常操作

| 操作 | 入口 |
| --- | --- |
| 开启或显示镜像 | 菜单栏 → 设备 → 镜像 |
| 查看手机应用 | 主界面设备行「应用」，或设备子菜单「应用」 |
| 选择物理显示屏 | 设备 → 镜像屏幕 |
| 返回、主页、多任务 | 镜像窗口底部图标栏 |
| 熄灭手机实体屏并保留镜像 | 月亮图标；再次点击太阳图标恢复亮屏 |
| 开关后台文字同步 | 设备 → 剪贴板同步 |
| 切换语言、调整镜像设置 | 设置 |
| 关闭主界面后继续运行 | 关闭窗口后，仍可通过菜单栏操作 |
| 结束 Amoss 创建的会话 | 退出 Amoss |

新授权设备默认开启剪贴板同步。**所有开启同步的设备共享最新复制的文字。** 关闭某台设备的开关后，该设备不再自动收发。首次连接不会覆盖两端原有剪贴板。仅支持文字，最大约 256 KB，不支持图片与文件。轮询、权限、存储和多设备行为见[隐私说明](PRIVACY.md)。

## 兼容性与限制

- 独立窗口中的应用仍在手机上运行，共用原账号和数据。部分应用不支持虚拟屏；打开已经运行的应用可能将其任务从手机移入窗口。这不是账号多开或数据隔离。独立应用窗口暂不转发声音。
- 展开或合盖会重启物理屏镜像，可能短暂中断。无法可靠判断时可手动选屏。
- 熄屏功能不会解锁手机，也不会绕过受保护内容。部分手机从深度休眠唤醒时可能短暂亮屏。
- 复制粘贴需要 Android 7+，声音转发需要 Android 11+。虚拟屏、输入注入和后台剪贴板能力取决于 Android 与厂商实现；部分手机需要额外开启 USB 调试安全设置。
- 手机锁屏时可能不提供剪贴板内容；Mac 端也遵循系统剪贴板读取权限。
- 实机验证覆盖了 PGT110 / Android 16 的内外屏镜像、计算器与手机同时操作、后台剪贴板同步。结果不代表所有机型和应用都兼容。

## 构建与测试

开发机需要 **Xcode 26+、Python 3.12+、CMake 3.20+**，并与目标架构一致。安装应用的用户不需要这些工具。

```sh
bash scripts/check-environment.sh
bash scripts/check.sh
bash scripts/build.sh arm64
bash scripts/test-mirror.sh arm64
bash scripts/package.sh arm64
```

完整构建会下载固定版本、经过 SHA-256 校验的依赖。首次运行还会在 `build/helper-tools` 安装固定版本的 Python 构建工具。产物为 `dist/Amoss.app`、`dist/Amoss-0.5.0-arm64.dmg` 及校验文件。

环境配置、源码重建、签名、公证、发布检查与生成文件规则见[构建与发布](docs/BUILDING.md)；提交修改前请阅读[贡献说明](CONTRIBUTING.md)。

## 项目结构

| 路径 | 用途 |
| --- | --- |
| `Sources/Amoss/` | SwiftUI/AppKit 界面、菜单栏与应用生命周期 |
| `Sources/AmossCore/` | 设备发现、会话、剪贴板协议和本地化 |
| `Integrations/Scrcpy/` | 原生操作栏、窗口适配与控制桥接 |
| `Integrations/Clipboard/` | 需明确指定设备的 USB 集成测试 |
| `Tests/` | Swift 核心测试与 Python 构建、打包测试 |
| `Resources/` | 元数据、图标、安装说明和第三方许可证 |
| `scripts/` | 依赖下载、构建、验证与打包 |

`Package.swift` 用于核心测试，`Amoss.xcodeproj` 用于构建完整应用，两者都需要保留。Xcode 工程由 `scripts/generate-project.py` 生成；使用 Xcode 前先运行 `build.sh` 准备内置工具。单独执行 `swift run` 不会生成完整独立应用包。

## 许可证与致谢

Amoss 自有代码、文档和应用图标采用 [Apache-2.0](LICENSE)，另见 [NOTICE](NOTICE)。

感谢 [scrcpy](https://github.com/Genymobile/scrcpy)、[ADB](https://android.googlesource.com/platform/packages/modules/adb/)、[FFmpeg](https://ffmpeg.org/)、[SDL](https://libsdl.org/) 和 [dav1d](https://code.videolan.org/videolan/dav1d)。这些组件保持各自许可证；其中镜像客户端使用 LGPL-2.1-or-later 授权的 FFmpeg。每个安装包的 **Third-party sources** 目录提供对应源码与重建说明，重新分发二进制时应同时保留对应源码获取途径。详见[第三方声明](Resources/ThirdPartyNotices.txt)。

[更新记录](CHANGELOG.md) · [安全反馈](SECURITY.md) · [隐私说明](PRIVACY.md)
