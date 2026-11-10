# Android and iOS build guide

[简体中文](mobile-builds.zh-CN.md) · **English** · [Documentation](README.en.md)

Both platforms use Flutter 3.47.5 and the version in `pubspec.yaml`. `pubspec.lock` and `ios/Podfile.lock` pin dependencies. Android supports ARM64 and x86_64; iOS supports iPhones and iPads on iOS 18+. See [Contributing](../CONTRIBUTING.en.md) for development checks.

## GitHub Actions

In a repository where you can run workflows and configure signing, open **Actions → Proxly 双端打包 / Mobile builds → Run workflow**:

| Input | Purpose |
| --- | --- |
| `ref` | Trusted branch, tag, or full commit SHA; use a full SHA for release builds |
| `platform` | `both`, `android`, or `ios` |
| `android_build_type` | `release` uses production signing; `debug` uses `top.canmoqiu.proxly.debug` with separate settings |
| `draft_release_tag` | Optional private test-draft delivery, described below; leave blank by default |

Alternatively, run these commands from that checkout, replacing `COMMIT_SHA` with the full source SHA:

```sh
gh workflow run mobile-builds.yml --ref main -f ref=COMMIT_SHA -f platform=both -f android_build_type=release
gh run list --workflow mobile-builds.yml --limit 5
```

The workflow is manual-only and does not publish Releases automatically. It executes scripts from the selected `ref`, so use trusted code. `debug` changes the build type and application ID, not the version channel.

### Downloading artifacts

After completion, download artifacts from the matching run:

| Artifact | Contents |
| --- | --- |
| `proxly-android-release-<number>` | Production-signed APK, SHA-256, `build-info-android.json` |
| `proxly-android-debug-<number>` | Separate debug APK, digest, and build information |
| `proxly-ios-unsigned-<number>` | IPA, SHA-256, `build-info-ios.json` |
| `android-build-logs-*` / `ios-build-logs-*` | Analysis, test, and compiler logs |

Artifacts last 14 days. In this CLI example, `RUN_ID` is the ID on the run page, not the run number used in artifact names:

```sh
gh run download RUN_ID -p 'proxly-android-release-*' -p 'proxly-ios-unsigned-*' -D dist
```

### Private test-draft delivery

If artifact storage is unavailable, first create a matching prerelease draft in a private repository targeting the full source SHA, then supply `draft_release_tag`. This mode supports test versions only.

Before building and uploading, the workflow checks repository visibility, version, draft state, and target SHA. It uploads only APK / IPA files without overwriting assets or publishing the draft; view logs in Actions. If one platform already uploaded successfully, retry only the other. The workflow declares `contents: write` for this mode.

## Android signing and local builds

Actions requires these Secrets and the repository variable `ANDROID_CERT_SHA256`:

| Secret | Content |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded PKCS#12 keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_PASSWORD` | Private-key password |
| `ANDROID_KEY_ALIAS` | Key alias |

Packaging verifies the certificate digest. The key is restored into the runner's temporary directory and removed afterward. Keep keys and passwords out of logs, caches, and attachments.

For local builds, use an untracked `android/key.properties` containing `storeFile` (absolute path), `storeType=PKCS12`, `storePassword`, `keyAlias`, and `keyPassword`:

```sh
flutter pub get --enforce-lockfile
flutter build apk --release --target-platform android-arm64,android-x64
```

Both architectures share one APK. Use 26.8 on a 32-bit Android system, including an ARM64 device running a 32-bit OS.

The official certificate SHA-256 is `938c46e51d9149a2cec9f3af7efc4da730894e9e1ec192b982c55a22fbb1c6d8`. Version 26.5 used a different debug certificate: safely record settings, uninstall it, then install the new package. Later releases with the same signature support in-place updates. Independently signed packages cannot overwrite official ones.

## iOS builds

Native compilation requires macOS, Xcode, and CocoaPods. Actions installs the pinned Flutter toolchain, runs the simulator WebView integration test, and produces a device Release package. It checks that `ios/Podfile.lock` has not drifted. Simulator output cannot replace a device package. See the [iOS installation guide](ios-selfsign.en.md) for installation.

## Before publishing

- Confirm both builds and applicable tests pass. Check connection, proxy switching, configuration operations, background recovery, and in-place updates on real devices.
- Match the source SHA in build information to the selected commit, and embedded version and build number to `pubspec.yaml`.
- Verify the Android certificate and both architectures, iOS device support, and package digests through the packaging checks.
- Publish matching source, tags, and packages. Upload only installation packages and include digests in Chinese and English release notes.

Formal filenames include `Proxly-Android-26.10.apk` and `Proxly-iOS-26.10.ipa`; test versions retain the third segment. Filenames and release notes omit internal build numbers. Describe compatibility, signing, or migration changes in the version that introduces them.
