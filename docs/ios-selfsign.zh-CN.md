# iPhone 个人自签版本

本版本支持 iOS 18.0 及更新系统的 iPhone，使用竖屏界面。继续管理用户自己的 Clash/Mihomo/OpenClash 控制器；手机不运行代理内核。应用与 Android 共用启动更新提醒及关于页检测开关，点击更新后在 GitHub 发布页下载 IPA 并重新签名安装，Zashboard 面板仍可在应用内单独更新。

## Windows 开发

使用 `.flutter-version` 固定的 Flutter **3.47.5**。安装该版本后，在项目根目录运行：

```powershell
flutter config --no-analytics --no-enable-swift-package-manager
flutter pub get
flutter analyze
flutter test
```

Windows 可修改代码、运行 Dart/Widget 测试；iOS 原生编译由 GitHub Actions 的 macOS 26 + Xcode 26.6 完成。工程通过 CocoaPods 集成插件。`pubspec.lock` 和经过 Mac 构建验证的 `ios/Podfile.lock` 随源码提交，固定 Dart 和原生依赖；CI 会检查原生锁文件是否发生意外变化。

## 手动打包

1. Android 与 iOS 已在 `main` 同步开发，默认分支提供 `mobile-builds.yml` 手动工作流。
2. 在 GitHub 的 **Actions → Proxly Android and iOS builds → Run workflow** 中，`ref` 填写要构建的分支、标签或完整提交 SHA，`platform` 选择 `ios`。
3. 等待 iPhone 模拟器 WebView 集成测试和 iOS 构建完成。任务不会因为普通推送自动运行。`platform=both` 同时构建 Android，`platform=android` 只构建 Android；正式发布选择 `android_build_type=release`。
4. 下载 `proxly-ios-unsigned-<运行序号>` Artifact，解压得到 `.ipa`、`.ipa.sha256` 和 `build-info-ios.json`。

也可以通过 GitHub CLI 发起，例如：

```powershell
gh workflow run mobile-builds.yml --ref main -f ref=main -f platform=ios
gh run list --workflow mobile-builds.yml --limit 5
gh run download <运行编号> -n proxly-ios-unsigned-<运行序号> -D .\dist\ios
```

同时构建 APK 和 IPA 时使用 `-f platform=both -f android_build_type=release`。Android 产物为 `proxly-android-release-<运行序号>`，包含已签名 APK、SHA-256 和构建信息。需要独立测试包时选择 `android_build_type=debug`，其包名为 `top.canmoqiu.proxly.debug`，可与正式版并存，配置独立保存。签名配置和旧版迁移步骤见 [双端构建说明](mobile-builds.zh-CN.md)。

运行编号（run ID）与运行序号（run number）不同，可在 Actions 页面或 `gh run view` 中确认。Artifact 保留 14 天。公开仓库的 Actions 额度与并发限制以 GitHub 当前政策为准；额度或并发不足时先处理 GitHub 的构建限制，工作流不会修改计费或仓库可见性。

工作流只需要仓库读取权限，不需要 Apple 账号、证书或描述文件，也不发布 Release。输入的 `ref` 应是你信任的代码，因为构建会执行该版本的脚本。

## 自签与覆盖更新

1. 使用 PowerShell `Get-FileHash -Algorithm SHA256 <IPA路径>`，与 `.ipa.sha256` 中的摘要核对。
2. 将 **Release 未签名 IPA** 导入你现有的自签工具，按工具要求签名安装。IPA 不能跳过签名直接安装。
3. 工程 Bundle ID 为 `top.canmoqiu.proxly`。更新和续签时保持实际 Bundle ID、签名身份和 Keychain 访问配置一致，使用覆盖安装；变更这些信息或卸载可能影响本地配置和凭据访问。
4. 按签名工具和 iOS 提示完成信任/开发者模式设置。证书有效期和续签由你的签名方式决定。

首次连接时允许 **局域网** 权限。手机应能访问路由器地址和 Clash external-controller 端口。若拒绝过授权，到系统设置的 Proxly 页面重新允许，然后返回应用重试连接。SSH 使用已有的端口 22 和主机指纹确认流程。

YAML 文件读写需要路由器提供 SFTP。OpenWrt 上如果能列出文件却不能打开，请检查是否安装并启用了 `openssh-sftp-server`；目录列表使用 SSH 命令，能列出文件不代表 SFTP 可用。

凭据存放在仅本机、解锁时可访问的 Keychain 中，不同步到 iCloud。暂时无法读取时应用保留配置并提供重试，不自动清空凭据。

## 面板更新与恢复

Zashboard 更新仍执行摘要、大小和归档路径检查。iOS 安装完成后会重建所有已打开面板的本地服务和 WebView，无需退出应用。若安装成功但激活失败，再次点击更新可重试激活，不重新下载；也可在加载失败页点击重试。

返回前台时重新建立需要恢复的面板连接，原生页面恢复轮询。应用不承诺后台持续监控。已有的远程重启或上传操作可能在进入后台前已经送达路由器；恢复后应检查实际状态，避免盲目重复执行。

## 真机验收清单

- [ ] 自签安装后可启动，图标、启动页和竖屏安全区域正常。
- [ ] 局域网权限允许、拒绝、重新开启后分别显示合理结果并能重试。
- [ ] 正确/错误的控制器地址及密钥都能得到可理解的反馈。
- [ ] 首页流量、代理切换、原生/Web 两种连接列表和独立控制台正常。
- [ ] SSH 首次确认与指纹变更提示、OpenClash 快捷设置正常。
- [ ] YAML 可从“文件”及可用的 iCloud 文件位置导入，编辑后导出并重新打开；中文输入、选区和键盘无遮挡。
- [ ] Zashboard 更新后版本变化，三个面板重新加载，偏好仍保留；失败可重试。
- [ ] 锁屏、长时间后台、断网、切换 Wi-Fi 后回到应用能够恢复。
- [ ] 同一签名身份与 Bundle ID 覆盖安装后，配置和凭据仍可读取。

构建成功不等于真机验收通过。模拟器验证本地 HTTP/WebSocket、WKWebView、Keychain 和导航恢复，不代替实际路由器及 iOS 27 真机测试。反馈问题时请提供机型、iOS 版本、自签工具、`build-info-ios.json` 中的提交 SHA、操作步骤与截图。不要包含控制器密钥、SSH 密码或签名证书。构建失败时查看 `ios-build-logs-*` 或 `android-build-logs-*` Artifact。

更新检测通过公开的 GitHub Releases 获取版本信息。应用可直接读取公开版本；iOS 用户点击更新后仍需下载 IPA 并使用自己的签名方式安装。
