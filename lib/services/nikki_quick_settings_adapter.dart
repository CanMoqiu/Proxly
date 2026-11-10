import 'openclash_restart_coordinator.dart';
import 'openclash_script_safety.dart';
import 'router_quick_settings.dart';
import 'router_tool.dart';

class NikkiQuickSettingsAdapter {
  NikkiQuickSettingsAdapter(
      {required this.run, required this.restartCoordinator});
  final Future<String> Function(String) run;
  final OpenClashRestartCoordinator restartCoordinator;

  Future<OpenClashQuickSettings> load(
      {Future<String> Function(String)? readRunner}) async {
    final values = <String, String>{};
    for (final line in (await (readRunner ?? run)(readCommand)).split('\n')) {
      final split = line.indexOf('=');
      if (split > 0) {
        values[line.substring(0, split)] = line.substring(split + 1);
      }
    }
    if (values['available'] != '1') throw StateError('Nikki unavailable');
    final runtime = values['runtime'] == '1';
    String? value(String name) =>
        runtime ? values['runtime_$name'] : values[name];
    final variant = switch ('${values['tcp_mode']}/${values['udp_mode']}') {
      'redirect/tproxy' => OpenClashRunVariant.compatibility,
      'tun/tun' => OpenClashRunVariant.tun,
      'redirect/tun' => OpenClashRunVariant.mix,
      _ => null,
    };
    final bypassIp = _flag(values['bypass_china_mainland_ip']);
    final bypassIp6 = _flag(values['bypass_china_mainland_ip6']);
    final unsupported = <OpenClashQuickSettingKey>{
      OpenClashQuickSettingKey.streamUnlock,
      if (bypassIp == null || bypassIp6 == null)
        OpenClashQuickSettingKey.areaBypass,
      if (values['core_only'] == '1') ...OpenClashQuickSettingKey.values,
      if (values['mixin_file_content'] == '1')
        ...OpenClashQuickSettingKey.values
            .where((key) => key != OpenClashQuickSettingKey.areaBypass),
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(values['revision'] ?? ''))
        ...OpenClashQuickSettingKey.values,
      if (value('mode') == null ||
          !['rule', 'global', 'direct'].contains(value('mode')))
        OpenClashQuickSettingKey.proxyMode,
      if (runtime && !['true', 'false'].contains(value('sniffer')))
        OpenClashQuickSettingKey.sniffer,
      if (runtime && !['true', 'false'].contains(value('dns_respect_rules')))
        OpenClashQuickSettingKey.dnsProxy,
    };
    return OpenClashQuickSettings(
      routerTool: RouterTool.nikki,
      backendRevision: values['revision'] ?? '',
      unsupported: unsupported,
      baseMode: switch (value('dns_mode')) {
        'fake-ip' => OpenClashBaseMode.fakeIp,
        'redir-host' => OpenClashBaseMode.redirHost,
        _ => OpenClashBaseMode.unknown,
      },
      runVariant: variant,
      proxyMode: switch (value('mode')) {
        'global' => OpenClashProxyMode.global,
        'direct' => OpenClashProxyMode.direct,
        _ => OpenClashProxyMode.rule,
      },
      areaBypass: bypassIp == null || bypassIp6 == null || bypassIp != bypassIp6
          ? null
          : bypassIp
              ? OpenClashAreaBypass.mainland
              : OpenClashAreaBypass.disabled,
      snifferEnabled: ['1', 'true'].contains(value('sniffer')),
      dnsProxyEnabled: ['1', 'true'].contains(value('dns_respect_rules')),
      streamUnlockEnabled: false,
      streamUnlockSupported: false,
      routerSelfProxyEnabled: values['router_proxy'] == '1',
      rawRunMode: '${values['tcp_mode']}/${values['udp_mode']}',
    );
  }

  static bool? _flag(String? value) => switch (value) {
        '1' => true,
        '' || '0' => false,
        _ => null,
      };

  Future<OpenClashQuickSettingApplyResult> applyChange({
    required OpenClashQuickSettings original,
    required OpenClashQuickSettings desired,
    required OpenClashQuickSettingKey key,
  }) async {
    OpenClashQuickSettingApplyResult failure(String code,
            {bool persisted = false, bool uncertain = false}) =>
        OpenClashQuickSettingApplyResult.failure(
            settings: original,
            errorCode: code,
            rollbackAttempted: false,
            rollbackSucceeded: false,
            changesPersisted: persisted,
            canRetry: persisted,
            stateUncertain: uncertain);
    if (!original.supports(key)) return failure('unsupported_feature');
    if (key == OpenClashQuickSettingKey.areaBypass &&
        (desired.areaBypass == null ||
            desired.areaBypass == OpenClashAreaBypass.overseas)) {
      return failure('unsupported_feature');
    }
    if (key == OpenClashQuickSettingKey.baseMode &&
            desired.baseMode == OpenClashBaseMode.unknown ||
        key == OpenClashQuickSettingKey.runVariant &&
            desired.runVariant == null) {
      return failure('unsupported_feature');
    }
    if (_matches(original, desired, key)) {
      return OpenClashQuickSettingApplyResult.success(original);
    }
    var started = false;
    var persisted = false;
    OpenClashQuickSettings? verified;
    final result = await restartCoordinator.restart(
      reason: OpenClashRestartReason.quickSetting,
      retryPersistence: false,
      beforeRestart: () async {
        // Never replay a write whose result was not confirmed by the remote marker.
        if (started) throw StateError('Refresh Nikki before retrying');
        started = true;
        final output = await run(buildApplyCommand(original, desired, key));
        if (!output.contains('PROXLY_NIKKI_PERSISTED=1')) {
          throw StateError('Nikki persistence was not confirmed');
        }
        persisted = true;
      },
      verify: () async {
        final current = await load();
        if (!_matches(current, desired, key)) {
          throw StateError('Nikki verification failed');
        }
        verified = current;
      },
    );
    return result.success && verified != null
        ? OpenClashQuickSettingApplyResult.success(verified!)
        : failure(persisted ? 'restart_failed' : 'settings_changed',
            persisted: persisted, uncertain: started && !persisted);
  }

  static bool _matches(OpenClashQuickSettings a, OpenClashQuickSettings b,
          OpenClashQuickSettingKey key) =>
      switch (key) {
        OpenClashQuickSettingKey.baseMode => a.baseMode == b.baseMode,
        OpenClashQuickSettingKey.runVariant => a.runVariant == b.runVariant,
        OpenClashQuickSettingKey.proxyMode => a.proxyMode == b.proxyMode,
        OpenClashQuickSettingKey.areaBypass => a.areaBypass == b.areaBypass,
        OpenClashQuickSettingKey.sniffer =>
          a.snifferEnabled == b.snifferEnabled,
        OpenClashQuickSettingKey.dnsProxy =>
          a.dnsProxyEnabled == b.dnsProxyEnabled,
        _ => false,
      };

  static String buildApplyCommand(OpenClashQuickSettings original,
      OpenClashQuickSettings desired, OpenClashQuickSettingKey key) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(original.backendRevision)) {
      throw StateError('Refresh Nikki configuration first');
    }
    if (key == OpenClashQuickSettingKey.areaBypass &&
        (desired.areaBypass == null ||
            desired.areaBypass == OpenClashAreaBypass.overseas)) {
      throw UnsupportedError('No equivalent Nikki bypass option');
    }
    final options = switch (key) {
      OpenClashQuickSettingKey.baseMode => {
          'mixin.dns_mode': desired.baseMode == OpenClashBaseMode.fakeIp
              ? 'fake-ip'
              : 'redir-host'
        },
      OpenClashQuickSettingKey.runVariant => {
          'proxy.tcp_mode': desired.runVariant == OpenClashRunVariant.tun
              ? 'tun'
              : 'redirect',
          if (desired.runVariant != OpenClashRunVariant.compatibility)
            'mixin.tun_enabled': '1',
          'proxy.udp_mode':
              desired.runVariant == OpenClashRunVariant.compatibility
                  ? 'tproxy'
                  : 'tun'
        },
      OpenClashQuickSettingKey.proxyMode => {
          'mixin.mode': desired.proxyMode.name
        },
      OpenClashQuickSettingKey.areaBypass => {
          'proxy.bypass_china_mainland_ip':
              desired.areaBypass == OpenClashAreaBypass.mainland ? '1' : '0',
          'proxy.bypass_china_mainland_ip6':
              desired.areaBypass == OpenClashAreaBypass.mainland ? '1' : '0',
        },
      OpenClashQuickSettingKey.sniffer => {
          'mixin.sniffer': desired.snifferEnabled ? '1' : '0'
        },
      OpenClashQuickSettingKey.dnsProxy => {
          'mixin.dns_respect_rules': desired.dnsProxyEnabled ? '1' : '0'
        },
      _ => throw UnsupportedError('No equivalent Nikki option'),
    };
    final tx =
        '/etc/config/.proxly-nikki-${OpenClashScriptSafety.transactionId()}';
    final changes = options.entries
        .map((e) =>
            'uci -c "\$tx" -t "\$tx/delta" set nikki.${e.key}=\'${e.value}\'')
        .join('\n');
    return '''
set -eu
umask 077
[ -x /etc/init.d/nikki ] && [ -f /etc/config/nikki ] && [ ! -L /etc/config/nikki ]
[ "\$(uci -q get nikki.config.core_only || true)" != 1 ]
check_revision() {
  [ "\$(sha256sum /etc/config/nikki | cut -d ' ' -f1)" = '${original.backendRevision}' ] &&
    [ -z "\$(uci -q changes nikki)" ]
}
check_revision
tx='$tx'
mkdir "\$tx"
trap 'rm -rf "\$tx"' EXIT HUP INT TERM
mkdir "\$tx/delta"
cp /etc/config/nikki "\$tx/nikki"
$changes
uci -c "\$tx" -t "\$tx/delta" commit nikki
chmod 600 "\$tx/nikki"
check_revision
mv -f "\$tx/nikki" /etc/config/nikki
printf '%s\\n' PROXLY_NIKKI_PERSISTED=1
''';
  }

  static const readCommand = r'''
[ -x /etc/init.d/nikki ] && command -v uci >/dev/null 2>&1 || exit 1
printf 'available=1\n'
printf 'revision=%s\n' "$(sha256sum /etc/config/nikki | cut -d ' ' -f1)"
for pair in config.core_only mixin.mixin_file_content mixin.dns_mode mixin.mode mixin.sniffer mixin.dns_respect_rules proxy.tcp_mode proxy.udp_mode proxy.router_proxy proxy.bypass_china_mainland_ip proxy.bypass_china_mainland_ip6; do
  printf '%s=%s\n' "${pair#*.}" "$(uci -q get nikki.$pair || true)"
done
if [ -f /etc/nikki/run/config.yaml ]; then
  printf 'runtime=1\n'
  if command -v yq >/dev/null 2>&1; then
    printf 'runtime_dns_mode=%s\n' "$(yq -r '.dns.enhanced-mode // ""' /etc/nikki/run/config.yaml)"
    printf 'runtime_mode=%s\n' "$(yq -r '.mode // ""' /etc/nikki/run/config.yaml)"
    printf 'runtime_sniffer=%s\n' "$(yq -r '.sniffer.enable // false' /etc/nikki/run/config.yaml)"
    printf 'runtime_dns_respect_rules=%s\n' "$(yq -r '.dns.respect-rules // false' /etc/nikki/run/config.yaml)"
  fi
fi
''';
}
