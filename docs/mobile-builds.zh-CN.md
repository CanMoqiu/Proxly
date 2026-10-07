# Android 与 iOS 同步开发、构建和发布

两端共享 `main` 分支、Flutter 3.47.5、依赖锁文件及 `pubspec.yaml` 版本号。平台差异通过能力判断处理。修改共享代码时运行 `flutter analyze` 与 `flutter test`，发布前同时验证 Android Release 和 iOS Release。

在 **Actions → Proxly Android and iOS builds → Run workflow** 选择：

- `ref`：可信的分支、标签或完整提交 SHA，正式发布使用主分支完整 SHA。
- `platform`：`both` 同时构建两端；`android` 或 `ios` 只构建对应平台。
- `android_build_type`：默认 `release` 使用固定正式签名；`debug` 生成独立 `.debug` 包名的测试包。

```powershell
gh workflow run mobile-builds.yml --ref main -f ref=main -f platform=both -f android_build_type=release
```

工作流只有仓库读取权限，不自动发布 Release。产物保留 14 天：`proxly-android-release-<序号>` 与 `proxly-ios-unsigned-<序号>`，各含安装包、SHA-256 和平台构建信息。正式安装包名为 `Proxly-Android-26.6.apk` / `Proxly-iOS-26.6.ipa`；测试版本保留第三位版本号，文件名均不含内部构建号。失败日志保存在 `android-build-logs-*` / `ios-build-logs-*`。

## Android 正式签名

GitHub Actions 使用仓库 Secrets：

- `ANDROID_KEYSTORE_BASE64`：PKCS#12 密钥文件的 Base64 内容。
- `ANDROID_KEYSTORE_PASSWORD`：密钥库密码。
- `ANDROID_KEY_PASSWORD`：私钥密码。
- `ANDROID_KEY_ALIAS`：别名。

仓库变量 `ANDROID_CERT_SHA256` 固定发布证书的 SHA-256，打包时校验，防止误用 Debug 或其他密钥。密钥仅在构建期间恢复到 runner 临时目录，随后清除，不上传到日志、缓存或发布附件。

本地构建使用未跟踪的 `android/key.properties`，字段为 `storeFile`（绝对路径）、`storeType=PKCS12`、`storePassword`、`keyAlias` 和 `keyPassword`。不要提交私钥或密码；单独保留安全备份，后续版本使用同一签名。

```powershell
flutter build apk --release
```

从 26.6.0+35 起，发布证书 SHA-256 为 `938c46e51d9149a2cec9f3af7efc4da730894e9e1ec192b982c55a22fbb1c6d8`。旧 26.5 使用的 Debug 证书与此不同，无法直接覆盖；迁移步骤见 [26.6 发布说明](releases/26.6.0.md)。

## iOS 自签安装

iOS 18+ iPhone 使用 Release 未签名 IPA，不需要在仓库提供 Apple 证书。构建、安装与覆盖升级见 [iOS 使用说明](ios-selfsign.zh-CN.md)。

## 发布

合并变更到主分支，以其完整 SHA 手动运行双端构建。确认两个任务均成功，核对包内版本、源码 SHA、安卓签名和文件校验值后，再将标签指向该提交并上传安装包及构建信息。Release 说明应区分 Android 已签名 APK 与 iOS 待自签 IPA，保留影响覆盖升级的签名说明。
