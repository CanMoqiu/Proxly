import 'dart:async';

import 'package:flutter/foundation.dart';

import 'clash_config_file_service.dart';
import 'clash_service.dart';
import 'openclash_restart_coordinator.dart';
import 'openclash_script_safety.dart';
import 'ssh_service.dart';

enum OpenClashBaseMode { fakeIp, redirHost, unknown }

enum OpenClashRunVariant { compatibility, tun, mix }

enum OpenClashProxyMode { rule, global, direct }

enum OpenClashAreaBypass { mainland, overseas, disabled }

enum OpenClashQuickSettingKey {
  runVariant,
  proxyMode,
  areaBypass,
  sniffer,
  dnsProxy,
  streamUnlock,
}

class OpenClashQuickSettings {
  final OpenClashBaseMode baseMode;
  final OpenClashRunVariant? runVariant;
  final OpenClashProxyMode proxyMode;
  final OpenClashAreaBypass areaBypass;
  final bool snifferEnabled;
  final bool dnsProxyEnabled;
  final bool streamUnlockEnabled;
  final bool routerSelfProxyEnabled;
  final bool streamUnlockSupported;
  final String rawRunMode;

  const OpenClashQuickSettings({
    required this.baseMode,
    required this.runVariant,
    required this.proxyMode,
    required this.areaBypass,
    required this.snifferEnabled,
    required this.dnsProxyEnabled,
    required this.streamUnlockEnabled,
    required this.routerSelfProxyEnabled,
    required this.streamUnlockSupported,
    required this.rawRunMode,
  });

  OpenClashQuickSettings copyWith({
    OpenClashBaseMode? baseMode,
    OpenClashRunVariant? runVariant,
    OpenClashProxyMode? proxyMode,
    OpenClashAreaBypass? areaBypass,
    bool? snifferEnabled,
    bool? dnsProxyEnabled,
    bool? streamUnlockEnabled,
    bool? routerSelfProxyEnabled,
    bool? streamUnlockSupported,
    String? rawRunMode,
  }) {
    return OpenClashQuickSettings(
      baseMode: baseMode ?? this.baseMode,
      runVariant: runVariant ?? this.runVariant,
      proxyMode: proxyMode ?? this.proxyMode,
      areaBypass: areaBypass ?? this.areaBypass,
      snifferEnabled: snifferEnabled ?? this.snifferEnabled,
      dnsProxyEnabled: dnsProxyEnabled ?? this.dnsProxyEnabled,
      streamUnlockEnabled: streamUnlockEnabled ?? this.streamUnlockEnabled,
      routerSelfProxyEnabled:
          routerSelfProxyEnabled ?? this.routerSelfProxyEnabled,
      streamUnlockSupported:
          streamUnlockSupported ?? this.streamUnlockSupported,
      rawRunMode: rawRunMode ?? this.rawRunMode,
    );
  }
}

class OpenClashQuickSettingApplyResult {
  final bool success;
  final OpenClashQuickSettings settings;
  final String? errorCode;
  final String? errorDetail;
  final String? failureStage;
  final bool rollbackAttempted;
  final bool rollbackSucceeded;
  final bool changesPersisted;
  final bool canRetry;

  const OpenClashQuickSettingApplyResult._({
    required this.success,
    required this.settings,
    required this.errorCode,
    required this.errorDetail,
    required this.failureStage,
    required this.rollbackAttempted,
    required this.rollbackSucceeded,
    required this.changesPersisted,
    required this.canRetry,
  });

  const OpenClashQuickSettingApplyResult.success(
    OpenClashQuickSettings settings,
  ) : this._(
        success: true,
        settings: settings,
        errorCode: null,
        errorDetail: null,
        failureStage: null,
        rollbackAttempted: false,
        rollbackSucceeded: false,
        changesPersisted: true,
        canRetry: false,
      );

  const OpenClashQuickSettingApplyResult.failure({
    required OpenClashQuickSettings settings,
    required String errorCode,
    String? errorDetail,
    String? failureStage,
    required bool rollbackAttempted,
    required bool rollbackSucceeded,
    bool changesPersisted = false,
    bool canRetry = false,
  }) : this._(
         success: false,
         settings: settings,
         errorCode: errorCode,
         errorDetail: errorDetail,
         failureStage: failureStage,
         rollbackAttempted: rollbackAttempted,
         rollbackSucceeded: rollbackSucceeded,
         changesPersisted: changesPersisted,
         canRetry: canRetry,
       );
}

typedef OpenClashCommandRunner = Future<String> Function(String command);
typedef OpenClashTransactionIdFactory = String Function();
typedef OpenClashDelay = Future<void> Function(Duration duration);

class _OpenClashCapabilities {
  final bool reported;
  final bool hasUci;
  final bool coreRunning;
  final bool hasOpenClashInit;
  final bool hasRuby;
  final bool hasYamlCompatibility;
  final bool hasRuntimeConfig;
  final String version;

  const _OpenClashCapabilities({
    required this.reported,
    required this.hasUci,
    required this.coreRunning,
    required this.hasOpenClashInit,
    required this.hasRuby,
    required this.hasYamlCompatibility,
    required this.hasRuntimeConfig,
    required this.version,
  });
}

class OpenClashQuickSettingsService {
  final ClashService _clashService;
  final OpenClashRestartCoordinator _restartCoordinator;
  final OpenClashCommandRunner? _commandRunner;
  final OpenClashTransactionIdFactory _transactionIdFactory;
  final OpenClashDelay _delay;

  OpenClashQuickSettingsService({
    ClashService? clashService,
    OpenClashRestartCoordinator? restartCoordinator,
    OpenClashCommandRunner? commandRunner,
    OpenClashTransactionIdFactory? transactionIdFactory,
    OpenClashDelay? delay,
  }) : _clashService = clashService ?? ClashService.instance,
       _restartCoordinator =
           restartCoordinator ?? OpenClashRestartCoordinator.instance,
       _commandRunner = commandRunner,
       _delay = delay ?? Future<void>.delayed,
       _transactionIdFactory =
           transactionIdFactory ?? OpenClashScriptSafety.transactionId;

  Future<OpenClashQuickSettings> load({bool preferLiveProxyMode = true}) async {
    final values = _parseKeyValues(await _run(_readCommand));
    final rawRunMode = values['en_mode'] ?? '';
    var parsedRunMode = _parseRunMode(rawRunMode);
    var proxyMode =
        _parseProxyMode(values['proxy_mode']) ?? OpenClashProxyMode.rule;
    if (preferLiveProxyMode) {
      try {
        proxyMode =
            _parseProxyMode(await _clashService.getProxyMode()) ?? proxyMode;
      } catch (_) {
        // Persisted UCI remains available while the core is offline.
      }
    }

    final runtimeAvailable = values['runtime_config_available'] == '1';
    final runtimeTunValue = values['runtime_tun_enabled'];
    final persistedVariant = parsedRunMode.variant;
    if (runtimeAvailable &&
        runtimeTunValue != null &&
        persistedVariant != null) {
      final expectsTun = persistedVariant != OpenClashRunVariant.compatibility;
      if ((runtimeTunValue == '1') != expectsTun) {
        parsedRunMode = (baseMode: parsedRunMode.baseMode, variant: null);
      }
    }
    return OpenClashQuickSettings(
      baseMode: parsedRunMode.baseMode,
      runVariant: parsedRunMode.variant,
      proxyMode: proxyMode,
      areaBypass: _parseAreaBypass(values['china_ip_route']),
      snifferEnabled: runtimeAvailable
          ? values['runtime_sniffer'] == '1'
          : values['enable_meta_sniffer'] == '1',
      dnsProxyEnabled: runtimeAvailable
          ? values['runtime_dns_proxy'] == '1'
          : values['enable_respect_rules'] == '1',
      streamUnlockEnabled: values['stream_auto_select'] == '1',
      routerSelfProxyEnabled: values['router_self_proxy'] != '0',
      streamUnlockSupported: values['stream_unlock_supported'] == '1',
      rawRunMode: rawRunMode,
    );
  }

  Future<OpenClashQuickSettingApplyResult> applyChange({
    required OpenClashQuickSettings original,
    required OpenClashQuickSettings desired,
    required OpenClashQuickSettingKey key,
  }) async {
    _validateSingleChange(original: original, desired: desired, key: key);
    if (_matches(key, original, desired)) {
      return OpenClashQuickSettingApplyResult.success(original);
    }
    if (key == OpenClashQuickSettingKey.runVariant) {
      return _applyRunVariantWithRestart(original: original, desired: desired);
    }

    final transaction = OpenClashScriptSafety.transactionPath(
      'quick',
      _transactionIdFactory(),
    );
    var prepared = false;
    var rollbackAttempted = false;
    var rollbackSucceeded = false;
    var errorCode = 'unknown';
    String? errorDetail;
    var liveProxyModeChanged = false;
    var applyStarted = false;
    var persistenceCompleted = false;
    String? runtimePath;
    var failureStage = '准备设置';

    try {
      failureStage = '检查 OpenClash 环境';
      final capabilities = await _probeCapabilities();
      _validateCapabilities(capabilities, key);
      _trace(
        transaction.split('_').last,
        key,
        'capabilities',
        'version=${capabilities.version.isEmpty ? 'unknown' : capabilities.version}, '
            'yaml=${capabilities.hasYamlCompatibility ? 'openclash' : 'system'}',
      );
      if (_requiresController(key)) {
        failureStage = '检查 Clash 控制器';
        _trace(transaction.split('_').last, key, 'controller-preflight');
        await _ensureControllerReady();
      }
      if (key == OpenClashQuickSettingKey.proxyMode) {
        failureStage = '更新代理模式运行态';
        _trace(transaction.split('_').last, key, 'live-update');
        await _setLiveProxyMode(desired.proxyMode);
        liveProxyModeChanged = true;
      }

      failureStage = '写入 OpenClash 设置';
      _trace(transaction.split('_').last, key, 'prepare');
      applyStarted = true;
      final output = await _run(
        _buildApplyCommand(
          transaction: transaction,
          original: original,
          desired: desired,
          key: key,
        ),
        operationTimeout: _operationTimeoutFor(key),
      );
      runtimePath = _marker(output, 'PROXLY_RUNTIME_PATH') ?? runtimePath;
      prepared = output.contains('PROXLY_TX_READY=1');
      if (!prepared) {
        throw const _QuickApplyException('incomplete_response');
      }
      persistenceCompleted = !_usesRuntime(key);
      if (_usesRuntime(key)) {
        final path = runtimePath;
        if (path == null || path.isEmpty) {
          throw const _QuickApplyException('runtime_config_missing');
        }
        failureStage = '热重载 Mihomo 配置';
        _trace(transaction.split('_').last, key, 'hot-reload');
        await _reloadRuntimeConfig(path);
        failureStage = '保存 OpenClash 设置';
        final persistOutput = await _run(
          _runtimePersistCommand(
            transaction: transaction,
            desired: desired,
            key: key,
          ),
          operationTimeout: _operationTimeoutFor(key),
        );
        if (_marker(persistOutput, 'PROXLY_PERSISTED') != '1') {
          throw const _QuickApplyException('incomplete_response');
        }
        persistenceCompleted = true;
      }

      failureStage = '验证设置结果';
      _trace(transaction.split('_').last, key, 'verify');
      final actual = await load();
      if (!_matches(key, actual, desired)) {
        throw const _QuickApplyException('verification_failed');
      }
      failureStage = '检查 Mihomo 进程';
      final pidBefore = _marker(output, 'PROXLY_PID_BEFORE');
      final pidAfter = await _readClashPid();
      if (pidBefore == null || pidBefore.isEmpty || pidBefore != pidAfter) {
        throw const _QuickApplyException('pid_changed');
      }
      failureStage = '检查 Mihomo 健康状态';
      await _verifyCoreHealth();

      try {
        await _run(_cleanupCommand(transaction));
      } catch (_) {
        // Temporary files live under /tmp and do not affect the applied state.
      }
      _trace(transaction.split('_').last, key, 'success');
      return OpenClashQuickSettingApplyResult.success(actual);
    } catch (error) {
      errorCode = _errorCode(error);
      errorDetail = _stageDetail(failureStage, _errorDetail(error));
      runtimePath ??= _runtimePathMarker(error);
      final rollbackMarker = _rollbackMarker(error);
      rollbackSucceeded = rollbackMarker == 'success';
      rollbackAttempted =
          rollbackSucceeded || rollbackMarker == 'failed' || prepared;
      final unconfirmedTransaction =
          error is SshCommandException &&
          applyStarted &&
          rollbackMarker == null;

      if ((prepared || unconfirmedTransaction) && !rollbackSucceeded) {
        rollbackAttempted = true;
        try {
          final rollbackOutput = await _run(
            _rollbackCommand(transaction: transaction, key: key),
            operationTimeout: _operationTimeoutFor(key),
          );
          rollbackSucceeded =
              _marker(rollbackOutput, 'PROXLY_ROLLBACK') == 'success';
        } catch (rollbackError) {
          rollbackSucceeded = _rollbackMarker(rollbackError) == 'success';
        }
      }

      if (liveProxyModeChanged) {
        try {
          await _setLiveProxyMode(original.proxyMode);
        } catch (_) {
          rollbackAttempted = true;
          rollbackSucceeded = false;
        }
      }

      if (rollbackSucceeded) {
        try {
          final path = runtimePath;
          if (_usesRuntime(key) && path != null && path.isNotEmpty) {
            await _reloadRuntimeConfig(path);
          }
          await _verifyCoreHealth();
          final restored = await load();
          rollbackSucceeded = _matches(key, restored, original);
        } catch (_) {
          rollbackSucceeded = false;
        }
      }

      OpenClashQuickSettings actual;
      try {
        actual = await load();
      } catch (_) {
        actual = original;
      }
      if (rollbackAttempted && !rollbackSucceeded) {
        errorCode = 'rollback_failed';
      }
      _trace(
        transaction.split('_').last,
        key,
        'failure',
        '$errorCode $errorDetail',
      );
      return OpenClashQuickSettingApplyResult.failure(
        settings: actual,
        errorCode: errorCode,
        errorDetail: errorDetail,
        failureStage: failureStage,
        rollbackAttempted: rollbackAttempted,
        rollbackSucceeded: rollbackSucceeded,
        changesPersisted: persistenceCompleted && !rollbackSucceeded,
      );
    }
  }

  Future<OpenClashQuickSettingApplyResult> _applyRunVariantWithRestart({
    required OpenClashQuickSettings original,
    required OpenClashQuickSettings desired,
  }) async {
    final operationId = _transactionIdFactory();
    var latest = original;
    _trace(operationId, OpenClashQuickSettingKey.runVariant, 'start');

    try {
      final capabilities = await _probeCapabilities();
      _validateCapabilities(capabilities, OpenClashQuickSettingKey.runVariant);
      _trace(
        operationId,
        OpenClashQuickSettingKey.runVariant,
        'capabilities',
        'version=${capabilities.version.isEmpty ? 'unknown' : capabilities.version}',
      );
    } catch (error) {
      const stage = '检查 OpenClash 环境';
      final detail = _stageDetail(stage, _errorDetail(error));
      _trace(
        operationId,
        OpenClashQuickSettingKey.runVariant,
        'failure',
        detail,
      );
      return OpenClashQuickSettingApplyResult.failure(
        settings: original,
        errorCode: _errorCode(error),
        errorDetail: detail,
        failureStage: stage,
        rollbackAttempted: false,
        rollbackSucceeded: false,
      );
    }

    final restartResult = await _restartCoordinator.restart(
      reason: OpenClashRestartReason.quickSetting,
      beforeRestart: () async {
        _trace(operationId, OpenClashQuickSettingKey.runVariant, 'persist');
        final output = await _run(
          _runVariantPersistCommand(
            transaction: OpenClashScriptSafety.transactionPath(
              'run_mode',
              operationId,
            ),
            desired: desired,
          ),
          operationTimeout: const Duration(seconds: 35),
        );
        if (_marker(output, 'PROXLY_PERSISTED') != '1') {
          throw const _QuickApplyException('incomplete_response');
        }
      },
      verify: () async {
        _trace(operationId, OpenClashQuickSettingKey.runVariant, 'verify');
        latest = await load();
        if (!_matches(OpenClashQuickSettingKey.runVariant, latest, desired)) {
          throw const _QuickApplyException('verification_failed');
        }
      },
    );

    if (restartResult.success) {
      _trace(operationId, OpenClashQuickSettingKey.runVariant, 'success');
      return OpenClashQuickSettingApplyResult.success(latest);
    }

    final error =
        restartResult.error ??
        const _QuickApplyException('restart_failed', 'unknown restart error');
    final stage = !restartResult.changesPersisted
        ? '写入 OpenClash 设置'
        : error is _QuickApplyException && error.code == 'verification_failed'
        ? '验证重启后的运行模式'
        : '重启或等待 OpenClash 上线';
    final errorCode = !restartResult.changesPersisted
        ? _errorCode(error)
        : error is _QuickApplyException && error.code == 'verification_failed'
        ? error.code
        : 'restart_failed';
    final detail = _stageDetail(stage, _errorDetail(error));
    _trace(operationId, OpenClashQuickSettingKey.runVariant, 'failure', detail);

    try {
      latest = await load();
    } catch (_) {
      latest = restartResult.changesPersisted ? desired : original;
    }
    return OpenClashQuickSettingApplyResult.failure(
      settings: latest,
      errorCode: errorCode,
      errorDetail: detail,
      failureStage: stage,
      rollbackAttempted: false,
      rollbackSucceeded: false,
      changesPersisted: restartResult.changesPersisted,
      canRetry: _restartCoordinator.canRetry,
    );
  }

  Future<void> _ensureControllerReady() async {
    try {
      await _clashService.getProxyMode();
    } catch (error) {
      final failure = _controllerFailure(error);
      throw _QuickApplyException(failure.code, failure.detail);
    }
  }

  Future<void> _setLiveProxyMode(OpenClashProxyMode mode) async {
    try {
      await _clashService.setProxyMode(mode.name);
    } catch (error) {
      final failure = _controllerFailure(error);
      throw _QuickApplyException(failure.code, failure.detail);
    }
  }

  Future<void> _reloadRuntimeConfig(String path) async {
    try {
      await _clashService.reloadConfig(path);
    } catch (error) {
      final failure = _controllerFailure(error);
      throw _QuickApplyException(failure.code, failure.detail);
    }
  }

  Future<String> _readClashPid() async {
    final output = await _run(_pidCommand);
    return _marker(output, 'PROXLY_PID') ?? '';
  }

  Future<void> _verifyCoreHealth() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _clashService.getProxyMode();
      } catch (error) {
        final failure = _controllerFailure(error);
        throw _QuickApplyException('core_health_failed', failure.detail);
      }
      if (attempt < 2) {
        await _delay(const Duration(milliseconds: 250));
      }
    }
  }

  Future<_OpenClashCapabilities> _probeCapabilities() async {
    final values = _parseKeyValues(await _run(_capabilityCommand));
    final reported = values['PROXLY_CAPS'] == '1';
    return _OpenClashCapabilities(
      reported: reported,
      hasUci: values['cap_uci'] == '1',
      coreRunning: values['cap_core'] == '1',
      hasOpenClashInit: values['cap_init'] == '1',
      hasRuby: values['cap_ruby'] == '1',
      hasYamlCompatibility: values['cap_yaml_compat'] == '1',
      hasRuntimeConfig: values['cap_runtime'] == '1',
      version: values['openclash_version'] ?? '',
    );
  }

  static void _validateCapabilities(
    _OpenClashCapabilities capabilities,
    OpenClashQuickSettingKey key,
  ) {
    if (!capabilities.reported) return;
    if (!capabilities.hasUci) {
      throw const _QuickApplyException('uci_missing');
    }
    if (!capabilities.coreRunning) {
      throw const _QuickApplyException('core_offline');
    }
    if (key == OpenClashQuickSettingKey.runVariant &&
        !capabilities.hasOpenClashInit) {
      throw const _QuickApplyException('restart_unavailable');
    }
    if (!_usesRuntime(key)) return;
    if (!capabilities.hasRuby) {
      throw const _QuickApplyException('ruby_missing');
    }
    if (!capabilities.hasRuntimeConfig) {
      throw const _QuickApplyException('runtime_config_missing');
    }
  }

  static Duration _operationTimeoutFor(OpenClashQuickSettingKey key) {
    return key == OpenClashQuickSettingKey.areaBypass
        ? const Duration(seconds: 330)
        : const Duration(seconds: 80);
  }

  void _validateSingleChange({
    required OpenClashQuickSettings original,
    required OpenClashQuickSettings desired,
    required OpenClashQuickSettingKey key,
  }) {
    if (original.baseMode != desired.baseMode) {
      throw ArgumentError('OpenClash base mode cannot be changed here');
    }
    final changed = OpenClashQuickSettingKey.values
        .where((candidate) => !_matches(candidate, original, desired))
        .toList();
    if (changed.length > 1 || (changed.isNotEmpty && changed.single != key)) {
      throw ArgumentError('applyChange accepts exactly one setting');
    }
    if (key == OpenClashQuickSettingKey.runVariant &&
        (desired.baseMode == OpenClashBaseMode.unknown ||
            desired.runVariant == null)) {
      throw const _QuickApplyException('unsupported_run_mode');
    }
    if (key != OpenClashQuickSettingKey.streamUnlock ||
        !desired.streamUnlockEnabled) {
      return;
    }
    if (desired.proxyMode != OpenClashProxyMode.rule) {
      throw const _QuickApplyException('stream_requires_rule');
    }
    if (!desired.routerSelfProxyEnabled) {
      throw const _QuickApplyException('stream_requires_router_proxy');
    }
    if (!desired.streamUnlockSupported) {
      throw const _QuickApplyException('stream_component_missing');
    }
  }

  static bool _matches(
    OpenClashQuickSettingKey key,
    OpenClashQuickSettings actual,
    OpenClashQuickSettings expected,
  ) {
    return switch (key) {
      OpenClashQuickSettingKey.runVariant =>
        actual.baseMode == expected.baseMode &&
            actual.runVariant == expected.runVariant,
      OpenClashQuickSettingKey.proxyMode =>
        actual.proxyMode == expected.proxyMode,
      OpenClashQuickSettingKey.areaBypass =>
        actual.areaBypass == expected.areaBypass,
      OpenClashQuickSettingKey.sniffer =>
        actual.snifferEnabled == expected.snifferEnabled,
      OpenClashQuickSettingKey.dnsProxy =>
        actual.dnsProxyEnabled == expected.dnsProxyEnabled,
      OpenClashQuickSettingKey.streamUnlock =>
        actual.streamUnlockEnabled == expected.streamUnlockEnabled,
    };
  }

  Future<String> _run(
    String command, {
    Duration operationTimeout = const Duration(seconds: 35),
  }) async {
    final runner = _commandRunner;
    if (runner != null) return runner(command);
    final settings = await ClashConfigFileService.loadSettings();
    return SshService.runText(
      settings.host,
      settings.password,
      command,
      username: settings.username,
      port: settings.port,
      operationTimeout: operationTimeout,
    );
  }

  static bool _usesRuntime(OpenClashQuickSettingKey key) =>
      key == OpenClashQuickSettingKey.sniffer ||
      key == OpenClashQuickSettingKey.dnsProxy;

  static bool _requiresController(OpenClashQuickSettingKey key) =>
      key == OpenClashQuickSettingKey.proxyMode || _usesRuntime(key);

  static bool _usesFirewall(OpenClashQuickSettingKey key) =>
      key == OpenClashQuickSettingKey.areaBypass;

  static String _buildApplyCommand({
    required String transaction,
    required OpenClashQuickSettings original,
    required OpenClashQuickSettings desired,
    required OpenClashQuickSettingKey key,
  }) {
    final usesRuntime = _usesRuntime(key);
    final usesFirewall = _usesFirewall(key);
    final body = switch (key) {
      OpenClashQuickSettingKey.runVariant => throw StateError(
        'Run mode uses the restart flow',
      ),
      OpenClashQuickSettingKey.proxyMode => _proxyModeBody(desired),
      OpenClashQuickSettingKey.areaBypass => _areaBypassBody(desired),
      OpenClashQuickSettingKey.sniffer => _snifferBody(desired),
      OpenClashQuickSettingKey.dnsProxy => _dnsProxyBody(desired),
      OpenClashQuickSettingKey.streamUnlock => _streamUnlockBody(
        desired.streamUnlockEnabled,
      ),
    };
    return _applyTemplate
        .replaceAll('__RUNTIME_HELPERS__', _runtimeResolverShell)
        .replaceAll('__TX__', transaction)
        .replaceAll(
          '__CREATE_TX__',
          OpenClashScriptSafety.createTransactionDirectory,
        )
        .replaceAll('__USES_RUNTIME__', usesRuntime ? '1' : '0')
        .replaceAll('__USES_FIREWALL__', usesFirewall ? '1' : '0')
        .replaceAll('__USES_PROXY__', '0')
        .replaceAll('__OLD_PROXY_MODE__', original.proxyMode.name)
        .replaceAll('__APPLY_BODY__', body);
  }

  static String _rollbackCommand({
    required String transaction,
    required OpenClashQuickSettingKey key,
  }) {
    final usesRuntime = _usesRuntime(key);
    final usesFirewall = _usesFirewall(key);
    return _rollbackTemplate
        .replaceAll('__TX__', transaction)
        .replaceAll(
          '__CREATE_TX__',
          OpenClashScriptSafety.createTransactionDirectory,
        )
        .replaceAll('__USES_RUNTIME__', usesRuntime ? '1' : '0')
        .replaceAll('__USES_FIREWALL__', usesFirewall ? '1' : '0')
        .replaceAll('__USES_PROXY__', '0');
  }

  static String _cleanupCommand(String transaction) =>
      "rm -f '$transaction.uci' '$transaction.runtime' "
      "'$transaction.runtime_path' '$transaction.proxy_mode' "
      "'$transaction.pid' '$transaction.http'; "
      "rmdir '${transaction.substring(0, transaction.lastIndexOf('/'))}' 2>/dev/null || true";

  static String _proxyModeBody(OpenClashQuickSettings desired) =>
      '''
uci set openclash.config.proxy_mode='${desired.proxyMode.name}' || fail persist_failed
set_overwrite proxy_mode '${desired.proxyMode.name}' || fail persist_failed
uci commit openclash || fail persist_failed
''';

  static String _areaBypassBody(OpenClashQuickSettings desired) {
    final value = _areaBypassValue(desired.areaBypass);
    return '''
ipv6_enable="\$(uci -q get openclash.config.ipv6_enable 2>/dev/null || echo 0)"
uci set openclash.config.china_ip_route='$value' || fail persist_failed
set_overwrite china_ip_route '$value' || fail persist_failed
if [ "\$ipv6_enable" != '0' ]; then
  uci set openclash.config.china_ip6_route='$value' || fail persist_failed
  set_overwrite china_ip6_route '$value' || fail persist_failed
fi
uci commit openclash || fail persist_failed
reload_firewall || fail firewall_reload_failed
''';
  }

  static String _snifferBody(OpenClashQuickSettings desired) {
    final value = desired.snifferEnabled ? '1' : '0';
    return _runtimeRubyCommand(
      value: value,
      body: r'''
config = load_config(path)
if enabled
  config["sniffer"] = {
    "enable" => true,
    "parse-pure-ip" => true,
    "override-destination" => false,
  }
  custom_path = "/etc/openclash/custom/openclash_custom_sniffer.yaml"
  if File.exist?(custom_path)
    begin
      custom = load_config(custom_path)
      if custom.is_a?(Hash) && custom["sniffer"].is_a?(Hash)
        config["sniffer"].merge!(custom["sniffer"])
      end
    rescue Exception
    end
  end
  config["sniffer"]["sniff"] ||= {
    "QUIC" => {"ports" => [443]},
    "TLS" => {"ports" => [443, "8443"]},
    "HTTP" => {"ports" => [80, "8080-8880"], "override-destination" => true},
  }
  config["sniffer"]["force-domain"] ||= ["+.netflix.com", "+.nflxvideo.net", "+.amazonaws.com"]
  config["sniffer"]["skip-domain"] ||= ["+.apple.com", "Mijia Cloud", "dlg.io.mi.com"]
else
  config["sniffer"] = {"enable" => false}
end
write_config(path, config)
''',
    );
  }

  static String _dnsProxyBody(OpenClashQuickSettings desired) {
    final value = desired.dnsProxyEnabled ? '1' : '0';
    return _runtimeRubyCommand(
      value: value,
      body: r'''
config = load_config(path)
config["dns"] = {} unless config["dns"].is_a?(Hash)
config["dns"]["respect-rules"] = enabled
if enabled && (!config["dns"]["proxy-server-nameserver"].is_a?(Array) || config["dns"]["proxy-server-nameserver"].empty?)
  config["dns"]["proxy-server-nameserver"] = ["114.114.114.114", "119.29.29.29", "8.8.8.8", "1.1.1.1"]
end
write_config(path, config)
''',
    );
  }

  static String _runtimeRubyCommand({
    required String value,
    required String body,
  }) {
    final script = '$_runtimeRubyPrelude\n$body\n$_runtimeRubySuffix';
    return '''
$_openClashRubyShellFunction
export PROXLY_VALUE='$value'
export PROXLY_RUNTIME="\$runtime_path"
openclash_ruby -E UTF-8 -e '$script' || fail runtime_modify_failed
''';
  }

  static String _runtimePersistCommand({
    required String transaction,
    required OpenClashQuickSettings desired,
    required OpenClashQuickSettingKey key,
  }) {
    final body = switch (key) {
      OpenClashQuickSettingKey.sniffer =>
        '''
uci set openclash.config.enable_meta_sniffer='${desired.snifferEnabled ? '1' : '0'}' || fail persist_failed
uci set openclash.config.enable_meta_sniffer_pure_ip='${desired.snifferEnabled ? '1' : '0'}' || fail persist_failed
set_overwrite enable_meta_sniffer '${desired.snifferEnabled ? '1' : '0'}' || fail persist_failed
set_overwrite enable_meta_sniffer_pure_ip '${desired.snifferEnabled ? '1' : '0'}' || fail persist_failed
''',
      OpenClashQuickSettingKey.dnsProxy =>
        '''
uci set openclash.config.enable_respect_rules='${desired.dnsProxyEnabled ? '1' : '0'}' || fail persist_failed
set_overwrite enable_respect_rules '${desired.dnsProxyEnabled ? '1' : '0'}' || fail persist_failed
''',
      _ => throw StateError('Only runtime settings have a persist phase'),
    };
    return '''
set -eu
tx='$transaction'

fail() {
  echo "PROXLY_ERROR=\$1" >&2
  return 1
}

set_overwrite() {
  option="\$1"
  value="\$2"
  if uci -q show 'openclash.@overwrite[0]' >/dev/null 2>&1; then
    uci set "openclash.@overwrite[0].\$option=\$value"
  fi
}

[ -f "\$tx.uci" ] || fail backup_missing
$body
uci commit openclash || fail persist_failed
printf 'PROXLY_PERSISTED=1\n'
''';
  }

  static String _runVariantPersistCommand({
    required String transaction,
    required OpenClashQuickSettings desired,
  }) {
    final runMode = _runModeValue(desired.baseMode, desired.runVariant);
    return '''
set -eu
tx='$transaction'
${OpenClashScriptSafety.createTransactionDirectory}
armed=0

cleanup() {
  rm -f "\$tx.uci"
  rmdir "\${tx%/*}" 2>/dev/null || true
}

restore_on_exit() {
  rc="\$?"
  if [ "\$armed" = '1' ] && [ "\$rc" -ne 0 ]; then
    trap - EXIT
    uci import openclash < "\$tx.uci" >/dev/null 2>&1 || true
    uci commit openclash >/dev/null 2>&1 || true
    cleanup
    exit "\$rc"
  fi
}

fail() {
  echo "PROXLY_ERROR=\$1" >&2
  return 1
}

set_overwrite() {
  option="\$1"
  value="\$2"
  if uci -q show 'openclash.@overwrite[0]' >/dev/null 2>&1; then
    uci set "openclash.@overwrite[0].\$option=\$value"
  fi
}

command -v uci >/dev/null 2>&1 || { echo 'PROXLY_ERROR=uci_missing' >&2; exit 31; }
[ -x /etc/init.d/openclash ] || { echo 'PROXLY_ERROR=restart_unavailable' >&2; exit 31; }
uci export openclash > "\$tx.uci" || { echo 'PROXLY_ERROR=backup_failed' >&2; cleanup; exit 31; }
armed=1
trap restore_on_exit EXIT
uci set openclash.config.en_mode='$runMode' || fail persist_failed
set_overwrite en_mode '$runMode' || fail persist_failed
uci commit openclash || fail persist_failed
armed=0
trap - EXIT
cleanup
printf 'PROXLY_PERSISTED=1\n'
''';
  }

  static String _streamUnlockBody(bool enabled) {
    if (!enabled) {
      return '''
uci set openclash.config.stream_auto_select='0' || fail persist_failed
uci commit openclash || fail persist_failed
''';
    }
    return '''
[ "\$(uci -q get openclash.config.proxy_mode 2>/dev/null || echo rule)" = 'rule' ] || fail stream_requires_rule
[ "\$(uci -q get openclash.config.router_self_proxy 2>/dev/null || echo 1)" = '1' ] || fail stream_requires_router_proxy
stream_unlock_component=''
for candidate in /usr/share/openclash/openclash_streaming_unlock.lua /usr/share/openclash/openclash_stream_unlock.lua /etc/openclash/openclash_streaming_unlock.lua /etc/openclash/custom/openclash_streaming_unlock.lua
do
  if [ -f "\$candidate" ]; then
    stream_unlock_component="\$candidate"
    break
  fi
done
if [ -z "\$stream_unlock_component" ] && command -v find >/dev/null 2>&1; then
  stream_unlock_component="\$(find /usr/share/openclash /etc/openclash -maxdepth 4 -type f -name '*stream*unlock*.lua' 2>/dev/null | head -n 1)"
fi
[ -n "\$stream_unlock_component" ] || fail stream_component_missing
uci set openclash.config.stream_auto_select='1' || fail persist_failed
uci -q get openclash.config.stream_auto_select_interval >/dev/null 2>&1 || uci set openclash.config.stream_auto_select_interval='10' || fail persist_failed
uci -q get openclash.config.stream_auto_select_logic >/dev/null 2>&1 || uci set openclash.config.stream_auto_select_logic='Urltest' || fail persist_failed
uci -q get openclash.config.stream_auto_select_expand_group >/dev/null 2>&1 || uci set openclash.config.stream_auto_select_expand_group='0' || fail persist_failed
uci set openclash.config.stream_auto_select_netflix='1' || fail persist_failed
uci -q get openclash.config.stream_auto_select_group_key_netflix >/dev/null 2>&1 || uci set openclash.config.stream_auto_select_group_key_netflix='Netflix|奈飞' || fail persist_failed
uci set openclash.config.stream_auto_select_disney='1' || fail persist_failed
uci -q get openclash.config.stream_auto_select_group_key_disney >/dev/null 2>&1 || uci set openclash.config.stream_auto_select_group_key_disney='Disney|迪士尼' || fail persist_failed
uci set openclash.config.stream_auto_select_hbo_max='1' || fail persist_failed
uci -q get openclash.config.stream_auto_select_group_key_hbo_max >/dev/null 2>&1 || uci set openclash.config.stream_auto_select_group_key_hbo_max='HBO|HBO Max' || fail persist_failed
uci commit openclash || fail persist_failed
''';
  }

  static String _runModeValue(
    OpenClashBaseMode baseMode,
    OpenClashRunVariant? variant,
  ) {
    if (baseMode == OpenClashBaseMode.unknown || variant == null) {
      throw const _QuickApplyException('unsupported_run_mode');
    }
    final base = baseMode == OpenClashBaseMode.fakeIp
        ? 'fake-ip'
        : 'redir-host';
    final suffix = switch (variant) {
      OpenClashRunVariant.compatibility => '',
      OpenClashRunVariant.tun => '-tun',
      OpenClashRunVariant.mix => '-mix',
    };
    return '$base$suffix';
  }

  static String _areaBypassValue(OpenClashAreaBypass area) => switch (area) {
    OpenClashAreaBypass.disabled => '0',
    OpenClashAreaBypass.mainland => '1',
    OpenClashAreaBypass.overseas => '2',
  };

  static Map<String, String> _parseKeyValues(String output) {
    final result = <String, String>{};
    for (final rawLine in output.split('\n')) {
      final line = rawLine.trim();
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      result[line.substring(0, separator)] = line
          .substring(separator + 1)
          .trim();
    }
    return result;
  }

  static String? _marker(String output, String name) =>
      _parseKeyValues(output)[name];

  static String? _rollbackMarker(Object error) {
    if (error is! SshCommandException) return null;
    return _marker('${error.stdout}\n${error.stderr}', 'PROXLY_ROLLBACK');
  }

  static String? _runtimePathMarker(Object error) {
    if (error is! SshCommandException) return null;
    return _marker('${error.stdout}\n${error.stderr}', 'PROXLY_RUNTIME_PATH');
  }

  static String _errorCode(Object error) {
    if (error is _QuickApplyException) return error.code;
    if (error is SshCommandException) {
      return _marker('${error.stdout}\n${error.stderr}', 'PROXLY_ERROR') ??
          'ssh_command_failed';
    }
    if (error is SshPasswordRequiredException) return 'ssh_password_required';
    return 'unknown';
  }

  static String? _errorDetail(Object error) {
    if (error is _QuickApplyException) return error.detail;
    if (error is SshCommandException) {
      final output = '${error.stderr}\n${error.stdout}';
      final marker = _marker(output, 'PROXLY_DETAIL');
      if (marker != null && marker.trim().isNotEmpty) {
        return _sanitizeDiagnosticDetail(marker);
      }
      final sanitized = _sanitizeDiagnosticDetail(output);
      final exit = error.exitSignal == null
          ? 'SSH exit ${error.exitCode ?? 'unknown'}'
          : 'SSH signal ${error.exitSignal}';
      return sanitized.isEmpty ? exit : '$exit: $sanitized';
    }
    if (error is TimeoutException) return 'operation timed out';
    final sanitized = _sanitizeDiagnosticDetail(error.toString());
    return sanitized.isEmpty ? null : sanitized;
  }

  static String _sanitizeDiagnosticDetail(String raw) {
    var value = OpenClashScriptSafety.redactCredentials(raw)
        .replaceAll(
          RegExp(r'authorization:\s*bearer\s+\S+', caseSensitive: false),
          'Authorization: Bearer [redacted]',
        )
        .replaceAll(
          RegExp(r'bearer\s+\S+', caseSensitive: false),
          'Bearer [redacted]',
        )
        .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), '[url]')
        .replaceAll(RegExp(r'/etc/openclash/[^\s:]+'), '[openclash-path]')
        .replaceAll(RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b'), '[host]')
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    const markers = <String>[
      'PROXLY_ERROR=',
      'PROXLY_DETAIL=',
      'PROXLY_ROLLBACK=',
      'PROXLY_RUNTIME_PATH=',
      'PROXLY_TX_READY=',
      'PROXLY_PID_BEFORE=',
    ];
    for (final marker in markers) {
      value = value.replaceAll(RegExp('${RegExp.escape(marker)}\\S*'), '');
    }
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value.length > 240) value = '${value.substring(0, 240)}...';
    return value;
  }

  static String _stageDetail(String stage, String? detail) {
    final normalized = detail?.trim();
    return normalized == null || normalized.isEmpty
        ? stage
        : '$stage：$normalized';
  }

  static ({String code, String? detail}) _controllerFailure(Object error) {
    if (error is! ClashControllerException) {
      return (code: 'controller_api_failed', detail: null);
    }
    final code = switch (error.kind) {
      ClashControllerFailureKind.notConfigured => 'controller_not_configured',
      ClashControllerFailureKind.unauthorized => 'controller_unauthorized',
      ClashControllerFailureKind.badRequest => 'controller_bad_request',
      ClashControllerFailureKind.rejected => 'controller_rejected',
      ClashControllerFailureKind.timeout => 'controller_timeout',
      ClashControllerFailureKind.unreachable => 'controller_unreachable',
    };
    final status = error.statusCode == null ? null : 'HTTP ${error.statusCode}';
    final detail = switch ((status, error.detail)) {
      (final String status, final String detail) => '$status: $detail',
      (final String status, null) => status,
      (null, final String detail) => detail,
      _ => null,
    };
    return (code: code, detail: detail);
  }

  static ({OpenClashBaseMode baseMode, OpenClashRunVariant? variant})
  _parseRunMode(String value) {
    final baseMode = value.startsWith('fake-ip')
        ? OpenClashBaseMode.fakeIp
        : value.startsWith('redir-host')
        ? OpenClashBaseMode.redirHost
        : OpenClashBaseMode.unknown;
    if (baseMode == OpenClashBaseMode.unknown) {
      return (baseMode: baseMode, variant: null);
    }
    final variant = value.endsWith('-tun')
        ? OpenClashRunVariant.tun
        : value.endsWith('-mix')
        ? OpenClashRunVariant.mix
        : OpenClashRunVariant.compatibility;
    return (baseMode: baseMode, variant: variant);
  }

  static OpenClashProxyMode? _parseProxyMode(String? value) {
    return switch (value?.toLowerCase()) {
      'rule' => OpenClashProxyMode.rule,
      'global' => OpenClashProxyMode.global,
      'direct' => OpenClashProxyMode.direct,
      _ => null,
    };
  }

  static OpenClashAreaBypass _parseAreaBypass(String? value) {
    return switch (value) {
      '1' => OpenClashAreaBypass.mainland,
      '2' => OpenClashAreaBypass.overseas,
      _ => OpenClashAreaBypass.disabled,
    };
  }

  static void _trace(
    String operationId,
    OpenClashQuickSettingKey key,
    String event, [
    String? detail,
  ]) {
    if (!kDebugMode) return;
    final suffix = detail == null || detail.trim().isEmpty
        ? ''
        : ' detail=${_sanitizeDiagnosticDetail(detail)}';
    debugPrint(
      '[OpenClashQuickSettings] operation=$operationId '
      'key=${key.name} event=$event$suffix',
    );
  }

  static const _openClashRubyShellFunction = r'''
openclash_ruby() {
  if [ -f /usr/share/openclash/YAML.rb ]; then
    ruby -ryaml -rYAML -I /usr/share/openclash "$@"
  else
    ruby -ryaml "$@"
  fi
}
''';

  static const _runtimeRubyPrelude =
      OpenClashScriptSafety.rubyYamlGuard +
      r'''
def load_config(config_path)
  value = YAML.load_file(config_path)
  value = {} if value.nil?
  raise "configuration root is not a map" unless value.is_a?(Hash)
  value
end

def write_config(config_path, value)
  if YAML.respond_to?(:dump_to_path)
    YAML.dump(value, config_path)
    return
  end
  real_path = File.symlink?(config_path) ? File.realpath(config_path) : config_path
  temp_path = "#{real_path}.proxly.#{Process.pid}"
  mode = File.exist?(real_path) ? File.stat(real_path).mode & 07777 : nil
  created = false
  begin
    File.open(temp_path, File::WRONLY | File::CREAT | File::EXCL, 0600) do |file|
      created = true
      file.write(YAML.dump(value))
      file.flush
      begin
        file.fsync
      rescue Exception
      end
    end
    File.chmod(mode, temp_path) unless mode.nil?
    File.rename(temp_path, real_path)
  ensure
    File.unlink(temp_path) if created && File.exist?(temp_path)
  end
end

begin
  path = ENV.fetch("PROXLY_RUNTIME")
  enabled = ENV.fetch("PROXLY_VALUE") == "1"
''';

  static const _runtimeRubySuffix = r'''
rescue Exception => error
  detail = "#{error.class}: #{error.message}".gsub(/[\r\n]+/, " ")[0, 240]
  warn "PROXLY_DETAIL=#{detail}"
  exit 1
end
''';

  static const _pidCommand = r'''
pid="$(pidof clash 2>/dev/null | tr ' ' '\n' | sort -n | tr '\n' ' ' | sed 's/ *$//')"
printf 'PROXLY_PID=%s\n' "$pid"
''';

  static const _runtimeResolverShell = r'''
effective_uci_get() {
  option="$1"
  uci -q get "openclash.@overwrite[0].$option" 2>/dev/null ||
    uci -q get "openclash.config.$option" 2>/dev/null
}

validate_runtime_path() {
  candidate="$1"
  [ -n "$candidate" ] || return 1
  if command -v readlink >/dev/null 2>&1; then
    resolved="$(readlink -f "$candidate" 2>/dev/null || true)"
    [ -n "$resolved" ] && candidate="$resolved"
  fi
  case "$candidate" in
    /etc/openclash/*) ;;
    *) return 1 ;;
  esac
  [ -f "$candidate" ] || return 1
  printf '%s\n' "$candidate"
}

runtime_path_from_process() {
  clash_pid="$(pidof clash 2>/dev/null | tr ' ' '\n' | sort -n | head -n 1)"
  [ -n "$clash_pid" ] && [ -r "/proc/$clash_pid/cmdline" ] || return 1
  tr '\000' '\n' < "/proc/$clash_pid/cmdline" | awk '
    previous == "-f" { print; exit }
    /^-f=/ { sub(/^-f=/, ""); print; exit }
    { previous = $0 }
  '
}

resolve_runtime_path() {
  process_path="$(runtime_path_from_process 2>/dev/null || true)"
  if [ -n "$process_path" ]; then
    validate_runtime_path "$process_path" && return 0
  fi
  configured_path="$(effective_uci_get config_path 2>/dev/null || true)"
  [ -n "$configured_path" ] || return 1
  validate_runtime_path "/etc/openclash/$(basename "$configured_path")"
}
''';

  static const _capabilityCommand =
      _runtimeResolverShell +
      r'''
has_uci=0
core_running=0
has_init=0
has_ruby=0
has_yaml_compat=0
runtime_available=0
openclash_version=''

command -v uci >/dev/null 2>&1 && has_uci=1
[ -n "$(pidof clash 2>/dev/null)" ] && core_running=1
[ -x /etc/init.d/openclash ] && has_init=1
command -v ruby >/dev/null 2>&1 && has_ruby=1
[ -f /usr/share/openclash/YAML.rb ] && has_yaml_compat=1
if [ "$has_uci" = '1' ]; then
  runtime_path="$(resolve_runtime_path 2>/dev/null || true)"
  [ -n "$runtime_path" ] && runtime_available=1
fi
if command -v opkg >/dev/null 2>&1; then
  openclash_version="$(opkg status luci-app-openclash 2>/dev/null | awk -F ': ' '/^Version:/{print $2; exit}')"
elif command -v apk >/dev/null 2>&1; then
  openclash_version="$(apk info -v luci-app-openclash 2>/dev/null | head -n 1)"
fi
printf 'PROXLY_CAPS=1\n'
printf 'cap_uci=%s\n' "$has_uci"
printf 'cap_core=%s\n' "$core_running"
printf 'cap_init=%s\n' "$has_init"
printf 'cap_ruby=%s\n' "$has_ruby"
printf 'cap_yaml_compat=%s\n' "$has_yaml_compat"
printf 'cap_runtime=%s\n' "$runtime_available"
printf 'openclash_version=%s\n' "$openclash_version"
''';

  static const _readCommand =
      _runtimeResolverShell +
      _openClashRubyShellFunction +
      r'''
for option in en_mode proxy_mode china_ip_route enable_meta_sniffer enable_respect_rules stream_auto_select router_self_proxy; do
  value="$(effective_uci_get "$option" 2>/dev/null || true)"
  printf '%s=%s\n' "$option" "$value"
done
stream_unlock_component=''
for candidate in \
  /usr/share/openclash/openclash_streaming_unlock.lua \
  /usr/share/openclash/openclash_stream_unlock.lua \
  /etc/openclash/openclash_streaming_unlock.lua \
  /etc/openclash/custom/openclash_streaming_unlock.lua
do
  if [ -f "$candidate" ]; then
    stream_unlock_component="$candidate"
    break
  fi
done
if [ -z "$stream_unlock_component" ] && command -v find >/dev/null 2>&1; then
  stream_unlock_component="$(find /usr/share/openclash /etc/openclash -maxdepth 4 -type f -name '*stream*unlock*.lua' 2>/dev/null | head -n 1)"
fi
if [ -n "$stream_unlock_component" ]; then
  printf 'stream_unlock_supported=1\n'
else
  printf 'stream_unlock_supported=0\n'
fi
runtime_path="$(resolve_runtime_path 2>/dev/null || true)"
if [ -n "$runtime_path" ] && [ -f "$runtime_path" ] && command -v ruby >/dev/null 2>&1; then
  export RUNTIME_CONFIG_PATH="$runtime_path"
  openclash_ruby -E UTF-8 -e '
''' +
      OpenClashScriptSafety.rubyYamlGuard +
      r'''
    path = ENV.fetch("RUNTIME_CONFIG_PATH")
    config = YAML.load_file(path)
    config ||= {}
    puts "runtime_config_available=1"
    puts "runtime_tun_enabled=#{config.dig("tun", "enable") == true ? 1 : 0}"
    puts "runtime_sniffer=#{config.dig("sniffer", "enable") == true ? 1 : 0}"
    puts "runtime_dns_proxy=#{config.dig("dns", "respect-rules") == true ? 1 : 0}"
  ' 2>/dev/null || printf 'runtime_config_available=0\n'
else
  printf 'runtime_config_available=0\n'
fi
''';

  static const _applyTemplate = r'''
set -eu
__RUNTIME_HELPERS__
tx='__TX__'
uses_runtime='__USES_RUNTIME__'
uses_firewall='__USES_FIREWALL__'
uses_proxy='__USES_PROXY__'
__CREATE_TX__
armed=0

current_pid() {
  pidof clash 2>/dev/null | tr ' ' '\n' | sort -n | tr '\n' ' ' | sed 's/ *$//'
}

cleanup() {
  rm -f "$tx.uci" "$tx.runtime" "$tx.runtime_path" "$tx.proxy_mode" "$tx.pid" "$tx.http"
rmdir "${tx%/*}" 2>/dev/null || true
}

reload_firewall() {
  if /etc/init.d/openclash reload revert >/dev/null 2>&1 &&
      /etc/init.d/openclash reload restore >/dev/null 2>&1; then
    return 0
  fi
  /etc/init.d/openclash reload >/dev/null 2>&1 && return 0
  if command -v fw4 >/dev/null 2>&1; then
    fw4 reload >/dev/null 2>&1 && return 0
  fi
  if [ -x /etc/init.d/firewall ]; then
    /etc/init.d/firewall reload >/dev/null 2>&1 && return 0
  fi
  return 1
}

set_overwrite() {
  option="$1"
  value="$2"
  if uci -q show 'openclash.@overwrite[0]' >/dev/null 2>&1; then
    uci set "openclash.@overwrite[0].$option=$value"
  fi
}

restore_transaction() {
  set +e
  ok=1
  uci import openclash < "$tx.uci" >/dev/null 2>&1 && uci commit openclash >/dev/null 2>&1 || ok=0
  if [ "$uses_runtime" = '1' ]; then
    runtime_path="$(cat "$tx.runtime_path" 2>/dev/null)"
    cp -f "$tx.runtime" "$runtime_path" >/dev/null 2>&1 || ok=0
  fi
  if [ "$uses_firewall" = '1' ]; then
    reload_firewall >/dev/null 2>&1 || ok=0
  fi
  pid_before="$(cat "$tx.pid" 2>/dev/null)"
  [ -n "$pid_before" ] && [ "$pid_before" = "$(current_pid)" ] || ok=0
  if [ "$ok" = '1' ]; then
    echo 'PROXLY_ROLLBACK=success' >&2
  else
    echo 'PROXLY_ROLLBACK=failed' >&2
  fi
  return "$((1-ok))"
}

rollback_on_exit() {
  rc="$?"
  if [ "$armed" = '1' ] && [ "$rc" -ne 0 ]; then
    trap - EXIT
    restore_transaction
    cleanup
    exit 40
  fi
}

fail() {
  echo "PROXLY_ERROR=$1" >&2
  return 1
}

command -v uci >/dev/null 2>&1 || { echo 'PROXLY_ERROR=uci_missing' >&2; exit 31; }
pid_before="$(current_pid)"
[ -n "$pid_before" ] || { echo 'PROXLY_ERROR=core_offline' >&2; exit 31; }
uci export openclash > "$tx.uci" || { echo 'PROXLY_ERROR=backup_failed' >&2; cleanup; exit 31; }
printf '%s' "$pid_before" > "$tx.pid"

runtime_path=''
if [ "$uses_runtime" = '1' ]; then
  command -v ruby >/dev/null 2>&1 || { echo 'PROXLY_ERROR=ruby_missing' >&2; cleanup; exit 31; }
  runtime_path="$(resolve_runtime_path 2>/dev/null || true)"
  [ -n "$runtime_path" ] || { echo 'PROXLY_ERROR=runtime_config_missing' >&2; cleanup; exit 31; }
  cp -f "$runtime_path" "$tx.runtime" || { echo 'PROXLY_ERROR=backup_failed' >&2; cleanup; exit 31; }
  printf '%s' "$runtime_path" > "$tx.runtime_path"
  printf 'PROXLY_RUNTIME_PATH=%s\n' "$runtime_path"
fi
if [ "$uses_firewall" = '1' ]; then
  [ -x /etc/init.d/openclash ] || { echo 'PROXLY_ERROR=firewall_reload_missing' >&2; cleanup; exit 31; }
fi
if [ "$uses_proxy" = '1' ]; then
  printf '%s' '__OLD_PROXY_MODE__' > "$tx.proxy_mode"
fi

armed=1
trap rollback_on_exit EXIT
__APPLY_BODY__
pid_after="$(current_pid)"
[ "$pid_before" = "$pid_after" ] || fail pid_changed
armed=0
trap - EXIT
printf 'PROXLY_TX_READY=1\nPROXLY_PID_BEFORE=%s\n' "$pid_before"
''';

  static const _rollbackTemplate = r'''
set -u
tx='__TX__'
uses_runtime='__USES_RUNTIME__'
uses_firewall='__USES_FIREWALL__'
uses_proxy='__USES_PROXY__'

current_pid() {
  pidof clash 2>/dev/null | tr ' ' '\n' | sort -n | tr '\n' ' ' | sed 's/ *$//'
}

ok=1
[ -f "$tx.uci" ] || ok=0
if [ "$ok" = '1' ]; then
  uci import openclash < "$tx.uci" >/dev/null 2>&1 && uci commit openclash >/dev/null 2>&1 || ok=0
fi
if [ "$uses_runtime" = '1' ]; then
  runtime_path="$(cat "$tx.runtime_path" 2>/dev/null)"
  cp -f "$tx.runtime" "$runtime_path" >/dev/null 2>&1 || ok=0
fi
if [ "$uses_firewall" = '1' ]; then
  if /etc/init.d/openclash reload revert >/dev/null 2>&1 &&
      /etc/init.d/openclash reload restore >/dev/null 2>&1; then
    :
  elif /etc/init.d/openclash reload >/dev/null 2>&1; then
    :
  elif command -v fw4 >/dev/null 2>&1 && fw4 reload >/dev/null 2>&1; then
    :
  elif [ -x /etc/init.d/firewall ] &&
      /etc/init.d/firewall reload >/dev/null 2>&1; then
    :
  else
    ok=0
  fi
fi
pid_before="$(cat "$tx.pid" 2>/dev/null)"
[ -n "$pid_before" ] && [ "$pid_before" = "$(current_pid)" ] || ok=0
rm -f "$tx.uci" "$tx.runtime" "$tx.runtime_path" "$tx.proxy_mode" "$tx.pid" "$tx.http"
rmdir "${tx%/*}" 2>/dev/null || true
if [ "$ok" = '1' ]; then
  echo 'PROXLY_ROLLBACK=success'
  exit 0
fi
echo 'PROXLY_ROLLBACK=failed' >&2
exit 41
''';
}

class _QuickApplyException implements Exception {
  final String code;
  final String? detail;

  const _QuickApplyException(this.code, [this.detail]);
}
