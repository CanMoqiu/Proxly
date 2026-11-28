# Contributing

[简体中文](CONTRIBUTING.md) · **English** · [Documentation](docs/README.en.md)

## Development environment

Use the Flutter version pinned in `.flutter-version` and Android Studio or Xcode for the target platform. Native iOS builds require macOS. Windows supports static analysis and Flutter tests. See the [build guide](docs/mobile-builds.en.md) for packaging and signing.

For device features, prepare an OpenClash, Nikki, or compatible Mihomo API controller; configuration management also requires SSH/SFTP. Use recoverable test configurations. Do not commit real credentials, private keys, personal configuration, or build artifacts.

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
```

For packaging changes, run `python3 -m unittest discover -s scripts -p 'test_*.py'`. For WebView changes, run the native smoke test separately and check gestures and router connectivity on a physical device. See [iOS builds](docs/mobile-builds.en.md#ios-builds).

## Repository layout

| Path | Responsibility |
| --- | --- |
| `lib/pages/` | Native pages and WebView containers |
| `lib/services/` | Controller API, adapters, SSH/SFTP, storage, and updates |
| `lib/widgets/` | Shared components and Home cards |
| `lib/theme/` | Light and dark themes and component styling |
| `lib/l10n/` | Language settings and translations |
| `assets/web_panel/` | Upstream Zashboard distribution assets, kept unchanged |
| `android/`, `ios/` | Native projects |
| `test/`, `integration_test/` | Unit, Widget, and native integration tests |
| `scripts/` | Packaging, signing preparation, and package verification |

Native pages use shared state; web panels access the controller API through a local bridge. Separate adapters handle OpenClash and Nikki SSH management. Reuse existing connection state, storage, and restart flows. Follow the [dialog rules](docs/popup-interactions.en.md) and [Zashboard maintenance notes](docs/bundled-zashboard.en.md#asset-maintenance) when changing those areas.

### Where new code belongs

| Path | Responsibility |
| --- | --- |
| `lib/features/<feature>/` | Group pages, feature-specific widgets, state, and logic by feature. Examples include `yaml_config`, `web_panel`, `dashboard`, and `app_update`. Put YAML editor widgets in `lib/features/yaml_config/`. |
| `lib/core/<capability>/` | Group capabilities shared across features, including the controller API, SSH/SFTP, proxy backend adapters, and restart coordination. Put shared SSH/SFTP code in `lib/core/ssh/`. |
| `lib/widgets/`, `lib/theme/`, `lib/l10n/` | Store reusable UI widgets, theming, and localization, respectively. |
| `test/features/`, `test/core/` | Mirror the source module’s directory when placing new tests. Examples include `test/features/yaml_config/` and `test/core/ssh/`. |

- Start each feature directory with a few files. Split responsibilities that can be changed and verified independently, such as YAML editor document metrics, painting, and toolbars.
- Use a defined page entry point or service interface for cross-feature calls. Shared services ask for user confirmation through callbacks supplied by the UI, such as for SSH host trust. Pages read theme state from the theme layer, and the app entry point wires the pieces together.
- Name shared types after the capability they provide, such as a proxy restart coordinator. Name backend-specific commands, configuration, and behavior after the corresponding OpenClash or Nikki backend.
- Migrate files in small batches as part of regular changes, when the files are involved in the change and their destination is clear. Update callers and related tests in the same batch and preserve existing behavior.

## Code and pull requests

Keep each PR focused on one problem. Explain its purpose, user-visible changes, and actual test results, including platforms or device behavior that remain untested. Use [private reporting](SECURITY.en.md) for security issues.

Write source comments only in English. Explain necessary design reasons, security boundaries, or compatibility constraints without restating the code or mixing languages. UI text and localization are exempt. Write Git commit and push descriptions in English and describe the actual changes.

## Documentation and repository language

- Documentation, issue forms, and PRs default to Simplified Chinese; English participation is welcome. Maintain complete English counterparts, link languages at the top, and prefer English destinations from English pages.
- Organize content for its readers: README for introduction and setup, the user guide for operations and limits, and the build guide for environments and commands. Avoid repeated procedures, visual change logs, and one-off task reports.
- Preserve commands, paths, API fields, package names, and checksums. Update both languages and related links when features or limits change.
- Keep original licenses, upstream copyrights, and third-party notices. Translations aid reading and do not replace the original license.
- Workflow prompts and discussion forms use Chinese-first bilingual text. After renaming a discussion category, check `.github/DISCUSSION_TEMPLATE/<slug>.yml`; the filename must match GitHub's category URL slug. Poll categories do not support forms.
