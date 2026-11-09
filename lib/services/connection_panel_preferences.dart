import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConnectionPanelPreferences {
  ConnectionPanelPreferences();

  static final instance = ConnectionPanelPreferences();
  static const handlerName = 'saveConnectionPanelContent';
  static const phoneKey = 'webpanel_connection_content_phone_v1';
  static const tabletKey = 'webpanel_connection_content_tablet_v1';
  static const contentKeys = {
    'config/connection-card-lines',
    'config/connection-table-columns',
    'config/connection-table-size',
    'config/show-full-proxy-chain',
    'config/proxy-chain-direction',
  };
  static const _fields = {
    'close',
    'type',
    'process',
    'host',
    'rule',
    'chains',
    'outbound',
    'dlSpeed',
    'ulSpeed',
    'dl',
    'ul',
    'connectTime',
    'sourceIP',
    'sourcePort',
    'sniffHost',
    'destination',
    'destinationType',
    'geoip',
    'remoteAddress',
    'inboundUser',
  };
  Future<void>? _pending;

  static Map<String, String> defaults({required bool tablet}) => {
        'config/connection-card-lines':
            '[["host","close"],["sourceIP","connectTime"],["chains","dlSpeed","ulSpeed"],["rule","dl","ul"]]',
        'config/show-full-proxy-chain': 'true',
        'config/proxy-chain-direction': 'normal',
      };

  static Map<String, String> sanitize(Map<dynamic, dynamic> values) {
    final result = <String, String>{};
    for (final entry in values.entries) {
      final key = entry.key;
      final value = entry.value;
      if (!contentKeys.contains(key) ||
          value is! String ||
          value.length > 8192) {
        continue;
      }
      var valid = false;
      if (key == 'config/show-full-proxy-chain') {
        valid = value == 'true' || value == 'false';
      } else if (key == 'config/proxy-chain-direction') {
        valid = value == 'normal' || value == 'reverse';
      } else if (key == 'config/connection-table-size') {
        valid = value == 'small' || value == 'large';
      } else {
        try {
          final decoded = jsonDecode(value);
          bool fields(dynamic row) =>
              row is List &&
              row.length <= 20 &&
              row.every((field) => field is String && _fields.contains(field));
          valid = key == 'config/connection-card-lines'
              ? decoded is List &&
                  decoded.isNotEmpty &&
                  decoded.length <= 12 &&
                  decoded.every(fields)
              : decoded is List && decoded.isNotEmpty && fields(decoded);
        } catch (_) {
          valid = false;
        }
      }
      if (valid) result[key as String] = value;
    }
    return result;
  }

  Future<Map<String, String>> load({required bool tablet}) async {
    final pending = _pending;
    if (pending != null) await pending;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(tablet ? tabletKey : phoneKey);
    final result = defaults(tablet: tablet);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) result.addAll(sanitize(decoded));
      } catch (_) {
        // Keep device defaults when a stored content layout is damaged.
      }
    }
    return result;
  }

  Future<void> save(Map<dynamic, dynamic> patch, {required bool tablet}) {
    final safe = sanitize(patch);
    if (safe.isEmpty) return Future<void>.value();
    final next = (_pending ?? Future<void>.value()).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final key = tablet ? tabletKey : phoneKey;
      final values = <String, String>{};
      try {
        final old = jsonDecode(prefs.getString(key) ?? '{}');
        if (old is Map) values.addAll(sanitize(old));
      } catch (_) {
        // Replace damaged content preferences without touching shared settings.
      }
      values.addAll(safe);
      if (!await prefs.setString(key, jsonEncode(values))) {
        throw StateError('Could not save connection content');
      }
    });
    late final Future<void> settled;
    settled = next.catchError((_) {}).whenComplete(() {
      if (identical(_pending, settled)) _pending = null;
    });
    _pending = settled;
    return next;
  }

  void bind(
    InAppWebViewController controller, {
    required bool tablet,
    required int port,
    required bool Function() isCurrent,
  }) {
    controller.addJavaScriptHandler(
      handlerName: handlerName,
      callback: (arguments) async {
        if (!isCurrent() || arguments.length != 1 || arguments.first is! Map) {
          return false;
        }
        final url = await controller.getUrl();
        if (!isCurrent() ||
            url?.scheme != 'http' ||
            url?.host != '127.0.0.1' ||
            url?.port != port) {
          return false;
        }
        await save(arguments.first as Map, tablet: tablet);
        return true;
      },
    );
  }

  static String script(Map<String, String> content, {required bool tablet}) {
    final values = {
      ...sanitize(content),
      'config/connection-display-style': 'card',
      'config/use-connecticon-card': 'true',
      'config/connection-sort-type': 'connectTime',
      'config/connection-sort-direction': 'desc',
      'config/table-sorting': '[{"id":"connectTime","desc":true}]',
    };
    return '''
(() => {
  const values = ${jsonEncode(values)};
  const stateKey = '__proxlyConnectionContent';
  if (window[stateKey]) { window[stateKey].apply(values); return; }
  const keys = new Set(${jsonEncode(contentKeys.toList())});
  const pending = {};
  let applying = false, sending = false;
  const originalSet = Storage.prototype.setItem;
  async function flush() {
    const bridge = window.flutter_inappwebview;
    if (sending || !bridge || !bridge.callHandler || !Object.keys(pending).length) return;
    sending = true;
    const patch = {...pending};
    try {
      const ok = await bridge.callHandler('$handlerName', patch);
      if (ok) {
        for (const [key, value] of Object.entries(patch)) {
          if (pending[key] === value) delete pending[key];
        }
      }
    } catch (_) {
      // Retry pending user edits when the bridge or page becomes available.
    } finally { sending = false; }
    if (Object.keys(pending).some(key => pending[key] !== patch[key])) flush();
  }
  function apply(next) {
    applying = true;
    try {
      for (const [key, value] of Object.entries({...next, ...pending})) {
        if (localStorage.getItem(key) === value) continue;
        localStorage.setItem(key, value);
        window.dispatchEvent(new StorageEvent('storage', {
          key, newValue: value, storageArea: window.localStorage
        }));
      }
    } finally { applying = false; }
  }
  Storage.prototype.setItem = function(key, value) {
    const old = this.getItem(key);
    originalSet.call(this, key, value);
    if (this === window.localStorage && !applying && keys.has(String(key)) &&
        String(value).length <= 8192 && old !== String(value)) {
      pending[String(key)] = String(value);
      flush();
    }
  };
  window[stateKey] = {apply};
  window.addEventListener('flutterInAppWebViewPlatformReady', flush);
  document.addEventListener('visibilitychange', flush);
  apply(values);
})();
''';
  }
}
