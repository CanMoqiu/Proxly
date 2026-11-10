# Contributing

[简体中文](CONTRIBUTING.md) · **English** · [Documentation](docs/README.en.md)

## Development environment

Use Flutter 3.47.5, pinned in `.flutter-version`, and Android Studio or Xcode for the target platform. Native iOS builds require macOS; Windows supports Dart analysis and Widget tests. See the [build guide](docs/mobile-builds.en.md) for packaging and signing.

For device features, prepare an OpenClash, Nikki, or compatible Mihomo API controller; configuration management also requires SSH/SFTP. Use recoverable test configurations. Do not commit real credentials, private keys, personal configuration, or build artifacts.

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
```

Add checks appropriate to the change: run `python3 -m unittest discover -s scripts -p 'test_*.py'` for packaging scripts; run `integration_test/web_panel_smoke_test.dart` and physical-device checks for WebView changes. Simulated callbacks and simulators do not replace real routers and devices.

## Repository layout

| Path | Responsibility |
| --- | --- |
| `lib/pages/` | Native pages and WebView containers |
| `lib/services/` | Controller API, adapters, SSH/SFTP, storage, and updates |
| `lib/widgets/` | Shared components and Home cards |
| `lib/l10n/` | Language settings and translations |
| `assets/web_panel/` | Upstream Zashboard distribution assets, kept unchanged |
| `android/`, `ios/` | Native projects |
| `test/`, `integration_test/` | Unit, Widget, and native integration tests |
| `scripts/` | Packaging, signing preparation, and package verification |

Native pages use shared state; web panels access the controller API through a local bridge. Separate adapters handle OpenClash and Nikki SSH management. Reuse existing connection state, storage, and restart flows. Follow the [dialog rules](docs/popup-interactions.en.md) and [Zashboard maintenance notes](docs/bundled-zashboard.en.md#asset-maintenance) when changing those areas.

## Code and pull requests

Keep each PR focused on one problem. Explain its purpose, user-visible changes, and actual test results, including platforms or device behavior that remain untested. Use [private reporting](SECURITY.en.md) for security issues.

Write source comments only in English. Explain necessary design reasons, security boundaries, or compatibility constraints without restating the code or mixing languages. UI text and localization are exempt. Write Git commit and push descriptions in English and describe the actual changes.

## Documentation and repository language

- Documentation, issue forms, and PRs default to Simplified Chinese; English participation is welcome. Maintain complete English counterparts, link languages at the top, and prefer English destinations from English pages.
- Organize content for its readers: README for introduction and setup, the user guide for operations and limits, and the build guide for environments and commands. Avoid repeated procedures, visual change logs, and one-off task reports.
- Preserve commands, paths, API fields, package names, and checksums. Update both languages and related links when features or limits change.
- Keep original licenses, upstream copyrights, and third-party notices. Translations aid reading and do not replace the original license.
- Workflow prompts and discussion forms use Chinese-first bilingual text. After renaming a discussion category, check `.github/DISCUSSION_TEMPLATE/<slug>.yml`; the filename must match GitHub's category URL slug. Poll categories do not support forms.
