# Contributing / 贡献说明

Amoss welcomes focused bug fixes, compatibility reports, accessibility improvements
and Chinese/English translations. Please discuss large changes in an issue first.
Contributions are accepted under [Apache-2.0](LICENSE); retain third-party notices.

1. Read [Build and release](docs/BUILDING.md) and run `bash scripts/check.sh`.
2. Keep changes scoped; add meaningful tests for behavior or release-process changes.
3. For UI text, update both `Sources/AmossCore/Resources/*/Localizable.strings` catalogs and run `python3 scripts/check-localizations.py`.
4. Edit `scripts/generate-project.py` when changing generated project settings; regenerate the project and commit both.
5. Edit `Integrations/Scrcpy/` or `scripts/prepare-mirror-source.py`, not downloaded sources. Preserve per-file upstream modification notices.
6. Build the complete app and run `bash scripts/test-mirror.sh` for mirror integration changes. Hardware testing is opt-in; CI never requires a phone.
7. Describe the problem, resulting behavior and checks in the pull request. Report untested device behavior honestly.

Do not commit `build/`, `dist/`, downloaded dependencies, local design exports,
credentials, device serials, installed-app dumps, clipboard contents or private
screenshots. Public compatibility reports should name the model and OS version,
not a unique device identifier. Be respectful, give actionable feedback and do
not disclose another person's private information.

---

欢迎提交范围明确的修复、兼容性反馈、无障碍改进和中英文翻译。较大的功能调整请先通过 Issue 讨论。贡献采用 [Apache-2.0](LICENSE)，请保留第三方声明。

1. 阅读[构建与发布](docs/BUILDING.md)，运行 `bash scripts/check.sh`。
2. 保持修改聚焦；行为或发布流程变化应有必要的测试。
3. 界面文案同时更新两种语言的 `Localizable.strings`，运行翻译检查。
4. 修改工程设置时编辑生成脚本，重新生成并提交脚本和 Xcode 工程。
5. scrcpy 改动写在 `Integrations/Scrcpy/` 或适配脚本中，不直接修改下载目录；保留上游文件修改声明。
6. 镜像适配变更应完成完整构建和 C 协议测试。实机测试需主动指定设备，CI 不连接手机。
7. PR 说明问题、修改后的行为和验证结果，如实标注未验证的机型或场景。

不要提交构建产物、下载依赖、设计历史、凭据、设备序列号、应用列表转储、剪贴板正文或私人截图。兼容性反馈只需要机型和系统版本。交流中请尊重他人，提供具体反馈，保护个人信息。
