# Android and iOS build guide

[简体中文](mobile-builds.zh-CN.md) · **English** · [Documentation](README.en.md)

Both platforms use the Flutter version pinned in `.flutter-version` and the app version and build number in `pubspec.yaml`. `pubspec.lock` and `ios/Podfile.lock` pin dependencies. See [Contributing](../CONTRIBUTING.en.md) for development checks.

## GitHub Actions

In a repository where you can run workflows, open **Actions → Proxly 双端打包 / Mobile builds → Run workflow**. The workflow branch selects the workflow definition. The `ref` input selects the source to build.

| Input | Purpose |
| --- | --- |
| `ref` | Trusted branch, tag, or full commit SHA; use a full SHA for release builds |
| `platform` | `both`, `android`, or `ios` |
| `android_build_type` | `release` uses production signing, `unsigned` produces a release build for local signing, and `debug` uses the separate app ID `top.canmoqiu.proxly.debug` |
| `draft_release_tag` | Optional private test-draft delivery, described below; leave blank by default |

You can also run these commands from that checkout. Replace `COMMIT_SHA` with the full source SHA and choose the branch that contains the workflow definition.

```sh
gh workflow run mobile-builds.yml --ref main -f ref=COMMIT_SHA -f platform=both -f android_build_type=release
gh run list --workflow mobile-builds.yml --limit 5
```

Maintainers trigger the workflow manually. Choose a trusted `ref` because the build runs scripts from that commit. Use the same full SHA for both platforms. When delivering through Actions artifacts, update the Release draft after downloading and verifying the packages. Leave `draft_release_tag` blank when Android uses `unsigned`.

### Downloading artifacts

After completion, download artifacts from the matching run:

| Artifact | Contents |
| --- | --- |
| `proxly-android-release-<number>` | Production-signed APK, SHA-256, `build-info-android.json` |
| `proxly-android-unsigned-<number>` | `app-release-unsigned.apk`, SHA-256, and `commit.txt` |
| `proxly-android-debug-<number>` | Separate debug APK, digest, and build information |
| `proxly-ios-unsigned-<number>` | IPA, SHA-256, `build-info-ios.json` |
| `android-build-logs-*` / `ios-build-logs-*` | Analysis, test, and compiler logs |

Artifacts last 14 days. Use the `RUN_ID` from the run page for CLI downloads. If Android was built with `unsigned`, match the artifact using `proxly-android-unsigned-*`.

```sh
gh run download RUN_ID -p 'proxly-android-release-*' -p 'proxly-ios-unsigned-*' -D dist
```

### Private test-draft delivery

If artifact storage is unavailable, first create a matching prerelease draft in a private repository targeting the full source SHA, then supply `draft_release_tag`. This mode supports test versions only.

Before building and uploading, the workflow checks repository visibility, version, draft state, and target SHA. It uploads only APK / IPA files without overwriting assets or publishing the draft; view logs in Actions. If one platform already uploaded successfully, retry only the other. The workflow declares `contents: write` for this mode.

## Android signing and local builds

The Actions `release` mode uses these Secrets and the repository variable `ANDROID_CERT_SHA256`.

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

Before signing an unsigned Actions artifact, verify `commit.txt` and its APK SHA-256. Use Android SDK Build Tools to align, sign, and verify the APK in that order. Replace `KEYSTORE`, `KEY_ALIAS`, and `VERSION` with the release keystore path, alias, and display version. Enter passwords when prompted. See [zipalign](https://developer.android.com/tools/zipalign) and [apksigner](https://developer.android.com/tools/apksigner).

```sh
zipalign -P 16 4 app-release-unsigned.apk app-release-aligned.apk
apksigner sign --ks KEYSTORE --ks-key-alias KEY_ALIAS --out Proxly-Android-VERSION.apk app-release-aligned.apk
zipalign -c -P 16 4 Proxly-Android-VERSION.apk
apksigner verify --verbose --print-certs Proxly-Android-VERSION.apk
```

Recalculate SHA-256 for the signed APK. Verify its certificate, app ID, version, and bundled ARM64 and x86_64 build files.

The official certificate SHA-256 is `938c46e51d9149a2cec9f3af7efc4da730894e9e1ec192b982c55a22fbb1c6d8`. Version 26.5 used a different debug certificate: safely record settings, uninstall it, then install the new package. Later releases with the same signature support in-place updates. Independently signed packages cannot overwrite official ones.

## iOS builds

Native compilation requires macOS, Xcode, and CocoaPods. Actions installs the pinned Flutter toolchain, runs static analysis and the regular test suite, then produces a device Release package and checks `ios/Podfile.lock`. To verify WebViews separately, boot an iPhone simulator and run `flutter test integration_test/web_panel_smoke_test.dart -d <device-id>`. See the [iOS installation guide](ios-selfsign.en.md) for installation.

## Before publishing

- Confirm both builds and applicable tests pass. Check connection, proxy switching, configuration operations, background recovery, and in-place updates on real devices.
- Verify the source SHA in each build's metadata or `commit.txt`, along with the version and build number in the package.
- Verify the final APK certificate and both architectures, IPA device support, and both package digests. For local Android signing, verify the signed APK.
- Before publishing, select a plain version tag such as `v26.11.2` that points to the same source commit. Mark test versions in the release title and notes. Attach the final APK and IPA and include both digests in Chinese and English.

Examples of stable filenames are `Proxly-Android-26.10.apk` and `Proxly-iOS-26.10.ipa`. Test versions retain the third segment. Filenames and release notes omit internal build numbers. Describe compatibility, signing, or migration changes in the version that introduces them.
