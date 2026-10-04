import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// An app-owned flag font works for both bundled and downloaded dashboards,
/// independently of the device's regional system emoji font.
class WebPanelFlagFont {
  static const path = '/__proxly_flags.woff2';
  static const asset = 'assets/fonts/ProxlyFlags.woff2';

  static Future<bool> handle(HttpRequest request) async {
    if (request.uri.path != path) return false;
    try {
      final bytes = await rootBundle.load(asset);
      request.response.headers.contentType = ContentType('font', 'woff2');
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      request.response.add(bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      ));
    } catch (_) {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
    return true;
  }

  static String buildScript() {
    final css = [
      "@font-face { font-family: 'ProxlyFlags'; src: url('$path') format('woff2'); unicode-range: U+1F1E6-1F1FF; font-display: swap; }",
      // Put flags BEFORE all system fonts; keep the user's chosen text font.
      for (final font in const {
        'MiSans': "'MiSans-VF'",
        'SarasaUI': "'SarasaUiSC-Regular'",
        'PingFang': "'PingFangSC-Regular'",
        'FiraSans': "'Fira Sans'",
        'SystemUI': 'system-ui',
      }.entries)
        "#app-content[class*='font-${font.key}-'] { font-family: 'ProxlyFlags', ${font.value}, 'Twemoji', system-ui !important; }",
      ".vjs-tree { font-family: 'ProxlyFlags', Menlo, Monaco, Consolas, monospace !important; }",
    ].join('\n');
    return '''
      (function() {
        function apply() {
          if (document.getElementById('__proxly_flag_font')) return;
          const style = document.createElement('style');
          style.id = '__proxly_flag_font';
          style.textContent = ${jsonEncode(css)};
          (document.head || document.documentElement).appendChild(style);
        }
        if (document.documentElement) apply();
        document.addEventListener('DOMContentLoaded', apply, { once: true });
      })();
    ''';
  }
}
