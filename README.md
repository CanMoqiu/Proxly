<div align="center">
  <img src="proxly-icon.png" width="96" alt="Proxly 图标" />
  <h1>Proxly</h1>
  <p><strong>Android / iOS 软路由代理管理客户端</strong></p>
  <p>查看运行状态、切换代理与规则、管理连接和 YAML 配置。</p>

  [![最新正式版](https://img.shields.io/github/v/release/CanMoqiu/proxly?label=正式版)](https://github.com/CanMoqiu/proxly/releases/latest)
  [![支持平台](https://img.shields.io/badge/平台-Android%20%26%20iOS-3DDC84?logo=android&logoColor=white)](#兼容要求)
  [![许可证](https://img.shields.io/github/license/CanMoqiu/proxly)](LICENSE)

  [下载安装](https://github.com/CanMoqiu/proxly/releases) · [使用文档](docs/README.md) · [English](README.en.md)
</div>

Proxly 连接你自行部署的 OpenClash、Nikki 或兼容 Clash/Mihomo API 的控制器，通过原生界面、内置 Zashboard 和 SSH/SFTP 管理代理设备。应用不包含代理内核，不提供节点、订阅或流量转发。

## 开始使用

1. 从 [Releases](https://github.com/CanMoqiu/proxly/releases) 下载安装包。iPhone 和 iPad 的安装步骤见 [iOS 安装指南](docs/ios-selfsign.zh-CN.md)。
2. 填写控制器地址和密钥；需要配置管理功能时，再填写 SSH 密码及端口（默认 `22`）。
3. 点击“下一步”，应用识别代理软件并在偏好页预选。无法识别时使用“Mihomo 通用配置”，也可手动选择。完成偏好设置后进入首页。

之后可在设置中修改连接信息，在高级选项中修改代理软件、语言和连接页显示方式。详细操作见 [使用指南](docs/dashboard.zh-CN.md)。

## 功能

| 功能 | 说明 |
| --- | --- |
| 首页 | 运行状态、软件与内核版本、实时流量、连接概览和订阅用量；卡片可排序、隐藏 |
| 代理与规则 | 内置 Zashboard，支持节点和代理组切换、规则查看及独立控制台 |
| 连接 | 可选原生列表或 Web 面板；Web 连接页在手机和平板上均使用卡片，内容自定义自动保存 |
| 快捷设置 | 按软件支持范围调整代理模式、DNS、流量接管、区域绕过等选项 |
| 配置管理 | 切换、编辑、上传、重命名、导出和删除受支持的 YAML 文件 |
| 维护与更新 | 重启代理服务、清理 DNS 缓存、关闭连接，以及应用和面板更新 |
| 界面 | 简体中文、英语，跟随系统、浅色和深色主题；支持平板横竖屏 |

OpenClash 和 Nikki 提供专用适配，其他兼容控制器使用 Mihomo 通用配置。通用配置提供控制器 API 功能，不提供 SSH 配置管理和服务重启。不适用的功能自动隐藏，首页布局偏好保留。各软件差异见 [适配范围](docs/dashboard.zh-CN.md#适配范围)。

## 兼容要求

- **Android 7.0+**：仅支持 ARM64 和 x86_64，32 位安卓系统请使用 26.8。
- **iOS 18+**：支持 iPhone 和 iPad。
- **控制器**：需启用 `external-controller`，使用设备可访问的局域网 IP 或主机名，默认端口为 `9090`。若设置了 `secret`，请在应用中填写相同的密钥。
- **SSH/SFTP**：OpenClash 和 Nikki 的配置管理及服务重启需要通过 `root` 账号连接 SSH；YAML 文件读写还需启用 SFTP。

连接凭据和 SSH 主机指纹保存在系统安全存储中。首次 SSH 连接或指纹变化时需确认；YAML 操作仅限受支持的目录和文件大小，导入配置与更新包通过校验后才会使用。

## 文档与参与

- [使用指南](docs/dashboard.zh-CN.md)：连接设置、首页、软件适配、YAML 管理与故障处理。
- [Zashboard](docs/bundled-zashboard.md)：面板布局、配置导入和资源维护。
- [构建指南](docs/mobile-builds.zh-CN.md)：双端打包、Android 签名和产物核验。
- [贡献指南](CONTRIBUTING.md)：开发环境、目录结构、代码与文档约定。
- [问题反馈与功能建议](https://github.com/CanMoqiu/Proxly/issues/new/choose)。安全漏洞请使用 [私密报告渠道](SECURITY.md)。

## 技术与致谢

使用 [Flutter](https://flutter.dev/)、[Zashboard](https://github.com/Zephyruso/zashboard)、[flutter_inappwebview](https://github.com/pichillilorenzo/flutter_inappwebview)、[dartssh2](https://github.com/TerminalStudio/dartssh2) 和 [Re-Editor](https://pub.dev/packages/re_editor) 等开源项目。完整依赖见 [pubspec.yaml](pubspec.yaml)，许可证与第三方声明见 [文档目录](docs/README.md#许可证)。

## 法律与服务边界

Proxly 是公开源代码的 Android / iOS 客户端，仅用于管理用户自行部署并有权访问的 OpenClash / Mihomo 环境。项目维护者不提供代理节点、订阅、账号、线路、带宽、VPN、国际联网信道、流量转发、托管运行、远程代配置或其他持续性软件服务，也不参与用户网络环境的建设、运营或数据传输。

本项目不以提供、促成或协助所谓“翻墙”服务为目的，不得用于突破、绕过或规避中华人民共和国依法实施的网络访问管理措施。任何人在中华人民共和国境内使用本项目，均应遵守现行法律法规，通过合法的网络接入和国际联网信道使用网络，不得用于未经许可的电信业务、非法国际联网、危害网络安全、侵犯他人合法权益或其他违法活动。

用户自行决定是否使用本项目，并自行负责其设备、配置、网络接入方式、数据处理及由此产生的行为和后果。[MIT 许可证](LICENSE.zh-CN.md) 中的免责声明继续适用；本声明不排除依法不能免除的责任。

相关官方法律文本：

- [《中华人民共和国计算机信息网络国际联网管理暂行规定》](https://xzfg.moj.gov.cn/front/law/detail?LawID=1713&Query=)，包括第六条、第八条和第十条有关国际联网信道、经营活动和接入方式的规定。
- [《中华人民共和国电信条例》](https://www.samr.gov.cn/zw/zfxxgk/fdzdgknr/bgt/art/2023/art_cb96d9e9147740f79f4c111bb637ce29.html)，包括电信业务许可、国际通信、网络与信息安全相关规定。
- [《中华人民共和国网络安全法》](https://www.cac.gov.cn/2025-12/29/c_1768735112911946.htm)，采用自 2026 年 1 月 1 日施行的修正文本。

上述链接用于指向公开的官方法律文本，不构成针对具体使用情形的法律意见。

## 关联关系与许可证

Proxly 是独立开源项目，与 Clash、OpenClash、Mihomo、Zashboard 及相关服务提供方不存在官方隶属、授权或担保关系。

项目源代码依据 [MIT 许可证](LICENSE.zh-CN.md) 发布，Copyright (c) 2026 CanMoqiu。
