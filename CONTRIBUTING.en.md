# Contributing

[简体中文](CONTRIBUTING.md) · **English** · [Documentation](docs/README.en.md)

Thank you for contributing to Proxly. Read the [README](README.en.md), [security policy](SECURITY.en.md), and relevant build guides before submitting an issue or code.

## Development environment

- Flutter 3.47.5
- Android Studio or Xcode for the target platform
- An OpenClash / Mihomo controller and an SSH/SFTP environment for testing

Windows supports Dart analysis and tests; iOS Release builds require a macOS environment, such as the manual GitHub Actions workflow. Do not commit controller secrets, SSH passwords, signing keys, personal configuration, build artifacts, or local AI/cache directories.

## Before submitting

```text
flutter pub get --enforce-lockfile
flutter analyze
flutter test
```

For platform changes, state the tested platform, OS version, and device behavior that remains untested. For versioning, builds, or releases, follow the [mobile build guide](docs/mobile-builds.en.md) and the maintainer's version rules.

## Pull requests

Issues, feature requests, and PRs default to Chinese; English contributions are also welcome. Explain the purpose, user-visible behavior, and validation. Git commit and push descriptions may be English only. Keep each PR focused on one problem. Do not include certificates, tokens, private router configuration, or files unrelated to the software. Follow the [security policy](SECURITY.en.md) for vulnerabilities and keep sensitive details private.

## Documentation and language

Maintain complete Simplified Chinese and English versions of new or changed public documentation, with language links at the top. Default entry pages and templates use Chinese. Preserve commands, paths, API fields, and identifiers. English documents should link to English counterparts. See the [repository language policy](docs/repository-language.en.md).
