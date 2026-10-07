import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'connection_settings_store.dart';
import 'web_panel_scroll.dart';
import 'zashboard_config_validator.dart';

class ZashboardSettingsImportResult {
  final String json;
  final int acceptedCount;
  final int skippedCount;

  const ZashboardSettingsImportResult({
    required this.json,
    required this.acceptedCount,
    required this.skippedCount,
  });
}

class ZashboardSettingsImportService {
  ZashboardSettingsImportService._();

  static final instance = ZashboardSettingsImportService._();
  static const preferenceKey = 'webpanel_localstorage';

  static const Set<String> _authStateStorageKeys = {
    'setup/api-list',
    'setup/active-uuid',
  };
  static const Set<String> _managedStorageKeys = {
    WebPanelScroll.managedPreference,
    'config/auto-theme',
    'config/default-theme',
    'config/dark-theme',
    'config/language',
    'config/connection-display-style',
    'config/connection-sort-direction',
    'config/connection-sort-type',
    'config/connection-card-lines',
    'config/use-connecticon-card',
    'config/auto-import-settings',
    'config/import-settings-url',
    'config/auto-upgrade',
    'config/auto-upgrade-core',
    'config/check-upgrade-core',
    'config/is-sidebar-collapsed',
    'config/swipe-in-pages',
    'config/swipe-in-tabs',
    'config/two-columns',
    'config/settings-page-two-columns',
    'config/split-overview-page',
  };
  static const Set<String> _managedStorageKeyPrefixes = {
    'cache/',
    'config/table-',
    'config/connection-',
  };
  static final Object _redacted = Object();
  static final RegExp _sensitiveKeyPattern = RegExp(
    r'(secret|token|password|authorization)',
    caseSensitive: false,
  );
  static final RegExp _languageKeyPattern = RegExp(
    r'(^|[/._-])(lang|language|locale)$',
    caseSensitive: false,
  );
  static final RegExp _sensitiveValuePattern = RegExp(
    r'''["']?(secret|token|password|authorization)["']?\s*[:=]''',
    caseSensitive: false,
  );

  Future<String?> sanitizeSnapshot(String raw) async {
    return (await sanitizeEntries(raw))?.json;
  }

  Future<ZashboardSettingsImportResult?> sanitizeEntries(
    String raw, {
    Map<String, dynamic>? base,
  }) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;

    final token = (await ConnectionSettingsStore.instance.load()).token;
    final sanitized = <String, String>{};
    if (base != null) {
      for (final entry in base.entries) {
        final safeValue = _sanitizeStorageValue(entry.value, token);
        if (safeValue != null) sanitized[entry.key] = safeValue;
      }
    }

    var acceptedCount = 0;
    var skippedCount = 0;
    for (final entry in decoded.entries) {
      final key = entry.key.toString();
      if (_isManagedStorageKey(key)) {
        skippedCount++;
        continue;
      }
      final safeValue = _sanitizeStorageValue(entry.value, token);
      if (safeValue == null) {
        skippedCount++;
        continue;
      }
      sanitized[key] = safeValue;
      acceptedCount++;
    }

    return ZashboardSettingsImportResult(
      json: jsonEncode(sanitized),
      acceptedCount: acceptedCount,
      skippedCount: skippedCount,
    );
  }

  Future<ZashboardSettingsImportResult?> importSnapshot(String raw) async {
    if (utf8.encode(raw).length > ZashboardConfigValidator.maxBytes) {
      throw const FormatException('配置文件超过 5 MB，无法导入');
    }
    dynamic decoded = jsonDecode(raw);
    if (decoded is String) {
      if (utf8.encode(decoded).length > ZashboardConfigValidator.maxBytes) {
        throw const FormatException('配置文件超过 5 MB，无法导入');
      }
      decoded = jsonDecode(decoded);
    }
    if (decoded is! Map) return null;
    ZashboardConfigValidator.validateStructure(decoded);
    final normalizedRaw = jsonEncode(decoded);

    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic>? currentSafe;
    final currentRaw = prefs.getString(preferenceKey);
    if (currentRaw != null && currentRaw.isNotEmpty) {
      try {
        final current = await sanitizeEntries(currentRaw);
        if (current != null) {
          final decodedCurrent = jsonDecode(current.json);
          if (decodedCurrent is Map) {
            currentSafe = Map<String, dynamic>.from(decodedCurrent);
          }
        }
      } catch (_) {
        // A damaged old snapshot must not prevent a clean import.
      }
    }

    final result = await sanitizeEntries(normalizedRaw, base: currentSafe);
    if (result != null && result.acceptedCount > 0) {
      await prefs.setString(preferenceKey, result.json);
    }
    return result;
  }

  static bool _isManagedStorageKey(String key) {
    return _authStateStorageKeys.contains(key) ||
        _sensitiveKeyPattern.hasMatch(key) ||
        _languageKeyPattern.hasMatch(key) ||
        _managedStorageKeys.contains(key) ||
        _managedStorageKeyPrefixes.any(key.startsWith);
  }

  static bool _containsSensitiveJsonValue(dynamic value, String token) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (_sensitiveKeyPattern.hasMatch(entry.key.toString()) ||
            _containsSensitiveJsonValue(entry.value, token)) {
          return true;
        }
      }
      return false;
    }
    if (value is List) {
      return value.any((item) => _containsSensitiveJsonValue(item, token));
    }
    if (value is String) {
      return (token.isNotEmpty && value.contains(token)) ||
          _sensitiveValuePattern.hasMatch(value);
    }
    return false;
  }

  static String? _sanitizeStorageValue(dynamic value, String token) {
    if (value is String) return _sanitizeStorageString(value, token);
    final safeValue =
        _containsSensitiveJsonValue(value, token) ? _redacted : value;
    if (identical(safeValue, _redacted)) return null;
    return _sanitizeStorageString(jsonEncode(safeValue), token);
  }

  static String? _sanitizeStorageString(String value, String token) {
    if ((token.isNotEmpty && value.contains(token)) ||
        _sensitiveValuePattern.hasMatch(value)) {
      return null;
    }
    try {
      final decoded = jsonDecode(value);
      if (_containsSensitiveJsonValue(decoded, token)) return null;
    } catch (_) {
      // Plain string values are valid Zashboard localStorage entries.
    }
    return value;
  }
}
