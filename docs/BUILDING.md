# Build and release / 构建与发布

## Developer environment

Use a Mac matching the target architecture, full **Xcode 26+**, **Python 3.12+**,
and **CMake 3.20+**. Runtime support starts at macOS 15; a development toolchain
may require a newer macOS. The current local validation uses Xcode 27.1,
Python 3.14.5 and CMake 4.4.3 on Apple Silicon. CI uses the `xcode-27` ARM64 runner
and Python 3.12. Intel is experimental and is not part of the release matrix.

Install full Xcode and select its developer directory. If Homebrew is available,
`brew install python@3.12 cmake` supplies the other tools; ensure the selected
Python's `bin`/`libexec/bin` is before Apple's Python in PATH. Run
`python3 --version`, `xcodebuild -version`, then:

```sh
bash scripts/check-environment.sh
bash scripts/check.sh
bash scripts/build.sh arm64
bash scripts/test-mirror.sh arm64
bash scripts/package.sh arm64
```

Use a checkout path without whitespace for the C/Meson/Xcode toolchain flags.
The installed application itself supports paths containing spaces.
`build.sh` generates `Amoss.xcodeproj`, app icons and bundled resources. Open the
project afterward for development. Avoid hand-editing the generated project.

`check.sh` runs core Swift tests, Python build-tool tests, localization validation
and shell syntax checks. Mirror protocol tests require the full helper build.
None of these commands operate a connected phone. UI/hardware checks are separate.

## Downloads and caches

`scripts/dependencies.json` pins source and binary URLs and SHA-256 values.
Every downloaded or cached archive is verified before use. Corrupt archives fail
closed; after investigating the source, remove only that cached archive and retry.
Downloads use a temporary file and are promoted only after verification.

Python build tools are pinned in `scripts/helper-build-requirements.txt` and
installed into `build/helper-tools`; they are development-only. A changed
requirements file refreshes this environment. Build tools come from PyPI and
require network access on first use. Native dependency archives use fixed hashes;
Python build-tool versions are pinned but their transitive wheel hashes are not.

`build/mirror-sources` intentionally preserves extracted sources for local LGPL
modifications. `build/mirror-deps/<arch>` caches compiled libraries. Changes to the dependency manifest, build recipe, checkout path or toolchain
automatically invalidate the compiled native cache. After manually editing extracted
library source, remove that compiled cache to rebuild your modifications. CI always
builds without native caches.
Never mix build directories from different checkout paths or architectures.

## Signing, packaging and provenance

By default, the app is ad-hoc signed. Set `AMOSS_SIGNING_IDENTITY` to a valid
Developer ID Application identity in your local keychain for Developer ID signing.
Do not commit certificates, private keys or credentials. Signing does not notarize.

`AMOSS_OUTPUT_DIR=build/release bash scripts/build.sh arm64` chooses another app
output directory. Package it with:

```sh
bash scripts/package.sh arm64 build/release/Amoss.app
```

Packaging compares the app/helper versions, architecture and recorded source
fingerprint against the current inputs. If source inputs changed, rebuild first.
The fingerprint includes application/integration sources, resources, licenses and
build scripts. This detects accidental stale packaging; it is not an attestation
against a malicious builder or a promise of bit-for-bit binary reproducibility.

The installer contains the app, bilingual installation instructions, LICENSE,
NOTICE, dependency source archives and the complete modified mirror client with
its SwiftUI sources and build recipes. Source tarballs normalize ownership and
timestamps; `SOURCE_DATE_EPOCH` can supply a stable timestamp (default: zero).
Source archive hashes are recorded in `Third-party sources/manifest.json`.

The DMG checksum records the basename, so recipients can run `shasum -a 256 -c`
from their download directory. Bundle validation checks signatures, runtime
libraries, language catalogs, licenses, version metadata and local home-path leaks
in Amoss-built executables. Original upstream ADB binaries retain upstream metadata.

To notarize a Developer ID build, use Apple's `notarytool` and a credential profile
stored in the local keychain. One possible workflow after building the DMG is:

```sh
# AMOSS_NOTARY_PROFILE names an existing keychain profile; it is not a password.
xcrun notarytool submit dist/Amoss-0.5.0-arm64.dmg --keychain-profile "$AMOSS_NOTARY_PROFILE" --wait
xcrun stapler staple dist/Amoss-0.5.0-arm64.dmg
xcrun stapler validate dist/Amoss-0.5.0-arm64.dmg
(cd dist && shasum -a 256 Amoss-0.5.0-arm64.dmg > Amoss-0.5.0-arm64.dmg.sha256)
```

Review the notary log and test the downloaded installer on another Mac.
Notarization is not run by the current CI; its artifacts are ad-hoc development
builds. [Apple notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Rebuild the corresponding source package

Follow `Third-party sources/README.txt` in the DMG. It specifies extraction,
copying the supplied upstream archives into the new build tree and rebuilding the
client. First use still downloads Python build tools. The complete modified
scrcpy tree is included for inspection; the recipe regenerates it from the pinned
original source plus the Amoss patch script. Each modified upstream file is marked.

To change FFmpeg, first run the build, edit `build/mirror-sources/ffmpeg-9.0.2`,
remove `build/mirror-deps/<arch>`, then rerun `bash scripts/build-mirror.sh` to
rebuild dependencies and relink. Preserve those local edits; do not run a cleanup
that removes extracted sources. For distribution of such modifications, update
the provided corresponding sources and notices too.

## Optional USB test

Only run this with a device you intend to test, unlocked. It temporarily writes
synthetic text to the phone clipboard and attempts to restore the original text;
it never uses the Mac's general pasteboard. Interruption may prevent restoration.

```sh
swiftc -parse-as-library -swift-version 6 -target arm64-apple-macos15.0 \
  -module-cache-path build/module-cache Sources/AmossCore/*.swift \
  Sources/Amoss/ClipboardSyncStore.swift Integrations/Clipboard/ClipboardSmoke.swift \
  -o build/clipboard-smoke
python3 scripts/test-clipboard-device.py --serial YOUR_TEST_DEVICE_SERIAL
```

## Public release process

1. Update app/helper version metadata together, the changelog and versioned examples. Build from a clean source checkout.
2. Run core/build-tool/localization tests, the complete build and mirror protocol tests. Package and verify the DMG; extract its corresponding source archive into another directory and verify the helper can rebuild.
3. Check startup, language switching, USB discovery, physical and virtual displays and clipboard behavior on authorized hardware. Record only the checks actually performed.
4. Review the intended Git file list. Build caches, local design history, downloads, DMGs and user data are ignored; do not upload the entire workspace as a ZIP.
5. Create the GitHub repository when ready. Enable private vulnerability reporting and require the CI checks for merging. Use a version tag matching the app version.
6. Attach the DMG and checksum to a GitHub Release, clearly state signing/notarization and tested platforms, and keep the corresponding sources accessible. The current workflow only produces CI artifacts; it does not publish releases automatically.

## 中文说明

开发机需要与目标架构一致的 Mac、完整 **Xcode 26+、Python 3.12+、CMake 3.20+**。运行应用只需 macOS 15+，开发工具可能要求更高系统版本。当前本机验证环境为 Xcode 27.1、Python 3.14.5、CMake 4.4.3，CI 使用 `xcode-27` ARM64 与 Python 3.12。Intel 尚属实验支持。

选择完整 Xcode 后，确保 `python3` 指向 3.12 或更高版本，而非系统旧版 Python。上方五条构建命令依次检查环境、运行基础测试、编译完整应用、验证镜像协议并生成安装包。构建目录请避免空白字符；安装后的应用可以位于含空格的路径。Xcode 工程和图标由脚本生成，不要单独手改生成的工程设置。

依赖地址与校验值集中在 `scripts/dependencies.json`。新下载与缓存包都先校验，失败即停止；临时文件校验成功才进入缓存。Python 构建工具固定版本，首次从 PyPI 下载，尚未固定其所有间接依赖的 wheel 哈希。依赖清单、构建脚本、目录或工具链变化时，会自动清除过期的原生编译缓存；手动修改解压后的库源码时仍需主动清除对应编译缓存。

默认 ad-hoc 签名。可通过 `AMOSS_SIGNING_IDENTITY` 指定钥匙串中的 Developer ID，但这不等于公证。上方提供手动 `notarytool` 流程；凭据应留在本机钥匙串。公证并装订票据后需重新生成 SHA-256 文件。CI 不使用签名凭据，不公证、不自动发布 Release。

打包会校验主程序和镜像版本、架构及源码指纹，拒绝把旧应用和新源码混装。安装包包含双语说明、许可证、第三方源码及完整镜像改动。源码包规范化所有者与时间戳，默认时间为零，也可指定 `SOURCE_DATE_EPOCH`。源码指纹用于避免意外混包，不是恶意构建者证明，也不宣称二进制逐字节可复现。

镜像重建按 DMG 的 `Third-party sources/README.txt` 操作。提供的完整修改版源码用于检查，脚本从固定上游源码重新应用改动。修改 FFmpeg 时，先完成一次构建，再编辑解压源码，删除对应架构的编译依赖目录并重建，即可重新链接。分发修改版时需同步提供相应源码与声明。

USB 集成测试不会自动运行。必须主动指定用于测试的已解锁手机；它会短暂写入虚构剪贴板文字并尝试恢复原内容，意外中断可能阻止恢复。请勿在 CI 连接私人手机，也不要公开其序列号或测试日志。

公开发布前，统一版本与更新记录，在干净目录验证完整构建、打包及随包源码重建；记录实际完成的实机测试；检查拟提交文件，启用 GitHub 私密漏洞报告。安装包与校验文件放 Releases，源码和开发配置进入 Git。旧设计、缓存与历史安装包保留本地，不上传整个工作目录。
