# Amoss

**Android & Mac, One Shared Space.**

[简体中文](README.zh-CN.md)

A native macOS menu bar app for using your Android devices over USB. Mirror a
phone, open supported Android apps in separate windows, and share text clipboards.
ADB, scrcpy and their runtime dependencies are included in the installer.

## Features

- **Menu bar first:** browse connected USB devices without keeping a main window open.
- **Device mirroring:** mouse and keyboard control, native navigation buttons and tooltips.
- **Foldables and multiple displays:** follow the active physical display or select one manually.
- **Independent app windows:** browse and search installed launchable apps; supported apps run on a virtual display while the phone remains available for another app.
- **Background clipboard:** bidirectional text sync without a mirror window, with a persistent switch for each device.
- **Chinese and English:** switch in Settings; by default a Chinese system uses Simplified Chinese, and other system languages use English.
- **Self-contained installation:** users do not need Homebrew, Android SDK, Java or Xcode.

## Requirements and installation

- Apple Silicon Mac running macOS 15 or later. The interface follows the host macOS appearance.
- An Android device with USB debugging enabled and a USB cable that supports data transfer.
- Current release target: **0.5.0**. Intel builds are experimental and require an Intel Mac to build; they have not been validated.

Download the ARM64 DMG and its `.sha256` file from this repository's **Releases**
page. In their download directory, verify:

```sh
shasum -a 256 -c Amoss-0.5.0-arm64.dmg.sha256
```

Open the DMG, drag Amoss into Applications, then open it. Connect the phone and
approve its USB debugging prompt. Amoss appears in the menu bar; select a device
to start mirroring, or choose **Main Window** to show the device list.

Local builds use ad-hoc signing and are not notarized. A release is notarized
only if its release notes explicitly say so. For a trusted unnotarized build,
macOS may require **System Settings → Privacy & Security → Open Anyway** after
an initial blocked launch. Do not disable Gatekeeper globally.

## Everyday use

| Action | Where |
| --- | --- |
| Open or focus a mirror | Menu bar → device → mirror |
| Browse Android apps | Device row → Apps, or device submenu → Apps |
| Choose a physical display | Device → Mirror Display |
| Back / Home / Recent apps | Mirror window's bottom icon bar |
| Turn off the phone panel while retaining the mirror | Moon icon; click the sun icon to restore it |
| Enable or disable background text sharing | Device → Clipboard Sync |
| Change language or mirror settings | Settings |
| Keep running after closing the main window | Close the window; use the menu bar to reopen it |
| End Amoss-owned sessions | Quit Amoss |

Clipboard sync is enabled by default for newly authorized devices. **All enabled
devices share the latest copied text.** A disabled device does not automatically
send or receive text. Initial connection does not overwrite existing clipboards.
Only text is supported, up to approximately 256 KB; images and files are excluded.
See [Privacy](PRIVACY.md) for polling, permissions, storage and multi-device behavior.

## Compatibility and limits

- App windows still run on the phone and use the same account and data. Some apps cannot run on a virtual display; launching an existing app may move its task from the phone. This is not account or data isolation. App windows currently do not forward audio.
- Fold/unfold transitions restart the physical mirror and may briefly interrupt it. Manual display selection remains available.
- Turning off the panel does not unlock the phone or bypass protected content. Some devices may briefly light up when waking from deep sleep.
- Clipboard copying/pasting requires Android 7+; audio forwarding requires Android 11+. Virtual displays, input injection and background clipboard access depend on Android and the device vendor. Some phones require an additional USB debugging security setting.
- The phone may withhold clipboard contents while locked. macOS pasteboard permissions also apply.
- Physical device validation has covered PGT110 on Android 16, including foldable displays, calculator/phone simultaneous use and background clipboard sharing. This is not a compatibility guarantee for other devices or apps.

## Build and test

Development requires **Xcode 26+**, **Python 3.12+**, and **CMake 3.20+** on a Mac
matching the target architecture. The installed app requires none of those tools.

```sh
bash scripts/check-environment.sh
bash scripts/check.sh
bash scripts/build.sh arm64
bash scripts/test-mirror.sh arm64
bash scripts/package.sh arm64
```

The full build downloads pinned, SHA-256-verified dependencies. First use also
installs pinned Python build tools into `build/helper-tools`. The output is
`dist/Amoss.app` and `dist/Amoss-0.5.0-arm64.dmg` with a checksum file.

Read [Build and release](docs/BUILDING.md) for environment setup, source rebuilds,
signing, notarization, release checks and the generated-file policy. Read
[Contributing](CONTRIBUTING.md) before submitting changes.

## Project layout

| Path | Purpose |
| --- | --- |
| `Sources/Amoss/` | SwiftUI/AppKit UI, menu bar and application lifecycle |
| `Sources/AmossCore/` | Device discovery, sessions, clipboard protocol and localization |
| `Integrations/Scrcpy/` | Native toolbar, window integration and control bridge |
| `Integrations/Clipboard/` | Explicit opt-in USB integration test harness |
| `Tests/` | Swift core tests and Python build/release tests |
| `Resources/` | Metadata, icons, installation text and third-party licenses |
| `scripts/` | Pinned downloads, build, validation and packaging |

`Package.swift` supports core tests; `Amoss.xcodeproj` builds the complete app.
The Xcode project is generated by `scripts/generate-project.py`. Prepare the
bundled tools with `build.sh` before building from Xcode. `swift run` alone does
not produce a standalone app bundle.

## License and acknowledgements

Amoss original code, documentation and app icons are licensed under
[Apache-2.0](LICENSE). See [NOTICE](NOTICE).

Amoss uses [scrcpy](https://github.com/Genymobile/scrcpy),
[ADB](https://android.googlesource.com/platform/packages/modules/adb/),
[FFmpeg](https://ffmpeg.org/), [SDL](https://libsdl.org/) and
[dav1d](https://code.videolan.org/videolan/dav1d). Their own licenses continue to
apply. In particular, the mirror client uses FFmpeg under LGPL-2.1-or-later.
Corresponding source code and rebuild instructions accompany each installer in
**Third-party sources**. Keep them available when redistributing binaries.
See [third-party notices](Resources/ThirdPartyNotices.txt).

[Changelog](CHANGELOG.md) · [Security](SECURITY.md) · [Privacy](PRIVACY.md)
