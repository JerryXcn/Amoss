# Security policy / 安全反馈

Security fixes target the latest release. Earlier 0.x builds are development
snapshots and do not have a separate maintenance commitment.

Use this repository's **Security → Report a vulnerability** for sensitive reports
when private vulnerability reporting is enabled. Do not post exploit details or
private data in a public issue. If that option is unavailable, open a minimal
issue titled **Private security contact requested** with no technical details;
a maintainer can arrange a private channel. No response-time guarantee is made.

Include the affected version, platform, impact and a minimal reproduction using
synthetic data. Never send ADB private keys, signing certificates, access tokens,
clipboard contents, device serials or complete device logs. USB debugging grants
powerful access: authorize only computers you trust and revoke authorization when
it is no longer needed.

---

安全修复面向最新发布版本，较早的 0.x 开发版本不单独承诺维护。

敏感问题优先通过仓库 **Security → Report a vulnerability** 私密提交。若尚未启用该入口，请仅创建标题为「请求私密安全反馈渠道」的 Issue，不包含漏洞技术细节，等待维护者提供私密渠道。项目暂不承诺固定响应时间。

报告应包含受影响版本、平台、影响和使用虚构数据的最小复现。不要上传 ADB 私钥、签名证书、访问令牌、剪贴板正文、设备序列号或完整设备日志。USB 调试权限较高，请只授权可信电脑，使用结束后可在手机上撤销授权。
