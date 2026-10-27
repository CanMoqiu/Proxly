# 贡献指南

**简体中文** · [English](CONTRIBUTING.en.md) · [文档目录](docs/README.md)

感谢你参与 Proxly。请先阅读 [README](README.md)、[安全说明](SECURITY.md) 和对应的构建文档，再提交问题或代码。

## 开发环境

- Flutter 3.47.5
- Android Studio 或 Xcode（按目标平台安装）
- OpenClash / Mihomo 控制器和可测试的 SSH/SFTP 环境

Windows 可以运行 Dart 静态检查和测试；iOS Release 构建需要 GitHub Actions 的 macOS 环境。不要把控制器密钥、SSH 密码、签名密钥、个人配置、构建产物或本地 AI/缓存目录提交到仓库。

## 提交前检查

```text
flutter pub get --enforce-lockfile
flutter analyze
flutter test
```

修改平台代码时，请同时说明测试平台、系统版本和未覆盖的真机行为。涉及版本、构建或发布时，遵循 `docs/mobile-builds.zh-CN.md` 以及维护者的版本规则。

## 提交合并请求

问题反馈、功能建议和 PR 默认使用中文，也欢迎英文。请说明变更目的、用户可见行为和验证结果。Git 提交及推送说明允许仅使用英文。一个 PR 聚焦一个问题；不要提交证书、令牌、私有路由器配置或与软件构建无关的文件。安全问题请按 [安全说明](SECURITY.md) 处理，不要公开发布敏感细节。

## 文档与语言

新增或修改公开文档时，同步维护简体中文和英文版本，并在页首提供语言切换。默认入口和模板使用中文；命令、文件路径、API 字段和标识符保持原样。英文文档应链接到对应英文页面。完整约定见 [仓库语言约定](docs/repository-language.zh-CN.md)。
