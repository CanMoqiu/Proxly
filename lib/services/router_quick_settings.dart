import 'router_tool.dart';

enum OpenClashBaseMode { fakeIp, redirHost, unknown }

enum OpenClashRunVariant { compatibility, tun, mix }

enum OpenClashProxyMode { rule, global, direct }

enum OpenClashAreaBypass { mainland, overseas, disabled }

enum OpenClashQuickSettingKey {
  baseMode,
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
  final OpenClashAreaBypass? areaBypass;
  final bool snifferEnabled;
  final bool dnsProxyEnabled;
  final bool streamUnlockEnabled;
  final bool routerSelfProxyEnabled;
  final bool streamUnlockSupported;
  final String rawRunMode;
  final RouterTool routerTool;
  final String backendRevision;
  final Set<OpenClashQuickSettingKey> unsupported;
  bool supports(OpenClashQuickSettingKey key) => !unsupported.contains(key);

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
    this.routerTool = RouterTool.openClash,
    this.backendRevision = '',
    this.unsupported = const {},
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
      routerTool: routerTool,
      backendRevision: backendRevision,
      unsupported: unsupported,
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
  final bool stateUncertain;

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
    this.stateUncertain = false,
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
    bool stateUncertain = false,
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
          stateUncertain: stateUncertain,
        );
}
