# Bundled fonts

- `JetBrainsMono-Regular.ttf`: JetBrains Mono 2.304, unmodified, from
  https://github.com/JetBrains/JetBrainsMono/tree/cd5227bd1f61dff3bbd6c814ceaf7ffd95e947d9
  (`fonts/ttf/JetBrainsMono-Regular.ttf`). Copyright JetBrains. SIL Open Font
  License 1.1; see `JetBrainsMono-OFL.txt`. ProxlyMono is the Flutter family alias.
- `ProxlyFlags.woff2`: unmodified `TwemojiMozilla-flags-B12sb_Bp.woff2` from the
  official Zashboard v3.29.1 distribution, renamed to a stable asset name.
  SHA-256: `c030920068cc493d59cc8c21ff29000b7a3676c40414cba7e7a5780d02f41cbf`.
  Twemoji artwork copyright Twitter and contributors, CC BY 4.0; Mozilla's
  COLR font conversion code is Apache 2.0. See `Twemoji-LICENSE.md` and
  https://github.com/mozilla/twemoji-colr. The flag-only subset is supplied by
  https://github.com/Zephyruso/zashboard. No additional glyph changes by Proxly.

The flag font is served by Proxly's loopback server even when the dashboard is
updated separately. iOS places it before the selected text font for regional
indicator characters; it does not change node names or stored preferences.
