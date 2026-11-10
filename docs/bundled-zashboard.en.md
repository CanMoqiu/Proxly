# Zashboard panel

[简体中文](bundled-zashboard.md) · **English** · [Documentation](README.en.md)

Proxly bundles Zashboard; no dashboard files need to be deployed on the router. Proxy, Rules, and web Connections use it, while the standalone console provides full web navigation. Theme, language, and controller connection follow app settings.

## Layout and connection cards

Phones use the mobile layout; Android tablets and iPads use the desktop layout. Embedded tabs hide web navigation and the overview sidebar; the standalone console retains them. Connections use cards on phones and tablets, with the same customizable defaults.

Card fields, table columns, and chain display save automatically in separate phone and tablet content profiles. The app manages display mode and sorting; shared imports do not overwrite device-specific connection content. Advanced options switches between native and web Connections.

The iOS Proxy page supports native history-back gestures from Rules to Proxy. Horizontal page swipes inside the panel are disabled; use page buttons or app navigation.

## Importing settings

The top-right import entry on Proxy offers two sources:

- **From core**: reads the controller's `/storage/zashboard` endpoint, requiring core support and saved settings.
- **From local JS file**: accepts Zashboard JSON data with `.json` or `.js` extensions; it does not execute JavaScript programs.

Files are limited to `5 MiB`, `2000` top-level keys, and `1 MiB` per serialized value. Imports filter credentials and app-managed settings. Rejected imports keep existing settings; successful ones refresh open panels.

## Updates and storage

Check, download, and install panel updates in Advanced options. SHA-256 and ZIP structure are verified before installation; failures retain the current panel. If download succeeded but activation failed, updating again retries activation only. An app update that changes the bundled panel version clears the downloaded older panel and uses the new bundled version.

Periodic HTTP cache cleanup preserves connection credentials, panel preferences, and installed assets. On Android cold launch, update APKs for the installed version or older versions are removed; newer packages awaiting installation remain available for retry.

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
