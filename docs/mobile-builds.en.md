# Android and iOS development, builds, and releases

[简体中文](mobile-builds.zh-CN.md) · **English** · [Documentation](README.en.md)

Both platforms share `main`, Flutter 3.47.5, dependency lockfiles, and the version in `pubspec.yaml`. Platform capabilities handle differences. Run `flutter analyze` and `flutter test` for shared-code changes, and validate both Android Release and iOS Release before publishing.

## Manual builds

Download official packages from [Releases](https://github.com/CanMoqiu/Proxly/releases). To build your own copy, use a repository where you have permission to run workflows and configure signing. Run the commands below from that checkout; GitHub CLI uses its repository context. These instructions do not require build access to the upstream public repository.

In **Actions → Proxly 双端打包 / Mobile builds → Run workflow**, choose:

- `ref`: a trusted branch, tag, or full commit SHA. Use a full main-branch SHA for a formal release.
- `platform`: `both` for both platforms, or `android` / `ios` for one.
- `android_build_type`: `release` uses the fixed production signing key; `debug` creates a separate test app with the `.debug` application ID suffix.

```powershell
gh workflow run mobile-builds.yml --ref main -f ref=main -f platform=both -f android_build_type=release
gh run list --workflow mobile-builds.yml --limit 5
```

This workflow is manual-only and uses artifacts by default. It declares repository contents write access to support private draft attachments, but does not create or publish Releases automatically. Artifacts last 14 days: `proxly-android-release-<number>` and `proxly-ios-unsigned-<number>`, each containing the package, SHA-256, and platform build information. Formal filenames include `Proxly-Android-26.8.apk` and `Proxly-iOS-26.8.ipa`; test versions retain their third version segment. Filenames omit internal build numbers. Failure logs are in `android-build-logs-*` / `ios-build-logs-*`.

Build type and version channel are separate: `debug` selects a debug signature and separate application ID; it does not automatically change the version to a test version. Both platforms take their version from `pubspec.yaml`.

## Private draft delivery (optional)

If Actions artifact storage is exhausted, first create a matching prerelease draft in a private repository targeting the full source commit SHA, then supply `draft_release_tag` (for example, `v26.8.1`). Leave it blank to keep using artifacts. Before building and uploading, the workflow checks repository privacy, the beta version, the draft tag, and the exact target SHA. It does not overwrite assets, publish drafts, or delete historical packages. Only the APK and IPA are uploaded as draft assets; this mode uses native Actions logs instead of log artifacts. Once one platform has uploaded successfully, retry only the failed platform to avoid duplicate asset names.

## Android production signing

GitHub Actions uses these repository Secrets:

- `ANDROID_KEYSTORE_BASE64`: Base64-encoded PKCS#12 keystore.
- `ANDROID_KEYSTORE_PASSWORD`: keystore password.
- `ANDROID_KEY_PASSWORD`: private-key password.
- `ANDROID_KEY_ALIAS`: key alias.

The repository variable `ANDROID_CERT_SHA256` pins the production certificate digest. Packaging checks it to prevent use of a debug or unrelated key. The keystore is restored only into the runner's temporary directory for the build, then removed; do not upload it in logs, caches, or release attachments.

For local builds, use an untracked `android/key.properties` with `storeFile` (absolute path), `storeType=PKCS12`, `storePassword`, `keyAlias`, and `keyPassword`. Do not commit private keys or passwords. Keep a secure backup and use the same signing key for later versions.

```powershell
flutter build apk --release --target-platform android-arm64,android-x64
```

Since 26.6.0+35, the official certificate SHA-256 has been `938c46e51d9149a2cec9f3af7efc4da730894e9e1ec192b982c55a22fbb1c6d8`. Version 26.5 used a different debug certificate and cannot be overwritten directly. Before upgrading, securely record your connection details and required settings, then uninstall the old version and install the new one. Later versions with the same signature can be installed over it. This digest is public verification information, not a signing key; independently signed builds cannot overwrite official packages.

## Android architectures

Android builds after 26.8 support only ARM64 (`arm64-v8a`) and x86_64. **Subsequent versions no longer support Android ARM32 devices**, and no 32-bit x86 package is provided. Devices running a 32-bit OS, including those with an ARM64 CPU, should stay on 26.8. Both supported architectures remain in one APK with the same application ID and signing identity. Packaging checks require complete native libraries for both architectures and reject ARM32 libraries.

## Storage after use

Startup does not create proxy or connections WebViews until their tabs are first opened; visited pages retain their state. Hidden tabs pause Flutter animations. The native connections list polls only while its tab is visible, no other page covers it, and the app is in the foreground. Returning refreshes its data without continuous hidden-page requests or redraws.

On Android cold startup, cleanup removes only in-app update APKs matching the installed version or an older version, plus download leftovers without a version marker. Newer APKs awaiting installation remain available for retry; launching the installer does not immediately delete them. Cleanup failures do not prevent startup.

Local panel resources use `Cache-Control: no-store` to avoid duplicate HTTP caches under random local ports. Android and iOS clear old WebView HTTP caches on first launch, application version changes or seven days after the last successful cleanup without deleting cookies, web storage, panel preferences, connection credentials, the installed panel, or user YAML files. Bundled and downloaded panels continue loading from local resources without an Internet download. On iOS, only WKWebView memory and disk HTTP caches are removed; Fetch caches, offline data, and IndexedDB remain intact. The application sandbox is not wiped.

## iOS self-signing

iOS 18+ iPhones use an unsigned Release IPA. No Apple certificate needs to be stored in the repository. See the [iPhone guide](ios-selfsign.en.md) for builds, installation, and in-place updates.

## Publishing

Select a verified source commit and run both builds using its full SHA. Confirm both jobs succeed, and check the embedded versions, source SHA, Android signature, and file digests. Publish the matching formal source, tag, and verified packages. Keep build diagnostics for traceability; include necessary version information and package digests in the release notes without exposing internal repository details or credentials.

Release notes default to Chinese and have a complete English counterpart. Distinguish the signed Android APK from the iOS IPA requiring self-signing, and retain signing information affecting in-place updates.

The first release with this architecture change must state in Important notes that Android ARM32 is no longer supported and that ARM64 and x86_64 are supported, directing 32-bit users to 26.8. The supported-platforms item in Version information stays “Android 7.0+; iOS 18+” without parenthetical details.
