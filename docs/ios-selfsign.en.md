# iPhone self-signed version

[简体中文](ios-selfsign.zh-CN.md) · **English** · [Documentation](README.en.md)

This version supports iPhones running iOS 18.0 or later in portrait orientation. It manages your own Clash/Mihomo/OpenClash controller; the phone does not run a proxy core. The app shares startup update notices and the About-page update toggle with Android. For an app update, download the IPA from GitHub Releases and sign it again before installation. Zashboard can still update separately inside the app.

## Windows development

Use Flutter **3.47.5**, pinned in `.flutter-version`. After installing it, run from the repository root:

```powershell
flutter config --no-analytics --no-enable-swift-package-manager
flutter pub get --enforce-lockfile
flutter analyze
flutter test
```

Windows supports code changes and Dart/Widget tests. The manual GitHub Actions workflow compiles native iOS code on macOS 26 with Xcode 26.6. CocoaPods integrates plugins. The committed `pubspec.lock` and Mac-build-validated `ios/Podfile.lock` pin Dart and native dependencies; the build workflow detects unexpected native lockfile changes.

## Manual packaging

1. Android and iOS share `main`; `mobile-builds.yml` provides the manual workflow. For your own builds, use a copy where you have workflow permission; official packages are on [Releases](https://github.com/CanMoqiu/Proxly/releases).
2. Open **Actions → Proxly 双端打包 / Mobile builds → Run workflow**. Set `ref` to a trusted branch, tag, or full commit SHA and `platform` to `ios`.
3. Wait for the iPhone simulator WebView integration test and iOS build. Ordinary pushes do not trigger this workflow. `platform=both` also builds Android; `platform=android` builds only Android. Select `android_build_type=release` for production signing.
4. Download the `proxly-ios-unsigned-<run number>` artifact. Extract the `.ipa`, `.ipa.sha256`, and `build-info-ios.json`.

GitHub CLI can also dispatch the workflow. Run these commands in the checkout you intend to build:

```powershell
gh workflow run mobile-builds.yml --ref main -f ref=main -f platform=ios
gh run list --workflow mobile-builds.yml --limit 5
$runId = Read-Host 'Enter the completed run ID shown in the list'
gh run download $runId -p 'proxly-ios-unsigned-*' -D .\dist\ios
```

For both packages, use `-f platform=both -f android_build_type=release`. The Android artifact `proxly-android-release-<run number>` contains the signed APK, SHA-256, and build information. For a separate test installation, choose `android_build_type=debug`; its application ID is `top.canmoqiu.proxly.debug`, allowing coexistence with the production app and separate preferences. See the [mobile build guide](mobile-builds.en.md) for signing and migration.

The run ID differs from the run number; confirm them on the Actions page or with `gh run view`. Artifacts last 14 days. If GitHub quotas or concurrency limits prevent a build, resolve those account/repository limits first; this workflow does not change billing or repository visibility.

The workflow has repository read permission, requires no Apple account, certificate, or provisioning profile, and does not publish a Release. Build only a trusted `ref`, because its scripts will execute.

## Signing and in-place updates

1. Run PowerShell `Get-FileHash -Algorithm SHA256 <IPA path>` (replace the placeholder with the downloaded path). Compare against the `.ipa.sha256` file or the official release's published digest.
2. Import the **unsigned Release IPA** into your existing self-signing tool and follow its signing/installation procedure. An unsigned IPA cannot be installed directly.
3. The project Bundle ID is `top.canmoqiu.proxly`. Keep the actual Bundle ID, signing identity, and Keychain access configuration consistent for updates and renewal, and install over the existing app. Changing these or uninstalling may affect local settings and credential access.
4. Complete trust/developer-mode settings as requested by the signing tool and iOS. Certificate validity and renewal depend on your signing method.

Allow **Local Network** access on first connection. The phone must reach the router address and Clash external-controller port. If permission was previously denied, enable it in the Proxly system settings page and retry. SSH uses port 22 and the existing host-fingerprint confirmation flow.

YAML reads/writes require SFTP on the router. If files can be listed but not opened on OpenWrt, check that `openssh-sftp-server` is installed and enabled. Listing uses SSH commands, so a successful list does not prove SFTP works.

Credentials use device-only Keychain storage accessible while unlocked and do not sync to iCloud. Temporary read failures preserve settings and offer retry instead of automatically clearing credentials.

## Panel updates and recovery

Zashboard updates retain digest, size, and archive-path validation. After installation, iOS rebuilds the local services and WebViews for all open panels without exiting the app. If installation succeeds but activation fails, pressing update again retries activation without downloading again; the load-error page also offers retry.

Returning to the foreground restores panel connections as needed and resumes native polling. Continuous background monitoring is not promised. Remote restarts or uploads may already have reached the router before backgrounding; check the actual state on return before repeating an operation.

## Physical-device acceptance checklist

- [ ] The self-signed app starts; icon, launch screen, portrait safe areas work.
- [ ] Allowing, denying, and re-enabling Local Network permission give understandable results and support retry.
- [ ] Valid and invalid controller addresses and secrets give actionable feedback.
- [ ] Home traffic, proxy switching, native/web connection lists, and standalone console work.
- [ ] Initial/changed SSH fingerprint confirmations and OpenClash quick settings work.
- [ ] YAML imports from Files and available iCloud locations, exports after editing, and reopens; Chinese input, selections, and keyboard remain usable.
- [ ] Zashboard version changes after updating, all three panels reload, preferences remain, and failure supports retry.
- [ ] Recovery works after locking, a long background interval, losing network, and switching Wi-Fi.
- [ ] In-place installation using the same signing identity and Bundle ID preserves settings and credential access.

A successful build does not prove physical-device acceptance. The simulator checks local HTTP/WebSocket, WKWebView, Keychain, and navigation recovery; it cannot replace a real router and supported iPhone testing. Reports should include device model, iOS version, signing tool, source SHA from `build-info-ios.json` when available, steps, and screenshots. Do not include controller secrets, SSH passwords, or signing certificates. For build failures, inspect `ios-build-logs-*` or `android-build-logs-*`.

Update detection reads public GitHub Releases. iOS users still download the IPA and install it using their own signing method.
