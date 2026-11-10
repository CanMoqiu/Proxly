# iOS installation guide

[简体中文](ios-selfsign.zh-CN.md) · **English** · [Documentation](README.en.md)

Supports iPhones and iPads running iOS 18+. iPhones use portrait; iPads support portrait and landscape. The app manages the router's proxy service and does not run a proxy core on the device.

## Installation and updates

1. Download the IPA from [Releases](https://github.com/CanMoqiu/Proxly/releases) and compare its SHA-256 with the release notes.
2. Import it into your signing tool, follow its signing and installation steps, and complete any iOS trust or Developer Mode requirements.
3. For updates or renewal, keep the actual Bundle ID, signing identity, and Keychain access configuration consistent and install over the existing app. The project Bundle ID is `top.canmoqiu.proxly`. Uninstalling or changing signing configuration may affect local settings and credential access.

Use either command to verify the digest, replacing `FILE.ipa` with the downloaded path:

```powershell
Get-FileHash -Algorithm SHA256 FILE.ipa
```

```sh
shasum -a 256 FILE.ipa
```

App update notices open Releases; download and install the new package using the same steps. Certificate lifetime and renewal depend on the signing tool. To compile your own package, see the [mobile build guide](mobile-builds.en.md).

## First connection

Allow **Local Network** access and ensure the device can reach the router's controller port. If permission was denied, enable it in Proxly's system settings and retry. See [connection setup](dashboard.en.md#connection-setup) for controller, software, and SSH settings.

Passwords and secrets use device-only Keychain storage accessible while unlocked, without iCloud sync. Temporary read failures allow retry without automatically clearing credentials.

## Troubleshooting

| Problem | Action |
| --- | --- |
| Installation or launch fails | Check the OS version, signature validity, and the tool's trust and Developer Mode requirements |
| Controller cannot connect | Check Local Network permission, network, address, port, and secret |
| Panel fails after returning from the background | Retry from the page; check the router state before repeating remote operations |
| Zashboard fails to load after updating | Select update again to retry activation without repeating a successful download |

Data refresh resumes in the foreground; the app does not monitor continuously in the background. Reports should include device model, iOS and app versions, and reproduction steps. Include the signing tool for installation issues, but omit passwords, secrets, and certificates.
