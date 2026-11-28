# Zashboard panel

[简体中文](bundled-zashboard.md) · **English** · [Documentation](README.en.md)

Proxly bundles Zashboard; no dashboard files need to be deployed on the router. Proxy, Rules, and web Connections use it, while the standalone console provides full web navigation. Theme, language, and controller connection follow app settings.

## Layout and connection cards

Phones use the mobile layout; Android tablets and iPads use the desktop layout. Embedded tabs hide web navigation and the overview sidebar; the standalone console retains them. Connections use cards on phones and tablets, with the same customizable defaults.

Card fields, table columns, and chain display are saved per controller profile, with separate settings for phone and tablet layouts. The app manages display mode and sorting, and imports preserve connection content settings. Once optional settings are visible, use Advanced options to switch between native and web Connections. See [Optional settings](dashboard.en.md#optional-settings).

The iOS Proxy page supports native history-back gestures from Rules to Proxy. Horizontal page swipes inside the panel are disabled; use page buttons or app navigation.

## Importing settings

The top-right import entry on Proxy offers two sources:

- **From core**: reads the controller's `/storage/zashboard` endpoint, requiring core support and saved settings.
- **From local JS file**: accepts Zashboard JSON data with `.json` or `.js` extensions; it does not execute JavaScript programs.

Files are limited to `5 MiB`, `2000` top-level keys, and `1 MiB` per serialized value. Imports apply to the active controller profile and filter credentials and app-managed settings. A failed import preserves existing settings. A successful import refreshes open panels.

## Loading and recovery

When the controller is online and Home or Proxy is in the foreground, the app prepares Proxy first and continues with web Connections. On Android and iOS, after five minutes or more in the background, panels are rebuilt when they next need to appear.

The embedded panels share one HTTP cache check. During initial WebView preparation, the app attempts cleanup if the version or build number has changed or seven days have passed since the last successful cleanup. Credentials, panel preferences, and installed assets are retained.

## Updates and storage

Check, download, and install panel updates in Advanced options. SHA-256 and ZIP structure are verified before installation; failures retain the current panel. If download succeeded but activation failed, updating again retries activation only. An app update that changes the bundled panel version clears the downloaded older panel and uses the new bundled version.

## Asset maintenance

| Item | Value |
| --- | --- |
| Bundled version | [v3.30.0](https://github.com/Zephyruso/zashboard/releases/tag/v3.30.0) |
| Upstream commit | `bf4f00bb8d905f8a78f627af7cf84457c4db53c4` |
| Distribution | Official `dist.zip` |
| SHA-256 | `1f91c014e61e768240a86ad0a9bd565b247ec5a0e26b125fb5d19076682905b7` |

Keep upstream distribution assets and the MIT license in `assets/web_panel/` unchanged. Adapt theme, authentication, navigation, fonts, and device layout through app-side scripts rather than editing minified JavaScript. See [bundled fonts](../assets/fonts/README.en.md) for flag-font provenance.

Preserve these constraints:

- Tablets use a display shortest side of at least `600` logical pixels, independent of keyboard or split-screen window size.
- The hidden dock retains a zero-height positioning box at the viewport bottom for virtual-list spacing.
- Keep `config/disable-pull-to-refresh` at `false` to avoid upstream global touch interception blocking reverse scrolling at an edge. Native WebView settings and CSS control overscroll.
- Keep `config/swipe-in-pages` and `config/swipe-in-tabs` disabled. On iOS Proxy, disable only top-level web route transitions to avoid combining them with native history animation.
- Update archives are limited to `50 MiB` downloaded, `2000` entries, `20 MiB` per file, `100 MiB` extracted, and a `100:1` compression ratio. Reject out-of-bounds paths, duplicate paths, and symbolic links.

After upgrading assets, check offline startup, theme and language sync, imports, device layouts, edge scrolling, and iOS history-back behavior. Native integration tests do not replace physical-device touch verification.
