# 贡献指南

**简体中文** · [English](CONTRIBUTING.en.md) · [文档目录](docs/README.md)

## 开发环境

使用 `.flutter-version` 固定的 Flutter 3.47.5，以及目标平台的 Android Studio 或 Xcode。iOS 原生构建需要 macOS；Windows 可运行 Dart 分析和 Widget 测试。构建与签名配置见 [构建指南](docs/mobile-builds.zh-CN.md)。

涉及设备功能时，准备 OpenClash、Nikki 或兼容 Mihomo API 的控制器；配置管理还需 SSH/SFTP。测试请使用可恢复的配置，勿提交真实凭据、私钥、个人配置或构建产物。

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
```

按改动范围补充检查：打包脚本运行 `python3 -m unittest discover -s scripts -p 'test_*.py'`；WebView 改动运行 `integration_test/web_panel_smoke_test.dart` 并进行真机验证。模拟回调和模拟器不能代替真实路由器及设备测试。

## 代码结构

| 路径 | 职责 |
| --- | --- |
| `lib/pages/` | 原生页面与 WebView 容器 |
| `lib/services/` | 控制器 API、软件适配、SSH/SFTP、存储和更新 |
| `lib/widgets/` | 共用组件与首页卡片 |
| `lib/l10n/` | 语言设置和界面翻译 |
| `assets/web_panel/` | 上游 Zashboard 发行资源，保留原样 |
| `android/`、`ios/` | 原生工程 |
| `test/`、`integration_test/` | 单元、Widget 和原生集成测试 |
| `scripts/` | 打包、签名准备及产物校验 |

原生页面通过共享数据层获取状态，Web 面板通过本地服务桥接控制器 API；OpenClash 和 Nikki 的 SSH 管理由各自适配器处理。新增功能应复用现有连接状态、存储及重启流程。弹窗遵循 [交互规范](docs/popup-interactions.zh-CN.md)，面板修改遵循 [Zashboard 维护说明](docs/bundled-zashboard.md#资源维护)。

## 代码与合并请求

一个 PR 聚焦一个问题，说明目的、用户可见变化及实际测试结果；未覆盖的平台或真机行为也需写明。涉及安全问题时使用 [私密报告渠道](SECURITY.md)。

源码注释只用英文，解释必要的设计原因、安全边界或兼容约束，不重复代码，不混用中英文。界面文本和本地化内容不受此限制。Git 提交与推送说明使用英文，准确描述变更。

## 文档与仓库语言

- 文档、问题表单和 PR 默认使用简体中文，也欢迎英文交流。公开文档同步维护完整英文版，页首互链，英文页优先链接英文文档。
- 按读者需要组织内容：README 介绍与上手，使用指南说明操作和限制，构建指南集中记录环境与命令。避免重复步骤、界面微调记录和一次性任务报告。
- 命令、路径、API 字段、包名和校验值保持原样。更新功能或限制时同时更新两种语言及相关链接。
- 许可证、上游版权和第三方声明保留原文；译本用于阅读，不替代原许可。
- 工作流提示和讨论表单采用中文在前的双语文本。修改讨论分类后，同步核对 `.github/DISCUSSION_TEMPLATE/<slug>.yml`，文件名须匹配 GitHub 分类的 URL 标识；投票分类不支持表单。
