import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../l10n/app_locale.dart';
import 'clash_host_validator.dart';
import 'connection_settings_store.dart';

class ClashConfig {
  final String host;
  final String token;

  const ClashConfig({required this.host, required this.token});

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
}

enum ClashControllerFailureKind {
  notConfigured,
  unauthorized,
  badRequest,
  rejected,
  timeout,
  unreachable,
}

class ClashControllerException implements Exception {
  final ClashControllerFailureKind kind;
  final int? statusCode;
  final String? detail;

  const ClashControllerException(
    this.kind, {
    this.statusCode,
    this.detail,
  });

  @override
  String toString() {
    final status = statusCode == null ? '' : ' HTTP $statusCode';
    final suffix = detail == null ? '' : ': $detail';
    return 'ClashControllerException($kind$status)$suffix';
  }
}

enum ProviderTrafficLevel { healthy, warning, critical }

class ProviderTraffic {
  final String name;
  final int used;
  final int total;
  final int? expire;

  const ProviderTraffic({
    required this.name,
    required this.used,
    required this.total,
    this.expire,
  });

  bool get isUnlimited => total <= 0 && expire == 0;

  int get remaining => total > 0 ? (total - used).clamp(0, total).toInt() : 0;

  double get remainingPercentage =>
      isUnlimited ? 1 : (total > 0 ? remaining / total : 0);

  ProviderTrafficLevel get remainingLevel {
    if (isUnlimited) return ProviderTrafficLevel.healthy;
    return switch (remainingPercentage) {
      > 0.5 => ProviderTrafficLevel.healthy,
      > 0.2 => ProviderTrafficLevel.warning,
      _ => ProviderTrafficLevel.critical,
    };
  }

  @Deprecated('Use remainingPercentage for the shrinking quota bar')
  double get percentage => total > 0 ? used / total : 0;
}

class ConnectionEntry {
  final String id;
  final String sourceIp;
  final String sourcePort;
  final String host;
  final String sniffHost;
  final String destinationIp;
  final String destinationPort;
  final String remoteDestination;
  final String network;
  final String type;
  final String chain;
  final List<String> chainList;
  final List<String> providerChains;
  final String rule;
  final String inboundName;
  final String inboundIp;
  final String inboundPort;
  final String process;
  final String dnsMode;
  final DateTime startTime;
  final int upload;
  final int download;
  final int apiUpSpeed;
  final int apiDownSpeed;

  const ConnectionEntry({
    required this.id,
    required this.sourceIp,
    required this.sourcePort,
    required this.host,
    required this.sniffHost,
    required this.destinationIp,
    required this.destinationPort,
    required this.remoteDestination,
    required this.network,
    required this.type,
    required this.chain,
    required this.chainList,
    required this.providerChains,
    required this.rule,
    required this.inboundName,
    required this.inboundIp,
    required this.inboundPort,
    required this.process,
    required this.dnsMode,
    required this.startTime,
    required this.upload,
    required this.download,
    required this.apiUpSpeed,
    required this.apiDownSpeed,
  });
}

class ClashService {
  static ClashService? _instance;
  static ClashService get instance => _instance ??= ClashService._();
  ClashService._()
      : _client = http.Client(),
        _settingsLoader = ConnectionSettingsStore.instance.load,
        _preserveInjectedConfig = false;

  ClashService.forTesting({
    required ClashConfig config,
    required http.Client client,
    Future<ConnectionSettings> Function()? settingsLoader,
    bool preserveInjectedConfig = true,
  })  : _config = config,
        _client = client,
        _settingsLoader =
            settingsLoader ?? ConnectionSettingsStore.instance.load,
        _preserveInjectedConfig = preserveInjectedConfig;

  ClashConfig? _config;
  final http.Client _client;
  final Future<ConnectionSettings> Function() _settingsLoader;
  final bool _preserveInjectedConfig;

  Future<void> loadConfig() async {
    final settings = await _settingsLoader();
    final host = ClashHostValidator.normalizeAddress(
      settings.host,
    );
    final token = settings.token;
    _config =
        host.isNotEmpty && ClashHostValidator.validationError(host) == null
            ? ClashConfig(host: host, token: token)
            : null;
  }

  Future<void> ensureConfigLoaded() async {
    if (_preserveInjectedConfig) return;
    await loadConfig();
  }

  bool get isConfigured => _config != null;

  Future<void> flushDnsCache() async {
    if (_config == null) throw Exception(tr('未配置 Clash 地址'));
    final uri = Uri.parse('http://${_config!.host}/cache/dns/flush');
    final response = await _client
        .post(uri, headers: _config!.headers)
        .timeout(const Duration(seconds: 5));
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    if (response.statusCode == 401) {
      throw Exception(tr('Token 错误'));
    }
    if (response.statusCode == 404) {
      throw Exception(tr('当前 Clash 内核不支持清理 DNS 缓存'));
    }
    throw Exception(tr('请求失败 ${response.statusCode}'));
  }

  Future<String> getProxyMode() async {
    final data = await _get('/configs', (value) => value);
    final mode = (data['mode'] as String? ?? '').toLowerCase();
    if (!const {'rule', 'global', 'direct'}.contains(mode)) {
      throw Exception(tr('Clash 返回了不支持的代理模式'));
    }
    return mode;
  }

  Future<void> setProxyMode(String mode) async {
    final normalized = mode.toLowerCase();
    if (!const {'rule', 'global', 'direct'}.contains(normalized)) {
      throw ArgumentError.value(mode, 'mode', 'Unsupported proxy mode');
    }
    await _updateConfig({'mode': normalized});
  }

  Future<void> reloadConfig(String remotePath) async {
    final normalized = remotePath.trim().replaceAll('\\', '/');
    if (!normalized.startsWith('/etc/openclash/') ||
        normalized.contains('\u0000') ||
        normalized.split('/').contains('..')) {
      throw ArgumentError.value(
        remotePath,
        'remotePath',
        'Invalid OpenClash runtime configuration path',
      );
    }
    await _reloadConfig({'path': normalized});
  }

  Future<void> _updateConfig(Map<String, dynamic> body) async {
    await ensureConfigLoaded();
    final config = _requireControllerConfig();
    final uri = Uri.parse('http://${config.host}/configs');
    final response = await _sendControllerRequest(
      () => _client.patch(
        uri,
        headers: config.headers,
        body: jsonEncode(body),
      ),
    );
    _ensureControllerSuccess(response);
  }

  Future<void> _reloadConfig(Map<String, dynamic> body) async {
    await ensureConfigLoaded();
    final config = _requireControllerConfig();
    final uri = Uri.parse('http://${config.host}/configs').replace(
      queryParameters: const {'force': 'true'},
    );
    final response = await _sendControllerRequest(
      () => _client.put(
        uri,
        headers: config.headers,
        body: jsonEncode(body),
      ),
    );
    _ensureControllerSuccess(response);
  }

  Future<T> _get<T>(
      String path, T Function(Map<String, dynamic>) parser) async {
    await ensureConfigLoaded();
    final config = _requireControllerConfig();
    final uri = Uri.parse('http://${config.host}$path');
    final response = await _sendControllerRequest(
      () => _client.get(uri, headers: config.headers),
      timeout: const Duration(seconds: 5),
    );
    if (response.statusCode == 200) {
      return parser(jsonDecode(response.body));
    }
    _throwControllerResponse(response);
  }

  ClashConfig _requireControllerConfig() {
    final config = _config;
    if (config != null) return config;
    throw const ClashControllerException(
      ClashControllerFailureKind.notConfigured,
    );
  }

  Future<http.Response> _sendControllerRequest(
    Future<http.Response> Function() request, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw const ClashControllerException(
        ClashControllerFailureKind.timeout,
      );
    } on http.ClientException catch (error) {
      throw ClashControllerException(
        ClashControllerFailureKind.unreachable,
        detail: _sanitizeControllerDetail(error.message),
      );
    } on SocketException catch (error) {
      throw ClashControllerException(
        ClashControllerFailureKind.unreachable,
        detail: _sanitizeControllerDetail(error.message),
      );
    }
  }

  void _ensureControllerSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    _throwControllerResponse(response);
  }

  Never _throwControllerResponse(http.Response response) {
    final kind = switch (response.statusCode) {
      400 => ClashControllerFailureKind.badRequest,
      401 => ClashControllerFailureKind.unauthorized,
      _ => ClashControllerFailureKind.rejected,
    };
    throw ClashControllerException(
      kind,
      statusCode: response.statusCode,
      detail: _responseDetail(response),
    );
  }

  String? _responseDetail(http.Response response) {
    var detail = response.body.trim();
    if (detail.isNotEmpty) {
      try {
        final decoded = jsonDecode(detail);
        if (decoded is Map && decoded['message'] is String) {
          detail = decoded['message'] as String;
        }
      } catch (_) {
        // Plain-text controller responses are useful as-is.
      }
    }
    return _sanitizeControllerDetail(detail);
  }

  String? _sanitizeControllerDetail(String raw) {
    var detail = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (detail.isEmpty) return null;
    final token = _config?.token ?? '';
    if (token.isNotEmpty) {
      detail = detail.replaceAll(token, '[redacted]');
    }
    detail = detail.replaceAll(
      RegExp(r'Bearer\s+\S+', caseSensitive: false),
      'Bearer [redacted]',
    );
    const maxLength = 240;
    if (detail.length > maxLength) {
      detail = '${detail.substring(0, maxLength)}...';
    }
    return detail;
  }

  Future<Map<String, dynamic>> getTrafficSnapshot() async {
    return _get('/connections', (data) {
      final conns = data['connections'] as List? ?? [];
      return {
        'downloadTotal': data['downloadTotal'] ?? 0,
        'uploadTotal': data['uploadTotal'] ?? 0,
        'count': conns.length,
        'connections': conns.map((c) {
          final meta = c['metadata'] as Map<String, dynamic>? ?? {};
          final host = (meta['host'] as String?)?.isNotEmpty == true
              ? meta['host'] as String
              : '${meta['destinationIP'] ?? ''}:${meta['destinationPort'] ?? ''}';
          final network = (meta['network'] as String? ?? 'tcp').toUpperCase();
          final chains = (c['chains'] as List? ?? []).cast<String>();
          final chainStr = chains.length > 1
              ? chains.reversed.join(' → ')
              : chains.isNotEmpty
                  ? chains.first
                  : 'DIRECT';
          final rule = c['rule'] as String? ?? '';
          final rulePayload = c['rulePayload'] as String? ?? '';
          final ruleDisplay = rule.isNotEmpty && rulePayload.isNotEmpty
              ? '$rule: $rulePayload'
              : rule;
          final id = c['id'] as String? ?? '';
          final sourceIp = meta['sourceIP'] as String? ?? '';
          final sourcePort = (meta['sourcePort'] ?? '').toString();
          final destinationIp = meta['destinationIP'] as String? ?? '';
          final destinationPort = (meta['destinationPort'] ?? '').toString();
          final remoteDestination = meta['remoteDestination'] as String? ?? '';
          final sniffHost = meta['sniffHost'] as String? ?? '';
          final type = meta['type'] as String? ?? '';
          final inboundName = meta['inboundName'] as String? ?? '';
          final inboundIp = meta['inboundIP'] as String? ?? '';
          final inboundPort = (meta['inboundPort'] ?? '').toString();
          final process = meta['process'] as String? ?? '';
          final dnsMode = meta['dnsMode'] as String? ?? '';
          final chainList = chains.isEmpty
              ? ['DIRECT']
              : chains.length == 1
                  ? chains.toList()
                  : chains.reversed.toList();
          final providerChains = (c['providerChains'] as List? ?? [])
              .map((e) => e?.toString() ?? '')
              .toList();
          final startStr = c['start'] as String? ?? '';
          final startTime = startStr.isNotEmpty
              ? DateTime.tryParse(startStr) ?? DateTime.now()
              : DateTime.now();
          final upload = c['upload'] as int? ?? 0;
          final download = c['download'] as int? ?? 0;
          final apiUpSpeed = c['uploadSpeed'] as int? ?? 0;
          final apiDownSpeed = c['downloadSpeed'] as int? ?? 0;
          return ConnectionEntry(
            id: id,
            sourceIp: sourceIp,
            sourcePort: sourcePort,
            host: host,
            sniffHost: sniffHost,
            destinationIp: destinationIp,
            destinationPort: destinationPort,
            remoteDestination: remoteDestination,
            network: network,
            type: type,
            chain: chainStr,
            chainList: chainList,
            providerChains: providerChains,
            rule: ruleDisplay,
            inboundName: inboundName,
            inboundIp: inboundIp,
            inboundPort: inboundPort,
            process: process,
            dnsMode: dnsMode,
            startTime: startTime,
            upload: upload,
            download: download,
            apiUpSpeed: apiUpSpeed,
            apiDownSpeed: apiDownSpeed,
          );
        }).toList(),
      };
    });
  }

  Future<void> closeConnection(String id) async {
    await ensureConfigLoaded();
    final config = _requireControllerConfig();
    final uri = Uri.parse(
        'http://${config.host}/connections/${Uri.encodeComponent(id)}');
    final response = await _sendControllerRequest(
      () => _client.delete(uri, headers: config.headers),
      timeout: const Duration(seconds: 5),
    );
    _ensureControllerSuccess(response);
  }

  Future<void> closeAllConnections() async {
    if (_config == null) throw Exception(tr('未配置 Clash 地址'));
    final uri = Uri.parse('http://${_config!.host}/connections');
    final response = await _client
        .delete(uri, headers: _config!.headers)
        .timeout(const Duration(seconds: 5));
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    if (response.statusCode == 401) {
      throw Exception(tr('Token 错误'));
    }
    if (response.statusCode == 404) {
      throw Exception(tr('当前 Clash 内核不支持关闭所有连接'));
    }
    throw Exception(tr('请求失败 ${response.statusCode}'));
  }

  Future<Map<String, String>> getVersionInfo() async {
    final data = await _get('/version', (d) => d);
    final coreVersion = (data['version'] as String?) ?? '--';
    // 查找 OpenClash 专有字段（部分修改版内核附带）
    final openclashVersion = data['openclash_version'] as String? ??
        data['clash_version'] as String?;
    final isMeta = data['meta'] as bool? ?? false;
    final clashLabel = openclashVersion ?? (isMeta ? 'Clash.Meta' : 'Clash');
    return {'clashVersion': clashLabel, 'coreVersion': coreVersion};
  }

  Future<List<ProviderTraffic>> getProviderTraffic() async {
    try {
      return await _get('/providers/proxies', (data) {
        final providers = data['providers'] as Map<String, dynamic>? ?? {};
        final result = <ProviderTraffic>[];
        providers.forEach((name, value) {
          if (value is! Map<String, dynamic>) return;
          final traffic = value['subscriptionInfo'];
          if (traffic is! Map) return;

          final upload =
              _readTrafficBytes(traffic['Upload'] ?? traffic['upload']);
          final download =
              _readTrafficBytes(traffic['Download'] ?? traffic['download']);
          final total = _readTrafficBytes(traffic['Total'] ?? traffic['total']);
          final expire =
              _readOptionalInt(traffic['Expire'] ?? traffic['expire']);
          result.add(
            ProviderTraffic(
              name: name,
              used: upload + download,
              total: total,
              expire: expire,
            ),
          );
        });
        return result;
      });
    } catch (_) {
      return [];
    }
  }

  static int _readTrafficBytes(dynamic value) {
    if (value is num) {
      return value.isFinite && value > 0 ? value.toInt() : 0;
    }
    if (value is String) {
      final parsed = num.tryParse(value.trim());
      return parsed != null && parsed.isFinite && parsed > 0
          ? parsed.toInt()
          : 0;
    }
    return 0;
  }

  static int? _readOptionalInt(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      return value.isFinite && value >= 0 ? value.toInt() : null;
    }
    if (value is String) {
      final parsed = num.tryParse(value.trim());
      return parsed != null && parsed.isFinite && parsed >= 0
          ? parsed.toInt()
          : null;
    }
    return null;
  }
}
