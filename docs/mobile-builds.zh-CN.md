# Android 与 iOS 构建指南

**简体中文** · [English](mobile-builds.en.md) · [文档目录](README.md)

双端使用 Flutter 3.47.5，版本取自 `pubspec.yaml`，依赖由 `pubspec.lock` 和 `ios/Podfile.lock` 固定。Android 支持 ARM64、x86_64；iOS 支持 iOS 18+ 的 iPhone 和 iPad。开发检查见 [贡献指南](../CONTRIBUTING.md)。

## GitHub Actions

在具有运行权限、可配置签名的仓库副本中，打开 **Actions → Proxly 双端打包 / Mobile builds → Run workflow**：

| 参数 | 用途 |
| --- | --- |
| `ref` | 要构建的可信分支、标签或完整提交 SHA；发布构建使用完整 SHA |
| `platform` | `both`、`android` 或 `ios` |
| `android_build_type` | `release` 使用正式签名；`debug` 使用独立包名 `top.canmoqiu.proxly.debug`，与正式包配置隔离 |
| `draft_release_tag` | 可选的私有测试草稿交付，见下文；默认留空 |

也可在该仓库根目录执行以下命令，将 `COMMIT_SHA` 替换为完整提交 SHA：

```sh
gh workflow run mobile-builds.yml --ref main -f ref=COMMIT_SHA -f platform=both -f android_build_type=release
gh run list --workflow mobile-builds.yml --limit 5
```

工作流仅手动触发，不自动发布 Release。构建执行所选 `ref` 的脚本，应使用可信代码。`debug` 只改变构建类型和包名，不改变版本渠道。

### 下载产物

任务完成后，从对应运行页面下载 Artifact：

| 产物 | 内容 |
| --- | --- |
| `proxly-android-release-<序号>` | 正式签名 APK、SHA-256、`build-info-android.json` |
| `proxly-android-debug-<序号>` | 独立调试 APK、摘要及构建信息 |
| `proxly-ios-unsigned-<序号>` | IPA、SHA-256、`build-info-ios.json` |
| `android-build-logs-*` / `ios-build-logs-*` | 分析、测试和编译日志 |

Artifact 保留 14 天。CLI 下载示例中的 `RUN_ID` 为运行页面的 ID，不是 Artifact 名称中的运行序号：

```sh
gh run download RUN_ID -p 'proxly-android-release-*' -p 'proxly-ios-unsigned-*' -D dist
```

### 私有测试草稿交付

Artifact 存储不足时，可在私有仓库预先创建同版本的预发布草稿，目标设为完整源码 SHA，再填写 `draft_release_tag`。此模式只支持测试版本。

工作流在构建前和上传前核对仓库可见性、版本、草稿状态和目标 SHA，只上传 APK / IPA，不覆盖同名附件，不发布草稿；日志从 Actions 页面查看。已有一端上传成功时，只重试另一端。工作流为此声明 `contents: write` 权限。

## Android 签名与本地构建

Actions 需要以下 Secrets，以及仓库变量 `ANDROID_CERT_SHA256`：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | PKCS#12 密钥库的 Base64 内容 |
| `ANDROID_KEYSTORE_PASSWORD` | 密钥库密码 |
| `ANDROID_KEY_PASSWORD` | 私钥密码 |
| `ANDROID_KEY_ALIAS` | 密钥别名 |

打包时校验证书摘要，密钥在 runner 临时目录恢复并在结束后清除。不要将密钥或密码写入日志、缓存和附件。

本地使用未跟踪的 `android/key.properties`，填写 `storeFile`（绝对路径）、`storeType=PKCS12`、`storePassword`、`keyAlias` 和 `keyPassword`：

```sh
flutter pub get --enforce-lockfile
flutter build apk --release --target-platform android-arm64,android-x64
```

两个架构打入同一 APK。32 位安卓系统请使用 26.8，包括运行 32 位系统的 ARM64 设备。

官方发布证书 SHA-256 为 `938c46e51d9149a2cec9f3af7efc4da730894e9e1ec192b982c55a22fbb1c6d8`。26.5 使用不同的 Debug 证书，升级前需安全记录设置、卸载旧版后再安装；之后同签名版本可覆盖更新。自行签名的包不能覆盖官方包。

## iOS 构建

原生编译需要 macOS、Xcode 和 CocoaPods。Actions 安装固定 Flutter 工具链、执行模拟器 WebView 集成测试并生成设备 Release 包；构建后检查 `ios/Podfile.lock` 未漂移。不要用模拟器产物代替设备包。安装步骤见 [iOS 安装指南](ios-selfsign.zh-CN.md)。

## 发布前核验

- 两端构建和适用测试成功；真机检查连接、代理切换、配置操作、后台恢复及覆盖更新。
- 构建信息中的源码 SHA 与选定提交一致，包内版本和构建号与 `pubspec.yaml` 一致。
- Android 证书和双架构完整性、iOS 设备支持及安装包摘要通过打包脚本检查。
- 发布源码、标签和安装包对应同一版本；仅上传安装包，摘要写入中英文发布正文。

正式版安装包名如 `Proxly-Android-26.10.apk`、`Proxly-iOS-26.10.ipa`；测试版保留第三段版本号。文件名和发布正文不展示内部构建号。仅在引入兼容性、签名或迁移变化的版本中说明相关影响。
