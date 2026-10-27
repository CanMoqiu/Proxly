# Bundled Zashboard

[简体中文](bundled-zashboard.md) · **English** · [Documentation](README.en.md)

- Version: v3.29.1 (2026-09-23)
- [Official release](https://github.com/Zephyruso/zashboard/releases/tag/v3.29.1)
- Commit: `50717b02dac68425cdc5b80cb754bea768ee4fc9`
- Asset: official `dist.zip`; SHA-256:
  `4f16cce229e223bd07b5a3daccfbfb8bf349d7335572d412959284ab6c9bab50`
- `assets/web_panel` preserves the distribution assets and includes the upstream MIT `LICENSE`.

Proxly adapts theme, authentication, navigation dock, and fonts through separate injected scripts, without changing minified upstream JavaScript. Proxy and Connections hide Zashboard's own dock; the standalone console retains it. The hidden dock keeps a zero-height positioning box at the viewport bottom so upstream virtual lists calculate bottom spacing correctly. The iOS flag font comes from an app-owned resource path and continues working after switching to a downloaded panel.

Native WebView settings and CSS control edge overscroll. Proxly owns `config/disable-pull-to-refresh` and sets it to `false`, disabling v3.29.1's global `touchmove` interception based on the initial touch direction. This prevents reverse scrolling from remaining blocked after reaching an edge. The adaptation applies to Proxy, Connections, and the console after panel updates, settings imports, and reloads. Browser-native scrolling, inertia, and nested-list handling remain intact; upstream minified assets are unchanged.

Proxly also fixes `config/swipe-in-pages` and `config/swipe-in-tabs` to off, preventing horizontal swipes from changing panel content. In-page buttons and the app's bottom navigation continue to work.

The import entry at the top right of Proxy offers import from the core or a local JS file. Core import reads Zashboard's `/storage/zashboard` endpoint and requires core support and saved settings. Local import accepts Zashboard JSON data with a `.json` or `.js` extension; it does not execute JavaScript. Both sources share size and structure checks, credential filtering, and protection of app-managed settings. Successful imports synchronize and reload live panels.
