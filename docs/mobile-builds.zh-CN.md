# Android 与 iOS 构建指南

**简体中文** · [English](mobile-builds.en.md) · [文档目录](README.md)

双端使用 `.flutter-version` 固定的 Flutter 版本，应用版本和构建号取自 `pubspec.yaml`。依赖由 `pubspec.lock` 和 `ios/Podfile.lock` 固定。开发检查见 [贡献指南](../CONTRIBUTING.md)。

## GitHub Actions

在具有运行权限的仓库中，打开 **Actions → Proxly 双端打包 / Mobile builds → Run workflow**。页面上的工作流分支决定工作流定义，表单中的 `ref` 决定实际构建的源码。

| 参数 | 用途 |
| --- | --- |
| `ref` | 要构建的可信分支、标签或完整提交 SHA；发布构建使用完整 SHA |
| `platform` | `both`、`android` 或 `ios` |
| `android_build_type` | `release` 使用正式签名，`unsigned` 生成供本地签名的正式构建，`debug` 使用独立包名 `top.canmoqiu.proxly.debug` |
| `draft_release_tag` | 可选的私有测试草稿交付，见下文；默认留空 |

也可在该仓库根目录执行以下命令。将 `COMMIT_SHA` 替换为完整提交 SHA，并选择包含工作流定义的分支。

```sh
gh workflow run mobile-builds.yml --ref main -f ref=COMMIT_SHA -f platform=both -f android_build_type=release
gh run list --workflow mobile-builds.yml --limit 5
```

工作流由维护者手动触发。使用可信的 `ref`，因为构建会执行该提交中的脚本。双端用同一个完整 SHA。使用常规 Artifact 交付时，在下载并核验产物后再更新 Release 草稿。Android 使用 `unsigned` 时，留空 `draft_release_tag`。

### 下载产物

任务完成后，从对应运行页面下载 Artifact：

| 产物 | 内容 |
| --- | --- |
| `proxly-android-release-<序号>` | 正式签名 APK、SHA-256、`build-info-android.json` |
| `proxly-android-unsigned-<序号>` | `app-release-unsigned.apk`、SHA-256、`commit.txt` |
| `proxly-android-debug-<序号>` | 独立调试 APK、摘要及构建信息 |
| `proxly-ios-unsigned-<序号>` | IPA、SHA-256、`build-info-ios.json` |
| `android-build-logs-*` / `ios-build-logs-*` | 分析、测试和编译日志 |

Artifact 保留 14 天。CLI 下载时使用运行页面的 `RUN_ID`。若 Android 构建选了 `unsigned`，使用 `proxly-android-unsigned-*` 匹配产物。

```sh
gh run download RUN_ID -p 'proxly-android-release-*' -p 'proxly-ios-unsigned-*' -D dist
```

### 私有测试草稿交付

Artifact 存储不足时，可在私有仓库预先创建同版本的预发布草稿，目标设为完整源码 SHA，再填写 `draft_release_tag`。此模式只支持测试版本。

工作流在构建前和上传前核对仓库可见性、版本、草稿状态和目标 SHA，只上传 APK / IPA，不覆盖同名附件，不发布草稿；日志从 Actions 页面查看。已有一端上传成功时，只重试另一端。工作流为此声明 `contents: write` 权限。

## Android 签名与本地构建

Actions 的 `release` 模式使用以下 Secrets 和仓库变量 `ANDROID_CERT_SHA256`。

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

签署 Actions 的待签包前，先核对 `commit.txt` 和待签 APK 的 SHA-256。使用 Android SDK Build Tools 按顺序对齐、签名和验证。示例中的 `KEYSTORE`、`KEY_ALIAS` 和 `VERSION` 分别替换为发布密钥库路径、别名和展示版本，按工具提示输入密码。参见 [zipalign](https://developer.android.com/tools/zipalign?hl=zh-cn) 和 [apksigner](https://developer.android.com/tools/apksigner?hl=zh-cn)。

```sh
zipalign -P 16 4 app-release-unsigned.apk app-release-aligned.apk
apksigner sign --ks KEYSTORE --ks-key-alias KEY_ALIAS --out Proxly-Android-VERSION.apk app-release-aligned.apk
zipalign -c -P 16 4 Proxly-Android-VERSION.apk
apksigner verify --verbose --print-certs Proxly-Android-VERSION.apk
```

签名后重新计算最终 APK 的 SHA-256，核对证书、包名、版本及 ARM64、x86_64 两套构建资源。

官方发布证书 SHA-256 为 `938c46e51d9149a2cec9f3af7efc4da730894e9e1ec192b982c55a22fbb1c6d8`。26.5 使用不同的 Debug 证书，升级前需安全记录设置、卸载旧版后再安装；之后同签名版本可覆盖更新。自行签名的包不能覆盖官方包。

## iOS 构建

原生编译需要 macOS、Xcode 和 CocoaPods。Actions 安装固定版本的 Flutter 工具链，运行静态检查和常规测试，然后生成设备 Release 包。构建后会核对 `ios/Podfile.lock`。如需验证模拟器中的 WebView，可在已启动的 iPhone 模拟器上单独运行 `flutter test integration_test/web_panel_smoke_test.dart -d <设备 ID>`。安装步骤见 [iOS 安装指南](ios-selfsign.zh-CN.md)。

## 发布前核验

- 两端构建和适用测试成功；真机检查连接、代理切换、配置操作、后台恢复及覆盖更新。
- 核对两端构建信息或 `commit.txt` 中的源码 SHA，以及包内版本和构建号。
- 核对最终 APK 的证书和双架构完整性、IPA 的设备支持，以及两个安装包的 SHA-256。Android 使用本地签名时，以签名后的 APK 为准。
- 发布前在 Release 中选定指向同一源码提交的纯版本标签，例如 `v26.11.2`。测试版标识写在标题和正文中。附件仅包含最终 APK 和 IPA，双端摘要写入中英文发布正文。

正式版安装包名如 `Proxly-Android-26.10.apk`、`Proxly-iOS-26.10.ipa`；测试版保留第三段版本号。文件名和发布正文不展示内部构建号。仅在引入兼容性、签名或迁移变化的版本中说明相关影响。
