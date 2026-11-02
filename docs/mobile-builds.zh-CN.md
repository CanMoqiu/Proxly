# Android 与 iOS 同步开发、构建和发布

**简体中文** · [English](mobile-builds.en.md) · [文档目录](README.md)

两端共享 `main` 分支、Flutter 3.47.5、依赖锁文件及 `pubspec.yaml` 版本号。平台差异通过能力判断处理。修改共享代码时运行 `flutter analyze` 与 `flutter test`，发布前同时验证 Android Release 和 iOS Release。

## 手动构建

正式安装包请从 [发布页](https://github.com/CanMoqiu/Proxly/releases) 下载。若自行构建，请在有工作流运行权限、能够配置签名的仓库副本中操作。以下命令从该副本的根目录执行，GitHub CLI 使用当前仓库上下文；不要求读者具有上游公开仓库的打包权限。

在 **工作流（Actions）→ Proxly 双端打包 / Mobile builds → 运行工作流（Run workflow）** 选择：

- `ref`：可信的分支、标签或完整提交 SHA，正式发布使用主分支完整 SHA。
- `platform`：`both` 同时构建两端；`android` 或 `ios` 只构建对应平台。
- `android_build_type`：默认 `release` 使用固定正式签名；`debug` 生成独立 `.debug` 包名的测试包。

```powershell
gh workflow run mobile-builds.yml --ref main -f ref=main -f platform=both -f android_build_type=release
gh run list --workflow mobile-builds.yml --limit 5
```

该工作流仅手动触发，默认以 Artifact 交付。为支持私有草稿附件上传，工作流声明仓库内容写入权限，但不会自动创建或发布 Release。产物保留 14 天：`proxly-android-release-<序号>` 与 `proxly-ios-unsigned-<序号>`，各含安装包、SHA-256 和平台构建信息。正式安装包名为 `Proxly-Android-26.8.apk` / `Proxly-iOS-26.8.ipa`；测试版本保留第三位版本号，文件名均不含内部构建号。失败日志保存在 `android-build-logs-*` / `ios-build-logs-*`。

构建类型与版本渠道是两个概念：`debug` 选择调试签名和独立包名，不会自动把版本改为测试版；双端版本均取自 `pubspec.yaml`。

## 私有草稿交付（可选）

Actions 存储配额不足时，可先在私有仓库创建同版本的预发布草稿，目标指定待构建的完整提交 SHA，再填写 `draft_release_tag`（例如 `v26.8.1`）。留空时仍使用 Artifact。工作流在构建前及上传前核对仓库为私有、版本为测试版、草稿标签与源码版本一致、目标 SHA 一致；不覆盖同名附件，不发布草稿，不删除历史产物。仅 APK 和 IPA 作为草稿附件上传；该模式不使用 Artifact 保存日志，可查看 Actions 原生日志。已上传一端后，只重试失败的另一端，避免同名附件冲突。

## Android 正式签名

GitHub Actions 使用仓库 Secrets：

- `ANDROID_KEYSTORE_BASE64`：PKCS#12 密钥文件的 Base64 内容。
- `ANDROID_KEYSTORE_PASSWORD`：密钥库密码。
- `ANDROID_KEY_PASSWORD`：私钥密码。
- `ANDROID_KEY_ALIAS`：别名。

仓库变量 `ANDROID_CERT_SHA256` 固定发布证书的 SHA-256，打包时校验，防止误用 Debug 或其他密钥。密钥仅在构建期间恢复到 runner 临时目录，随后清除，不上传到日志、缓存或发布附件。

本地构建使用未跟踪的 `android/key.properties`，字段为 `storeFile`（绝对路径）、`storeType=PKCS12`、`storePassword`、`keyAlias` 和 `keyPassword`。不要提交私钥或密码；单独保留安全备份，后续版本使用同一签名。

```powershell
flutter build apk --release --target-platform android-arm64,android-x64
```

从 26.6.0+35 起，发布证书 SHA-256 为 `938c46e51d9149a2cec9f3af7efc4da730894e9e1ec192b982c55a22fbb1c6d8`。旧 26.5 使用的 Debug 证书与此不同，无法直接覆盖；升级前请先安全记录连接信息及所需设置，再卸载旧版后安装；后续同签名版本可以覆盖更新。该摘要是公开核验信息，不是签名密钥；自行签名的包不能覆盖官方签名包。

## Android 架构支持

26.8 之后的 Android 构建仅支持 ARM64（`arm64-v8a`）和 x86_64，**后续版本不再支持 Android ARM32 位设备**，也不提供 32 位 x86 包。32 位系统（包括运行 32 位系统的 ARM64 处理器）请继续使用 26.8。两个受支持架构仍包含在同一个 APK 中，包名与签名保持不变。打包脚本会检查两个架构的原生库均完整，并拒绝混入 ARM32。

## 使用后的存储占用

首页启动时不预先创建代理和连接页的 WebView；首次进入对应标签时才初始化，之后保留页面状态。隐藏标签暂停 Flutter 动画；原生连接列表仅在标签可见、未被其他页面覆盖且应用位于前台时轮询，返回后重新获取数据，避免隐藏页面持续请求和刷新。

Android 冷启动时仅清理已安装版本及更旧版本的应用内更新 APK，以及没有版本记录的下载残留；较新、尚未安装的 APK 保留用于重试，不在唤起安装器后立即删除。清理失败不会阻止启动。

本地面板资源使用 `Cache-Control: no-store`，避免随机本地端口产生重复 HTTP 缓存。Android 与 iOS 在首次启动、应用版本变化或距上次成功清理满 7 天时清理旧 WebView HTTP 缓存；不会清除 Cookie、网页存储、面板偏好、连接凭据、当前安装的面板或用户 YAML 文件。内置与下载面板继续从本地资源目录加载，不依赖公网重新下载。iOS 仅清理 WKWebView 的内存和磁盘 HTTP 缓存，保留 Fetch 缓存、离线数据及 IndexedDB；不会清空应用沙盒。

## iOS 自签安装

iOS 18+ iPhone 使用 Release 未签名 IPA，不需要在仓库提供 Apple 证书。构建、安装与覆盖升级见 [iOS 使用说明](ios-selfsign.zh-CN.md)。

## 发布

选定已验证的源码提交，以完整 SHA 手动运行双端构建。确认两个任务均成功，核对包内版本、源码 SHA、Android 签名和文件校验值，再发布对应的正式源码、标签和已验证安装包。构建诊断保留用于追溯；发布正文提供必要的版本信息及安装包摘要，不包含内部仓库信息或凭据。

发布说明默认使用中文，并提供完整英文版本。应区分 Android 已签名 APK 与 iOS 待自签 IPA，保留影响覆盖升级的签名说明。

首次包含架构调整的发布说明须在“重要说明”中明确写出“不再支持 Android ARM32 位设备，支持 ARM64 与 x86_64”，并提示 32 位设备继续使用 26.8。版本信息的支持平台项固定为“Android 7.0+；iOS 18+”，不添加括号内容。
