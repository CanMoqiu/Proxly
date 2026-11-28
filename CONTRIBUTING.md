# 贡献指南

**简体中文** · [English](CONTRIBUTING.en.md) · [文档目录](docs/README.md)

## 开发环境

使用 `.flutter-version` 指定的 Flutter 版本，以及目标平台的 Android Studio 或 Xcode。iOS 原生构建需要 macOS，Windows 可运行静态分析和 Flutter 测试。构建与签名配置见 [构建指南](docs/mobile-builds.zh-CN.md)。

涉及设备功能时，准备 OpenClash、Nikki 或兼容 Mihomo API 的控制器；配置管理还需 SSH/SFTP。测试请使用可恢复的配置，勿提交真实凭据、私钥、个人配置或构建产物。

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
```

改动打包脚本时，运行 `python3 -m unittest discover -s scripts -p 'test_*.py'`。改动 WebView 时，按[构建指南](docs/mobile-builds.zh-CN.md#ios-构建)单独运行原生冒烟测试，并在真机上核对实际手势和路由器连接。

## 代码结构

| 路径 | 职责 |
| --- | --- |
| `lib/pages/` | 原生页面与 WebView 容器 |
| `lib/services/` | 控制器 API、软件适配、SSH/SFTP、存储和更新 |
| `lib/widgets/` | 共用组件与首页卡片 |
| `lib/theme/` | 明暗主题与组件样式 |
| `lib/l10n/` | 语言设置和界面翻译 |
| `assets/web_panel/` | 上游 Zashboard 发行资源，保留原样 |
| `android/`、`ios/` | 原生工程 |
| `test/`、`integration_test/` | 单元、Widget 和原生集成测试 |
| `scripts/` | 打包、签名准备及产物校验 |

原生页面通过共享数据层获取状态，Web 面板通过本地服务桥接控制器 API；OpenClash 和 Nikki 的 SSH 管理由各自适配器处理。新增功能应复用现有连接状态、存储及重启流程。弹窗遵循 [交互规范](docs/popup-interactions.zh-CN.md)，面板修改遵循 [Zashboard 维护说明](docs/bundled-zashboard.md#资源维护)。

### 新代码归属

| 路径 | 职责 |
| --- | --- |
| `lib/features/<feature>/` | 按功能存放页面、专用组件、状态和逻辑，例如 `yaml_config`、`web_panel`、`dashboard` 和 `app_update`。YAML 编辑器专用组件放在 `lib/features/yaml_config/`。 |
| `lib/core/<capability>/` | 存放跨功能使用的控制器 API、SSH/SFTP、代理后端适配及重启协调。共享的 SSH/SFTP 能力放在 `lib/core/ssh/`。 |
| `lib/widgets/`、`lib/theme/`、`lib/l10n/` | 分别存放通用界面组件、主题和本地化。 |
| `test/features/`、`test/core/` | 新增测试按被测模块归属，与源码目录对应，例如 `test/features/yaml_config/` 和 `test/core/ssh/`。 |

- 功能目录从少量文件开始。职责可以独立修改和验证时再拆分，例如 YAML 编辑器的文档度量、绘制和工具栏。
- 跨功能调用使用明确的页面入口或服务接口。公共服务通过界面提供的回调请求用户确认，例如 SSH 信任确认。页面从主题层读取主题状态，应用入口负责组装。
- 公共类型按实际能力命名，例如代理重启协调器。OpenClash 和 Nikki 各自的命令、配置和行为使用对应后端的名称。
- 随日常改动逐批迁移实际涉及且归属明确的文件。每批同步更新调用和相关测试，保持现有行为。

## 代码与合并请求

一个 PR 聚焦一个问题，说明目的、用户可见变化及实际测试结果；未覆盖的平台或真机行为也需写明。涉及安全问题时使用 [私密报告渠道](SECURITY.md)。

源码注释只用英文，解释必要的设计原因、安全边界或兼容约束，不重复代码，不混用中英文。界面文本和本地化内容不受此限制。Git 提交与推送说明使用英文，准确描述变更。

## 文档与仓库语言

- 文档、问题表单和 PR 默认使用简体中文，也欢迎英文交流。公开文档同步维护完整英文版，页首互链，英文页优先链接英文文档。
- 按读者需要组织内容：README 介绍与上手，使用指南说明操作和限制，构建指南集中记录环境与命令。避免重复步骤、界面微调记录和一次性任务报告。
- 命令、路径、API 字段、包名和校验值保持原样。更新功能或限制时同时更新两种语言及相关链接。
- 许可证、上游版权和第三方声明保留原文；译本用于阅读，不替代原许可。
- 工作流提示和讨论表单采用中文在前的双语文本。修改讨论分类后，同步核对 `.github/DISCUSSION_TEMPLATE/<slug>.yml`，文件名须匹配 GitHub 分类的 URL 标识；投票分类不支持表单。
