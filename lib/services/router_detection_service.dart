import 'dart:convert';
import 'package:http/http.dart' as http;
import 'clash_host_validator.dart';
import 'router_tool.dart';
import 'ssh_service.dart';

class RouterDetectionResult {
  final RouterTool tool;
  final ProxyCore core;
  final String version;
  final bool ambiguous;
  final bool sshChecked;
  const RouterDetectionResult(
      {required this.tool,
      required this.core,
      required this.version,
      this.ambiguous = false,
      this.sshChecked = false});
}

/// API identity and router package identity are separate evidence sources.
class RouterDetectionService {
  RouterDetectionService(
      {http.Client? client,
      Future<String> Function(String, String, int, String)? ssh})
      : _client = client,
        _ssh = ssh ??
            ((host, password, port, command) => SshService.runText(
                host, password, command,
                port: port, operationTimeout: const Duration(seconds: 10)));
  final http.Client? _client;
  final Future<String> Function(String, String, int, String) _ssh;

  Future<RouterDetectionResult> detect(
      {required String host,
      required String token,
      required String sshPassword,
      required int sshPort}) async {
    final normalized = ClashHostValidator.normalizeAddress(host);
    final error = ClashHostValidator.validationError(normalized);
    if (normalized.isEmpty || error != null) {
      throw ArgumentError('Invalid controller');
    }
    final client = _client ?? http.Client();
    try {
      final request = http.Request(
          'GET', Uri.parse('http://$normalized/version'))
        ..followRedirects = false
        ..headers
            .addAll({if (token.isNotEmpty) 'Authorization': 'Bearer $token'});
      final response =
          await client.send(request).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        throw StateError(response.statusCode == 401
            ? 'unauthorized'
            : 'controller_unavailable');
      }
      final bytes = <int>[];
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 5))) {
        if (bytes.length + chunk.length > 65536) {
          throw const FormatException('Version response too large');
        }
        bytes.addAll(chunk);
      }
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map ||
          data['version'] is! String ||
          (data['version'] as String).isEmpty) {
        throw const FormatException('Not a Clash version response');
      }
      final core = data['meta'] == true ? ProxyCore.mihomo : ProxyCore.clash;
      String? router;
      if (sshPassword.isNotEmpty) {
        try {
          router = await _ssh(
              Uri.parse('http://$normalized').host,
              sshPassword,
              sshPort,
              probeCommandForPort(Uri.parse('http://$normalized').port));
        } catch (_) {
          // API-only access remains useful when SSH is unavailable or declined.
        }
      }
      final running = parseProbe(router ?? '');
      return RouterDetectionResult(
          tool: running.length == 1 ? running.single : RouterTool.generic,
          core: core,
          version: (data['version'] as String)
              .substring(0, (data['version'] as String).length.clamp(0, 120)),
          ambiguous: running.length > 1,
          sshChecked: router != null);
    } finally {
      if (_client == null) client.close();
    }
  }

  static Set<RouterTool> parseProbe(String output) => {
        for (final line in output.split('\n'))
          if (line.trim() == 'openclash=running')
            RouterTool.openClash
          else if (line.trim() == 'nikki=running')
            RouterTool.nikki,
      };

  // A stopped but installed package is not evidence of the active controller.
  static String probeCommandForPort(int port) {
    if (port < 1 || port > 65535) throw ArgumentError('Invalid API port');
    return 'requested_port=$port\n$probeCommand';
  }

  static const probeCommand = r'''
for service in openclash nikki; do
  [ -x "/etc/init.d/$service" ] || continue
  case "$service" in
    openclash) listen="$(uci -q get openclash.config.cn_port)";;
    nikki)
      [ "$(uci -q get nikki.config.core_only)" != 1 ] || continue
      listen="$(uci -q get nikki.mixin.api_listen)"
      if [ -f /etc/nikki/run/config.yaml ] && command -v yq >/dev/null 2>&1; then
        listen="$(yq -r '.external-controller // ""' /etc/nikki/run/config.yaml)"
      fi;;
  esac
  [ "${listen##*:}" = "$requested_port" ] || continue
  if "/etc/init.d/$service" running >/dev/null 2>&1; then
    printf '%s=running\n' "$service"
  fi
done
''';
}
