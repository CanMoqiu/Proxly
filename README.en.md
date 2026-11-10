<div align="center">
  <img src="proxly-icon.png" width="96" alt="Proxly icon" />
  <h1>Proxly</h1>
  <p><strong>An Android and iOS client for router proxy management</strong></p>
  <p>Monitor status, switch proxies, inspect rules and connections, and manage YAML configurations.</p>

  [![Latest release](https://img.shields.io/github/v/release/CanMoqiu/proxly?label=release)](https://github.com/CanMoqiu/proxly/releases/latest)
  [![Platform](https://img.shields.io/badge/platform-Android%20%26%20iOS-3DDC84?logo=android&logoColor=white)](#requirements)
  [![License](https://img.shields.io/github/license/CanMoqiu/proxly)](LICENSE)

  [Downloads](https://github.com/CanMoqiu/proxly/releases) · [Documentation](docs/README.en.md) · [简体中文](README.md)
</div>

Proxly connects to your own OpenClash, Nikki, or compatible Clash/Mihomo API controller. It combines a native interface, bundled Zashboard, and SSH/SFTP for device management. It does not include a proxy core, provide nodes or subscriptions, or forward traffic.

## Getting started

1. Download a package from [Releases](https://github.com/CanMoqiu/proxly/releases). For iPhone and iPad, follow the [iOS installation guide](docs/ios-selfsign.en.md).
2. Enter the controller address and secret. For configuration management, also enter the SSH password and port (default `22`).
3. Select Continue to detect the proxy software and preselect it in Preferences. Unidentified software uses Mihomo generic configuration; you can also choose manually. Finish Preferences to open Home.

You can later edit connection details in Settings, and change proxy software, language, or the Connections view in Advanced options. See the [user guide](docs/dashboard.en.md).

## Features

| Feature | Description |
| --- | --- |
| Home | Runtime status, software and core versions, live traffic, connection overview, and subscription usage; reorder or hide cards |
| Proxies and rules | Bundled Zashboard for proxy and group selection, rule inspection, and a standalone console |
| Connections | Native list or web panel; web Connections uses cards on phones and tablets with automatically saved content customization |
| Quick settings | Adjust proxy mode, DNS, traffic handling, bypass, and other supported settings |
| Configuration | Switch, edit, upload, rename, export, and delete supported YAML files |
| Maintenance and updates | Restart proxy services, flush DNS caches, close connections, and update the app or dashboard |
| Interface | Simplified Chinese and English; system, light, and dark themes; portrait and landscape on tablets |

OpenClash and Nikki have dedicated adapters. Other compatible controllers use Mihomo generic configuration, which provides controller API features without SSH configuration management or service restart. Unsupported features are hidden while saved Home preferences are retained. See [adapter support](docs/dashboard.en.md#adapter-support).

## Requirements

- **Android 7.0+**: ARM64 and x86_64 only. Use 26.8 on a 32-bit Android system.
- **iOS 18+**: iPhone and iPad.
- **Controller**: enable `external-controller` and use a LAN IP or hostname reachable from your device. The default port is `9090`. If `secret` is configured, enter the same secret in the app.
- **SSH/SFTP**: OpenClash and Nikki configuration management and service restart require SSH access as `root`. Reading and writing YAML files also requires SFTP.

Connection credentials and SSH host fingerprints use platform secure storage. First SSH connections and changed fingerprints require confirmation. YAML operations are restricted to supported directories and file sizes; imported settings and update packages are validated before use.

## Documentation and participation

- [User guide](docs/dashboard.en.md): connections, Home, software support, YAML management, and troubleshooting.
- [Zashboard](docs/bundled-zashboard.en.md): panel layout, settings import, and asset maintenance.
- [Build guide](docs/mobile-builds.en.md): mobile packaging, Android signing, and package verification.
- [Contributing](CONTRIBUTING.en.md): development environment, repository layout, and code and documentation conventions.
- [Bug reports and feature requests](https://github.com/CanMoqiu/Proxly/issues/new/choose). Use [private reporting](SECURITY.en.md) for vulnerabilities.

## Technology and acknowledgements

Built with [Flutter](https://flutter.dev/), [Zashboard](https://github.com/Zephyruso/zashboard), [flutter_inappwebview](https://github.com/pichillilorenzo/flutter_inappwebview), [dartssh2](https://github.com/TerminalStudio/dartssh2), [Re-Editor](https://pub.dev/packages/re_editor), and other open-source projects. See [pubspec.yaml](pubspec.yaml) for dependencies and the [license index](docs/README.en.md#licenses) for licenses and third-party notices.

## Legal and service boundaries

Proxly is an open-source Android and iOS client intended solely to manage OpenClash / Mihomo environments deployed by and accessible to the user. The maintainers do not provide proxy nodes, subscriptions, accounts, routes, bandwidth, VPNs, international network channels, traffic forwarding, hosted operation, remote configuration, or other ongoing software services. The maintainers do not participate in the construction, operation, or data transmission of a user's network environment.

This project is not intended to provide, facilitate, or assist services commonly described as bypassing network restrictions. It must not be used to break through, bypass, or evade network-access controls lawfully implemented by the People's Republic of China. Anyone using the project within the People's Republic of China must comply with applicable laws and regulations, use lawful network access and international networking channels, and must not use the project for unlicensed telecommunications activities, unlawful international networking, acts that endanger network security, infringement of lawful rights, or other unlawful activities.

Users independently decide whether to use the project and remain responsible for their devices, configurations, network access methods, data processing, conduct, and resulting consequences. The disclaimer in the [MIT License](LICENSE) continues to apply; this statement does not exclude liabilities that cannot lawfully be excluded.

Related official legal texts:

- [Interim Provisions of the People's Republic of China on the Administration of International Networking of Computer Information Networks](https://xzfg.moj.gov.cn/front/law/detail?LawID=1713&Query=), including Articles 6, 8, and 10 on international networking channels, operating activities, and access methods.
- [Telecommunications Regulations of the People's Republic of China](https://www.samr.gov.cn/zw/zfxxgk/fdzdgknr/bgt/art/2023/art_cb96d9e9147740f79f4c111bb637ce29.html), including provisions on telecommunications licensing, international communications, and network and information security.
- [Cybersecurity Law of the People's Republic of China](https://www.cac.gov.cn/2025-12/29/c_1768735112911946.htm), using the amended text effective January 1, 2026.

These links identify publicly available official legal texts and do not constitute legal advice for a specific use case.

## Affiliation and license

Proxly is an independent open-source project and has no official affiliation, authorization, or warranty relationship with Clash, OpenClash, Mihomo, Zashboard, or related service providers.

The source code is distributed under the [MIT License](LICENSE), Copyright (c) 2026 CanMoqiu.
