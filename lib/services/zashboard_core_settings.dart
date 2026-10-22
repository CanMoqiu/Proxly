import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../l10n/app_locale.dart';
import 'zashboard_config_validator.dart';

/// Reads Zashboard's own core-storage API through the authenticated native
/// bridge. Returned data still goes through the common import sanitizer.
class ZashboardCoreSettings {
  static Future<String> read(Uri uri, {http.Client? client}) async {
    final transport = client ?? http.Client();
    try {
      return await (() async {
        final response = await transport
            .send(http.Request('GET', uri)..followRedirects = false);
        if (response.statusCode == 404 || response.statusCode == 405) {
          throw FormatException(tr('内核未保存 Zashboard 配置，或不支持从内核导入。'));
        }
        if (response.statusCode != 200) {
          throw FormatException(tr('无法读取内核中的 Zashboard 配置，请检查连接和访问权限。'));
        }
        final bytes = await ZashboardConfigValidator.readBounded(
            response.stream,
            reportedSize: response.contentLength ?? 0);
        final raw = utf8.decode(bytes);
        final decoded = jsonDecode(raw);
        if (decoded is! Map) throw const FormatException('Invalid settings');
        ZashboardConfigValidator.validateStructure(decoded);
        return raw;
      })()
          .timeout(const Duration(seconds: 15));
    } finally {
      if (client == null) transport.close();
    }
  }
}
