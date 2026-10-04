# 贡献指南

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

## Pull Request

PR 使用英文标题和正文，说明变更目的、用户可见行为和验证结果。一个 PR 聚焦一个问题；不要提交证书、令牌、私有路由器配置或与软件构建无关的文件。安全问题请按 [SECURITY.md](SECURITY.md) 处理，不要公开发布敏感细节。
