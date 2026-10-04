import 'dart:async';

import 'package:flutter/material.dart';

import '../app_route_observer.dart';
import '../l10n/app_locale.dart';
import '../services/clash_config_file_service.dart';
import '../services/clash_data_hub.dart';
import '../services/clash_service.dart';
import '../services/openclash_quick_settings_service.dart';
import '../services/openclash_restart_coordinator.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/app_feedback.dart';
import 'clash_config_files_page.dart';

class ClashControlCenterPage extends StatefulWidget {
  final bool autoLoad;
  final OpenClashQuickSettingsService? quickSettingsService;
  final OpenClashRestartCoordinator? restartCoordinator;

  const ClashControlCenterPage({
    super.key,
    this.autoLoad = true,
    this.quickSettingsService,
    this.restartCoordinator,
  });

  @override
  State<ClashControlCenterPage> createState() => _ClashControlCenterPageState();
}

class _ClashControlCenterPageState extends State<ClashControlCenterPage>
    with
        WidgetsBindingObserver,
        RouteAware,
        TransientFeedbackStateMixin<ClashControlCenterPage> {
  static const _autoSyncInterval = Duration(seconds: 5);

  late final OpenClashQuickSettingsService _quickSettingsService;
  late final OpenClashRestartCoordinator _restartCoordinator;
  ModalRoute<void>? _route;
  Timer? _autoSyncTimer;
  ClashActiveConfig? _activeConfig;
  OpenClashQuickSettings? _quickSettings;
  OpenClashQuickSettingKey? _applyingQuickSetting;
  int _quickSettingsMutationEpoch = 0;
  bool _loadingConfig = false;
  bool _loadingQuickSettings = false;
  bool _switchingConfig = false;
  bool _flushingDns = false;
  bool _closingConnections = false;
  late OpenClashRestartPhase _lastRestartPhase;
  String? _configMessage;
  bool _configMessageIsError = false;
  bool _routeVisible = false;
  bool _appForeground = true;

  bool get _operationBusy =>
      _switchingConfig ||
      _restartCoordinator.isBusy ||
      _flushingDns ||
      _closingConnections ||
      _applyingQuickSetting != null;

  bool get _autoSyncEnabled =>
      widget.autoLoad && _routeVisible && _appForeground && mounted;

  @override
  void initState() {
    super.initState();
    _restartCoordinator =
        widget.restartCoordinator ?? OpenClashRestartCoordinator.instance;
    _quickSettingsService = widget.quickSettingsService ??
        OpenClashQuickSettingsService(
          restartCoordinator: _restartCoordinator,
        );
    _lastRestartPhase = _restartCoordinator.phase;
    WidgetsBinding.instance.addObserver(this);
    _restartCoordinator.addListener(_handleRestartStateChanged);
    if (widget.autoLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _routeVisible = ModalRoute.of<void>(context)?.isCurrent ?? true;
        _syncAutoSyncTimer();
        unawaited(_refreshPage());
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (identical(_route, route)) return;
    if (_route != null) shellRouteObserver.unsubscribe(this);
    _route = route;
    if (route != null) {
      shellRouteObserver.subscribe(this, route);
      _routeVisible = route.isCurrent;
      _syncAutoSyncTimer();
    }
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    if (_route != null) shellRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _restartCoordinator.removeListener(_handleRestartStateChanged);
    disposeTransientFeedback();
    super.dispose();
  }

  @override
  void didPush() {
    _routeVisible = true;
    _syncAutoSyncTimer();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _syncAutoSyncTimer();
    _refreshVisibleStatus();
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _syncAutoSyncTimer();
  }

  @override
  void didPop() {
    _routeVisible = false;
    _syncAutoSyncTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_appForeground == foreground) return;
    _appForeground = foreground;
    _syncAutoSyncTimer();
    if (foreground) _refreshVisibleStatus();
  }

  void _syncAutoSyncTimer() {
    if (!_autoSyncEnabled) {
      _autoSyncTimer?.cancel();
      _autoSyncTimer = null;
      return;
    }
    _autoSyncTimer ??= Timer.periodic(
      _autoSyncInterval,
      (_) => _refreshVisibleStatus(),
    );
  }

  void _refreshVisibleStatus() {
    if (!_autoSyncEnabled) return;
    unawaited(_refreshPage(silent: true));
  }

  void _handleRestartStateChanged() {
    if (!mounted) return;
    final previous = _lastRestartPhase;
    final current = _restartCoordinator.phase;
    setState(() => _lastRestartPhase = current);
    if (current != previous &&
        (current == OpenClashRestartPhase.succeeded ||
            current == OpenClashRestartPhase.failed)) {
      unawaited(_refreshPage(silent: true));
    }
  }

  Future<void> _refreshPage({bool silent = false}) async {
    if (_operationBusy && silent) return;
    await Future.wait([
      _loadQuickSettings(silent: silent),
      _loadActiveConfig(silent: silent),
    ]);
  }

  Future<void> _loadQuickSettings({bool silent = false}) async {
    if (_loadingQuickSettings || (!silent && _operationBusy)) return;
    final startedEpoch = _quickSettingsMutationEpoch;
    if (!silent) setState(() => _loadingQuickSettings = true);
    try {
      final settings = await _quickSettingsService.load();
      if (!mounted) return;
      if (silent &&
          (_applyingQuickSetting != null ||
              startedEpoch != _quickSettingsMutationEpoch)) {
        return;
      }
      setState(() {
        _quickSettings = settings;
        if (!silent) _loadingQuickSettings = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (!silent) {
        setState(() => _loadingQuickSettings = false);
        AppFeedback.showSnackBar(
          context,
          tr(_formatConfigError('读取快捷设置', error)),
          tone: AppFeedbackTone.error,
        );
      }
    } finally {
      if (!silent && mounted && _loadingQuickSettings) {
        setState(() => _loadingQuickSettings = false);
      }
    }
  }

  Future<void> _loadActiveConfig({bool silent = false}) async {
    if (_loadingConfig || _operationBusy) return;
    if (!silent) {
      cancelFeedbackClear('config');
      setState(() {
        _loadingConfig = true;
        _configMessage = null;
        _configMessageIsError = false;
      });
    }
    try {
      final active = await ClashConfigFileService.getActiveConfig();
      if (!mounted) return;
      setState(() => _activeConfig = active);
    } catch (error) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _configMessage = _formatConfigError('读取当前配置', error);
          _configMessageIsError = true;
        });
        _scheduleConfigMessageClear(isError: true);
      }
    } finally {
      if (!silent && mounted) setState(() => _loadingConfig = false);
    }
  }

  Future<void> _chooseActiveConfig() async {
    if (_operationBusy || _loadingConfig) return;
    cancelFeedbackClear('config');
    setState(() {
      _switchingConfig = true;
      _configMessage = null;
      _configMessageIsError = false;
    });

    try {
      final files = await ClashConfigFileService.listFiles();
      if (!mounted) return;
      if (files.isEmpty) {
        setState(() {
          _configMessage = '没有找到可切换的 YAML 配置文件';
          _configMessageIsError = true;
        });
        _scheduleConfigMessageClear(isError: true);
        return;
      }

      final selected = await showModalBottomSheet<ClashConfigFile>(
        context: context,
        showDragHandle: true,
        builder: (context) => _ConfigPickerSheet(
          files: files,
          activePath: _activeConfig?.file?.path,
        ),
      );
      if (selected == null || !mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr('切换当前配置？')),
          content: Text(tr('将切换到 ${selected.name} 并重启 OpenClash。重启期间代理会短暂断开。')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: AdaptiveSingleLineText(tr('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: AdaptiveSingleLineText(tr('切换并重启')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      setState(() {
        _configMessage = '正在切换配置并重启 OpenClash...';
        _configMessageIsError = false;
      });
      final result = await _restartCoordinator.restart(
        reason: OpenClashRestartReason.activeConfig,
        beforeRestart: () =>
            ClashConfigFileService.setActiveConfigFile(selected.path),
        verify: () async {
          final active = await ClashConfigFileService.getActiveConfig();
          if (active.file?.path != selected.path) {
            throw StateError('OpenClash did not activate ${selected.name}');
          }
        },
      );
      final active = await ClashConfigFileService.getActiveConfig();
      if (!mounted) return;
      final switchConfirmed =
          result.success && active.file?.path == selected.path;
      setState(() {
        _activeConfig = active;
        _configMessage = switchConfirmed
            ? '已切换到 ${selected.name}'
            : result.changesPersisted
                ? '配置已切换，但 OpenClash 重启失败：${_exceptionMessage(result.error ?? '')}'
                : active.subscriptionMode
                    ? '已发送切换命令，但当前仍显示为订阅模式，请检查 OpenClash 配置'
                    : '已发送切换命令，但未能确认当前配置已变更';
        _configMessageIsError = !switchConfirmed;
      });
      _scheduleConfigMessageClear(isError: !switchConfirmed);
      ClashDataHub.instance.resetBaseline(clearSnapshot: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _configMessage = _formatConfigError('切换配置', error);
        _configMessageIsError = true;
      });
      _scheduleConfigMessageClear(isError: true);
    } finally {
      if (mounted) {
        setState(() => _switchingConfig = false);
        unawaited(_refreshPage(silent: true));
      }
    }
  }

  Future<void> _openConfigFiles() async {
    if (_operationBusy) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ClashConfigFilesPage()),
    );
    if (mounted) await _loadActiveConfig();
  }

  Future<void> _restartOpenClash() async {
    if (_operationBusy) return;
    final password = await _requestRestartPassword();
    if (password == null || !mounted) return;

    final result = _restartCoordinator.canRetry
        ? await _restartCoordinator.retryLast(password: password)
        : await _restartCoordinator.restart(
            password: password,
            reason: OpenClashRestartReason.manual,
          );
    if (!mounted) return;
    _showRestartResult(result);
    unawaited(_refreshPage(silent: true));
  }

  Future<String?> _requestRestartPassword() async {
    final routerIp = await ClashConfigFileService.routerHost();
    if (routerIp.isEmpty) {
      _showSnack('请先在设置页填写 OpenClash 地址', success: false);
      return null;
    }
    final savedPassword = await ClashConfigFileService.savedPassword();
    if (!mounted) return null;
    FocusManager.instance.primaryFocus?.unfocus();
    return showDialog<String>(
      context: context,
      builder: (_) =>
          _SshPasswordDialog(routerIp: routerIp, savedPassword: savedPassword),
    );
  }

  void _showRestartResult(OpenClashRestartResult result) {
    if (result.success) {
      _showSnack('OpenClash 重启成功', success: true);
      return;
    }
    final detail = _exceptionMessage(result.error ?? '未知错误');
    _showSnack(
      result.changesPersisted ? '设置已保存但重启失败：$detail' : '重启失败：$detail',
      success: false,
    );
  }

  Future<void> _flushDnsCache() async {
    if (_operationBusy) return;
    final confirmed = await _confirmMaintenanceAction(
      title: '清理 DNS 缓存？',
      message: '将清理 Clash 内核的 DNS 解析缓存。确定继续？',
    );
    if (!confirmed || !mounted || _operationBusy) return;
    setState(() => _flushingDns = true);
    try {
      await ClashService.instance.loadConfig();
      await ClashService.instance.flushDnsCache();
      _showSnack('DNS 缓存已清理', success: true);
    } on TimeoutException {
      _showSnack('清理 DNS 缓存超时，请检查控制器连接', success: false);
    } catch (error) {
      _showSnack('清理失败：${_exceptionMessage(error)}', success: false);
    } finally {
      if (mounted) {
        setState(() => _flushingDns = false);
        unawaited(_refreshPage(silent: true));
      }
    }
  }

  Future<void> _closeAllConnections() async {
    if (_operationBusy) return;
    final confirmed = await _confirmMaintenanceAction(
      title: '关闭所有连接？',
      message: '将立即关闭所有当前 Clash 代理连接，部分应用可能会自动重新连接。确定继续？',
    );
    if (!confirmed || !mounted || _operationBusy) return;
    setState(() => _closingConnections = true);
    try {
      await ClashService.instance.loadConfig();
      await ClashService.instance.closeAllConnections();
      ClashDataHub.instance.resetBaseline(clearSnapshot: true);
      unawaited(
        ClashDataHub.instance
            .refresh(force: true)
            .then<void>((_) {}, onError: (_) {}),
      );
      _showSnack('所有 Clash 代理连接已关闭', success: true);
    } on TimeoutException {
      _showSnack('关闭连接超时，请检查控制器连接', success: false);
    } catch (error) {
      _showSnack('关闭连接失败：${_exceptionMessage(error)}', success: false);
    } finally {
      if (mounted) {
        setState(() => _closingConnections = false);
        unawaited(_refreshPage(silent: true));
      }
    }
  }

  Future<bool> _confirmMaintenanceAction({
    required String title,
    required String message,
  }) async {
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(title)),
        content: Text(tr(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: AdaptiveSingleLineText(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: AdaptiveSingleLineText(tr('确定')),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _changeRunVariant(OpenClashRunVariant variant) async {
    final current = _quickSettings;
    if (current == null ||
        current.runVariant == variant ||
        current.baseMode == OpenClashBaseMode.unknown) {
      return;
    }
    await _applyQuickSetting(
      key: OpenClashQuickSettingKey.runVariant,
      desired: current.copyWith(runVariant: variant),
    );
  }

  Future<void> _changeProxyMode(OpenClashProxyMode mode) async {
    final current = _quickSettings;
    if (current == null || current.proxyMode == mode) return;
    if (mode != OpenClashProxyMode.rule && current.streamUnlockEnabled) {
      _showSnack('请先关闭流媒体解锁', success: false);
      return;
    }
    await _applyQuickSetting(
      key: OpenClashQuickSettingKey.proxyMode,
      desired: current.copyWith(proxyMode: mode),
    );
  }

  Future<void> _changeAreaBypass(OpenClashAreaBypass area) async {
    final current = _quickSettings;
    if (current == null || current.areaBypass == area) return;
    await _applyQuickSetting(
      key: OpenClashQuickSettingKey.areaBypass,
      desired: current.copyWith(areaBypass: area),
    );
  }

  Future<void> _changeSniffer(bool enabled) async {
    final current = _quickSettings;
    if (current == null || current.snifferEnabled == enabled) return;
    await _applyQuickSetting(
      key: OpenClashQuickSettingKey.sniffer,
      desired: current.copyWith(snifferEnabled: enabled),
    );
  }

  Future<void> _changeDnsProxy(bool enabled) async {
    final current = _quickSettings;
    if (current == null || current.dnsProxyEnabled == enabled) return;
    await _applyQuickSetting(
      key: OpenClashQuickSettingKey.dnsProxy,
      desired: current.copyWith(dnsProxyEnabled: enabled),
    );
  }

  Future<void> _changeStreamUnlock(bool enabled) async {
    final current = _quickSettings;
    if (current == null || current.streamUnlockEnabled == enabled) return;
    if (enabled && current.proxyMode != OpenClashProxyMode.rule) {
      _showSnack('流媒体解锁仅支持规则代理模式', success: false);
      return;
    }
    if (enabled && !current.routerSelfProxyEnabled) {
      _showSnack('请先在 OpenClash 中启用路由器本机代理', success: false);
      return;
    }
    if (enabled && !current.streamUnlockSupported) {
      _showSnack('当前 OpenClash 未提供流媒体解锁组件', success: false);
      return;
    }
    await _applyQuickSetting(
      key: OpenClashQuickSettingKey.streamUnlock,
      desired: current.copyWith(streamUnlockEnabled: enabled),
    );
  }

  Future<void> _applyQuickSetting({
    required OpenClashQuickSettingKey key,
    required OpenClashQuickSettings desired,
  }) async {
    final original = _quickSettings;
    if (original == null || _operationBusy) return;
    _quickSettingsMutationEpoch++;
    setState(() {
      _applyingQuickSetting = key;
      _quickSettings = desired;
    });

    try {
      final result = await _quickSettingsService.applyChange(
        original: original,
        desired: desired,
        key: key,
      );
      if (!mounted) return;
      setState(() => _quickSettings = result.settings);
      if (!result.success) {
        AppFeedback.showSnackBar(
          context,
          tr(_quickSettingFailureMessage(result)),
          tone: AppFeedbackTone.error,
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _quickSettings = original);
      AppFeedback.showSnackBar(
        context,
        tr('应用失败：${_exceptionMessage(error)}'),
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        _quickSettingsMutationEpoch++;
        setState(() => _applyingQuickSetting = null);
        unawaited(_refreshPage(silent: true));
      }
    }
  }

  String _quickSettingFailureMessage(
    OpenClashQuickSettingApplyResult result,
  ) {
    final reason = switch (result.errorCode) {
      'ssh_password_required' => '请先在设置页填写并保存 SSH 密码',
      'uci_missing' => '当前环境缺少 UCI 工具',
      'curl_missing' => '当前环境缺少 Curl 工具',
      'ruby_missing' => '当前环境缺少 Ruby，无法安全修改运行时配置',
      'core_offline' => 'Mihomo 当前未运行',
      'runtime_config_missing' => '未找到 OpenClash 生成的运行时配置',
      'restart_unavailable' => '当前环境无法重启 OpenClash',
      'firewall_reload_missing' => '当前环境不支持 OpenClash 防火墙重载',
      'unsupported_run_mode' => '当前运行模式不支持快捷切换',
      'stream_requires_rule' => '流媒体解锁仅支持规则代理模式',
      'stream_requires_router_proxy' => '请先在 OpenClash 中启用路由器本机代理',
      'stream_component_missing' => '当前 OpenClash 未提供流媒体解锁组件',
      'backup_failed' => '无法创建设置备份',
      'runtime_modify_failed' => '运行时配置修改失败',
      'hot_reload_failed' => 'Mihomo 热重载失败',
      'controller_not_configured' => '请先在设置页填写 Clash 控制器地址',
      'controller_unauthorized' => 'Clash 控制器 Token 错误',
      'controller_bad_request' => 'Mihomo 拒绝了配置请求',
      'controller_rejected' => 'Clash 控制器拒绝了请求',
      'controller_timeout' => '连接 Clash 控制器超时',
      'controller_unreachable' => '无法连接 Clash 控制器',
      'controller_api_failed' => 'Clash 控制器 API 调用失败，请检查控制器地址与 Token',
      'firewall_reload_failed' => 'OpenClash 防火墙重载失败',
      'persist_failed' => 'OpenClash 设置保存失败',
      'verification_failed' => '重新读取后设置未生效',
      'core_health_failed' => 'Mihomo 未能连续通过健康检查',
      'restart_failed' => 'OpenClash 重启或上线验证失败',
      'pid_changed' => '检测到 Mihomo 进程发生变化',
      'backup_missing' => '设置事务备份已丢失',
      'incomplete_response' => '路由器没有返回完整操作结果',
      'rollback_failed' => '实际状态可能不完整，请检查 OpenClash',
      _ => '当前环境无法完成设置',
    };
    final detail = result.errorDetail?.trim();
    final reasonWithDetail =
        detail == null || detail.isEmpty ? reason : '$reason（$detail）';
    if (result.changesPersisted) {
      return result.canRetry
          ? '设置已保存，但 OpenClash 未恢复正常：$reasonWithDetail。可使用重启按钮重试'
          : '设置已保存，但 OpenClash 未恢复正常：$reasonWithDetail';
    }
    if (result.rollbackAttempted && result.rollbackSucceeded) {
      return '应用失败，已恢复原设置：$reasonWithDetail';
    }
    if (result.rollbackAttempted) {
      return '应用失败且未能完整回滚：$reasonWithDetail';
    }
    return '应用失败：$reasonWithDetail';
  }

  String get _restartStatusLabel => switch (_restartCoordinator.phase) {
        OpenClashRestartPhase.saving => '正在保存设置...',
        OpenClashRestartPhase.restarting => '正在重启 OpenClash...',
        OpenClashRestartPhase.waitingForOnline => '等待 Clash 重新上线...',
        OpenClashRestartPhase.verifying => '正在验证设置...',
        OpenClashRestartPhase.failed when _restartCoordinator.canRetry =>
          '重试重启',
        _ => '重启 OpenClash',
      };

  bool get _showAppBarActivity =>
      _applyingQuickSetting != null || _restartCoordinator.isBusy;

  String get _appBarActivityLabel =>
      _restartCoordinator.isBusy ? _restartStatusLabel : '正在应用设置...';

  String _formatConfigError(String action, Object error) {
    if (error is SshPasswordRequiredException) {
      return '$action失败：请先在设置页填写并保存 SSH 密码';
    }
    return '$action失败：${_exceptionMessage(error)}';
  }

  String _exceptionMessage(Object error) =>
      error.toString().replaceFirst(RegExp(r'^Exception: '), '');

  void _showSnack(String message, {required bool success}) {
    if (!mounted) return;
    AppFeedback.showSnackBar(
      context,
      tr(message),
      tone: success ? AppFeedbackTone.success : AppFeedbackTone.error,
    );
  }

  void _scheduleConfigMessageClear({required bool isError}) {
    scheduleFeedbackClear(
      'config',
      isError: isError,
      clear: () => setState(() {
        _configMessage = null;
        _configMessageIsError = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final colorScheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    final bgColor = palette.pageBackground;
    final cardBg = palette.surface;
    final cardBorder = palette.border;
    final textColor = palette.textPrimary;
    final hintColor = palette.textSecondary;

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            tooltip: tr('返回'),
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_back_rounded, color: textColor),
          ),
          title: AdaptiveSingleLineText(
            tr('Clash 控制中心'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          centerTitle: true,
          actions: [
            SizedBox(
              width: kToolbarHeight,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: _showAppBarActivity
                      ? Semantics(
                          label: tr(_appBarActivityLabel),
                          liveRegion: true,
                          child: SizedBox(
                            key: const ValueKey(
                              'control_center_app_bar_activity_indicator',
                            ),
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.25,
                              color: colorScheme.primary,
                            ),
                          ),
                        )
                      : const SizedBox(
                          key: ValueKey(
                            'control_center_app_bar_activity_idle',
                          ),
                          width: 20,
                          height: 20,
                        ),
                ),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(0.5),
            child: Container(height: 0.5, color: cardBorder),
          ),
        ),
        body: ListView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          children: [
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cardBorder, width: 0.5),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('维护操作'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr('重启 OpenClash，或维护 Clash 内核的 DNS 缓存与代理连接。'),
                    style: TextStyle(fontSize: 11, color: hintColor),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: _OperationButton(
                      key: const ValueKey('maintenance_restart'),
                      label: tr(_restartStatusLabel),
                      icon: Icons.restart_alt_rounded,
                      warning: true,
                      loading: false,
                      enabled: !_operationBusy,
                      onTap: _restartOpenClash,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _OperationButton(
                          key: const ValueKey('maintenance_flush_dns'),
                          label: tr(_flushingDns ? '清理中' : '清理 DNS 缓存'),
                          icon: Icons.dns_rounded,
                          loading: _flushingDns,
                          enabled: !_operationBusy,
                          onTap: _flushDnsCache,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _OperationButton(
                          key: const ValueKey(
                            'maintenance_close_connections',
                          ),
                          label: tr(_closingConnections ? '关闭中' : '关闭连接'),
                          icon: Icons.link_off_rounded,
                          loading: _closingConnections,
                          enabled: !_operationBusy,
                          onTap: _closeAllConnections,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _OpenClashQuickSettingsCard(
              settings: _quickSettings,
              loading: _loadingQuickSettings,
              busy: _operationBusy,
              cardBg: cardBg,
              cardBorder: cardBorder,
              textColor: textColor,
              hintColor: hintColor,
              onRunVariantChanged: _changeRunVariant,
              onProxyModeChanged: _changeProxyMode,
              onAreaBypassChanged: _changeAreaBypass,
              onSnifferChanged: _changeSniffer,
              onDnsProxyChanged: _changeDnsProxy,
              onStreamUnlockChanged: _changeStreamUnlock,
            ),
            const SizedBox(height: 12),
            _CurrentConfigCard(
              activeConfig: _activeConfig,
              loading: _loadingConfig,
              switching: _switchingConfig,
              operationBusy: _operationBusy,
              message: _configMessage,
              messageIsError: _configMessageIsError,
              cardBg: cardBg,
              cardBorder: cardBorder,
              textColor: textColor,
              hintColor: hintColor,
              onRefresh: () => unawaited(_loadActiveConfig()),
              onSwitch: _chooseActiveConfig,
            ),
            const SizedBox(height: 12),
            _NavigationCard(
              icon: Icons.description_outlined,
              title: tr('YAML 配置文件'),
              subtitle: tr('读取、上传并编辑 OpenClash YAML 配置'),
              cardBg: cardBg,
              cardBorder: cardBorder,
              textColor: textColor,
              hintColor: hintColor,
              enabled: !_operationBusy,
              onTap: _openConfigFiles,
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenClashQuickSettingsCard extends StatelessWidget {
  final OpenClashQuickSettings? settings;
  final bool loading;
  final bool busy;
  final Color cardBg;
  final Color cardBorder;
  final Color textColor;
  final Color hintColor;
  final ValueChanged<OpenClashRunVariant> onRunVariantChanged;
  final ValueChanged<OpenClashProxyMode> onProxyModeChanged;
  final ValueChanged<OpenClashAreaBypass> onAreaBypassChanged;
  final ValueChanged<bool> onSnifferChanged;
  final ValueChanged<bool> onDnsProxyChanged;
  final ValueChanged<bool> onStreamUnlockChanged;

  const _OpenClashQuickSettingsCard({
    required this.settings,
    required this.loading,
    required this.busy,
    required this.cardBg,
    required this.cardBorder,
    required this.textColor,
    required this.hintColor,
    required this.onRunVariantChanged,
    required this.onProxyModeChanged,
    required this.onAreaBypassChanged,
    required this.onSnifferChanged,
    required this.onDnsProxyChanged,
    required this.onStreamUnlockChanged,
  });

  @override
  Widget build(BuildContext context) {
    final current = settings;
    final palette = AppPalette.of(context);
    final enabled = current != null && !busy;
    final baseModeLabel = switch (current?.baseMode) {
      OpenClashBaseMode.fakeIp => 'Fake-IP',
      OpenClashBaseMode.redirHost => 'Redir-Host',
      _ => current?.rawRunMode.isNotEmpty == true
          ? current!.rawRunMode
          : tr('尚未读取'),
    };
    final compatibilityLabel =
        current?.baseMode == OpenClashBaseMode.fakeIp ? tr('增强') : tr('兼容');
    final runModeSupported = current?.baseMode != OpenClashBaseMode.unknown &&
        current?.runVariant != null;

    var streamDescription = tr('自动为常见流媒体服务选择可解锁节点');
    if (current != null && !current.streamUnlockSupported) {
      streamDescription = tr('当前 OpenClash 未提供流媒体解锁组件');
    } else if (current != null && !current.routerSelfProxyEnabled) {
      streamDescription = tr('需要先在 OpenClash 中启用路由器本机代理');
    } else if (current != null &&
        current.proxyMode != OpenClashProxyMode.rule) {
      streamDescription = tr('仅支持规则代理模式');
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder, width: 0.5),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AdaptiveSingleLineText(
                      tr('OpenClash 快捷设置'),
                      alignment: Alignment.centerLeft,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr('设置会立即应用；切换运行模式时现有连接可能短暂重连。'),
                      style: TextStyle(fontSize: 11, color: hintColor),
                    ),
                  ],
                ),
              ),
              if (loading && current == null) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  key: ValueKey('quick_setting_loading_indicator'),
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _QuickSettingsSection(
            title: tr('运行模式'),
            description: tr('当前基础模式由 OpenClash 管理，可选择对应运行方式'),
            textColor: textColor,
            hintColor: hintColor,
            trailing: Container(
              constraints: const BoxConstraints(minWidth: 68),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: palette.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: AdaptiveSingleLineText(
                baseModeLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: palette.success,
                ),
              ),
            ),
            child: _QuickChoiceGroup<OpenClashRunVariant>(
              labels: [compatibilityLabel, 'TUN', tr('混合')],
              values: OpenClashRunVariant.values,
              selected: current?.runVariant,
              enabled: enabled && runModeSupported,
              valueKeyPrefix: 'quick_setting_run',
              onSelected: onRunVariantChanged,
            ),
          ),
          Divider(height: 25, color: cardBorder),
          _QuickSettingsSection(
            title: tr('代理模式'),
            description: tr('切换 Mihomo 处理连接时使用的规则范围'),
            textColor: textColor,
            hintColor: hintColor,
            child: _QuickChoiceGroup<OpenClashProxyMode>(
              labels: [tr('规则'), tr('全局'), tr('直连')],
              values: OpenClashProxyMode.values,
              selected: current?.proxyMode,
              enabled: enabled,
              valueKeyPrefix: 'quick_setting_proxy',
              onSelected: onProxyModeChanged,
            ),
          ),
          Divider(height: 25, color: cardBorder),
          _QuickSettingsSection(
            title: tr('区域绕过'),
            description: tr('指定区域流量不经过内核'),
            textColor: textColor,
            hintColor: hintColor,
            child: _QuickChoiceGroup<OpenClashAreaBypass>(
              labels: [tr('大陆'), tr('海外'), tr('停用')],
              values: const [
                OpenClashAreaBypass.mainland,
                OpenClashAreaBypass.overseas,
                OpenClashAreaBypass.disabled,
              ],
              selected: current?.areaBypass,
              enabled: enabled,
              valueKeyPrefix: 'quick_setting_area',
              onSelected: onAreaBypassChanged,
            ),
          ),
          Divider(height: 25, color: cardBorder),
          _QuickSwitchRow(
            key: const ValueKey('quick_setting_sniffer'),
            title: tr('域名嗅探'),
            description: tr('识别连接中的域名，降低按域名分流失效的概率'),
            value: current?.snifferEnabled ?? false,
            enabled: enabled,
            textColor: textColor,
            hintColor: hintColor,
            onChanged: onSnifferChanged,
          ),
          Divider(height: 17, color: cardBorder),
          _QuickSwitchRow(
            key: const ValueKey('quick_setting_dns_proxy'),
            title: tr('DNS 代理'),
            description: tr('让 DNS 查询遵循代理规则，减少解析与访问不一致'),
            value: current?.dnsProxyEnabled ?? false,
            enabled: enabled,
            textColor: textColor,
            hintColor: hintColor,
            onChanged: onDnsProxyChanged,
          ),
          Divider(height: 17, color: cardBorder),
          _QuickSwitchRow(
            key: const ValueKey('quick_setting_stream_unlock'),
            title: tr('流媒体解锁'),
            description: streamDescription,
            value: current?.streamUnlockEnabled ?? false,
            enabled: enabled,
            textColor: textColor,
            hintColor: hintColor,
            onChanged: onStreamUnlockChanged,
          ),
        ],
      ),
    );
  }
}

class _QuickSettingsSection extends StatelessWidget {
  final String title;
  final String description;
  final Color textColor;
  final Color hintColor;
  final Widget? trailing;
  final Widget child;

  const _QuickSettingsSection({
    required this.title,
    required this.description,
    required this.textColor,
    required this.hintColor,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: TextStyle(fontSize: 11, color: hintColor),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
        const SizedBox(height: 11),
        child,
      ],
    );
  }
}

class _QuickChoiceGroup<T> extends StatelessWidget {
  final List<String> labels;
  final List<T> values;
  final T? selected;
  final bool enabled;
  final String valueKeyPrefix;
  final ValueChanged<T> onSelected;

  const _QuickChoiceGroup({
    required this.labels,
    required this.values,
    required this.selected,
    required this.enabled,
    required this.valueKeyPrefix,
    required this.onSelected,
  }) : assert(labels.length == values.length);

  @override
  Widget build(BuildContext context) {
    return AdaptiveOptionGroup(
      labels: labels,
      reservedItemWidth: 28,
      children: [
        for (var index = 0; index < values.length; index++)
          _QuickChoiceButton(
            key: ValueKey('${valueKeyPrefix}_${values[index]}'),
            label: labels[index],
            selected: selected == values[index],
            enabled: enabled,
            onTap: () => onSelected(values[index]),
          ),
      ],
    );
  }
}

class _QuickChoiceButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _QuickChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AdaptiveSelectionButton(
      label: label,
      selected: selected,
      enabled: enabled,
      onTap: onTap,
    );
  }
}

class _QuickSwitchRow extends StatelessWidget {
  final String title;
  final String description;
  final bool value;
  final bool enabled;
  final Color textColor;
  final Color hintColor;
  final ValueChanged<bool> onChanged;

  const _QuickSwitchRow({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.enabled,
    required this.textColor,
    required this.hintColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: TextStyle(fontSize: 11, color: hintColor),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          value: value,
          onChanged: enabled ? onChanged : null,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }
}

class _CurrentConfigCard extends StatelessWidget {
  final ClashActiveConfig? activeConfig;
  final bool loading;
  final bool switching;
  final bool operationBusy;
  final String? message;
  final bool messageIsError;
  final Color cardBg;
  final Color cardBorder;
  final Color textColor;
  final Color hintColor;
  final VoidCallback onRefresh;
  final VoidCallback onSwitch;

  const _CurrentConfigCard({
    required this.activeConfig,
    required this.loading,
    required this.switching,
    required this.operationBusy,
    required this.message,
    required this.messageIsError,
    required this.cardBg,
    required this.cardBorder,
    required this.textColor,
    required this.hintColor,
    required this.onRefresh,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder, width: 0.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AdaptiveSingleLineText(
                  tr('当前使用配置'),
                  alignment: Alignment.centerLeft,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              IconButton(
                tooltip: tr('刷新当前配置'),
                visualDensity: VisualDensity.compact,
                onPressed: loading || operationBusy ? null : onRefresh,
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.refresh_rounded, size: 20, color: hintColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                activeConfig?.usesYaml == true
                    ? Icons.description_outlined
                    : Icons.link_off_rounded,
                size: 20,
                color: hintColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        loading
                            ? '正在读取...'
                            : (activeConfig?.displayText ?? '尚未读取'),
                      ),
                      style: TextStyle(fontSize: 13, color: textColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(activeConfig?.detailText ?? '读取 OpenClash 当前使用的配置来源'),
                      style: TextStyle(fontSize: 11, color: hintColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: 10),
            Text(
              tr(message!),
              style: TextStyle(
                fontSize: 12,
                color: messageIsError
                    ? AppPalette.of(context).error
                    : AppPalette.of(context).success,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: _OperationButton(
              key: const ValueKey('current_config_switch'),
              label: tr(switching ? '处理中' : '选择 YAML 配置'),
              icon: Icons.swap_horiz_rounded,
              loading: switching,
              enabled: !operationBusy && !loading,
              onTap: onSwitch,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color cardBg;
  final Color cardBorder;
  final Color textColor;
  final Color hintColor;
  final bool enabled;
  final VoidCallback onTap;

  const _NavigationCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.cardBg,
    required this.cardBorder,
    required this.textColor,
    required this.hintColor,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1 : 0.55,
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cardBorder, width: 0.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11, color: hintColor),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: hintColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _OperationButton extends StatelessWidget {
  static const _warningFill = Color(0xFFD97706);

  final String label;
  final IconData icon;
  final bool warning;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  const _OperationButton({
    super.key,
    required this.label,
    required this.icon,
    this.warning = false,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = warning
        ? ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.disabled)
                    ? _warningFill.withValues(alpha: 0.42)
                    : _warningFill),
            foregroundColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.disabled)
                    ? Colors.white.withValues(alpha: 0.68)
                    : Colors.white),
          )
        : null;

    return FilledButton.icon(
      onPressed: enabled ? onTap : null,
      style: style,
      icon: loading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon, size: 18),
      label: AdaptiveSingleLineText(label),
    );
  }
}

class _ConfigPickerSheet extends StatelessWidget {
  final List<ClashConfigFile> files;
  final String? activePath;

  const _ConfigPickerSheet({required this.files, required this.activePath});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintColor = AppPalette.of(context).textSecondary;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('选择 YAML 配置'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr('选择后会写入 OpenClash 当前配置，并在确认后重启。'),
              style: TextStyle(fontSize: 12, color: hintColor),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.55,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: files.length,
                separatorBuilder: (_, __) => Divider(
                  height: 0,
                  color: theme.dividerColor.withValues(alpha: 0.5),
                ),
                itemBuilder: (context, index) {
                  final file = files[index];
                  final selected = file.path == activePath;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected ? theme.colorScheme.primary : hintColor,
                    ),
                    title: Text(
                      file.name,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      file.displayPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: hintColor),
                    ),
                    onTap: () => Navigator.of(context).pop(file),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SshPasswordDialog extends StatefulWidget {
  final String routerIp;
  final String savedPassword;

  const _SshPasswordDialog({
    required this.routerIp,
    required this.savedPassword,
  });

  @override
  State<_SshPasswordDialog> createState() => _SshPasswordDialogState();
}

class _SshPasswordDialogState extends State<_SshPasswordDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.savedPassword,
  );
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  bool get _hasSavedPassword => widget.savedPassword.isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final password = _controller.text;
    if (password.isEmpty) {
      setState(() => _error = '请输入密码');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    if (!_hasSavedPassword) {
      await ClashConfigFileService.savePassword(password);
    }
    if (mounted) Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('确认重启 OpenClash')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'root@${widget.routerIp}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          if (_hasSavedPassword)
            Text(tr('将使用设置页保存的 SSH 密码执行重启。如需更换密码，请到设置页修改。'))
          else ...[
            Text(tr('设置页未保存 SSH 密码，本次输入后会同步保存到设置页。')),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: _obscure,
              onSubmitted: (_) => _confirm(),
              decoration: InputDecoration(
                labelText: tr('SSH 密码'),
                errorText: _error == null ? null : tr(_error!),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: AdaptiveSingleLineText(tr('取消')),
        ),
        FilledButton(
          onPressed: _saving ? null : _confirm,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : AdaptiveSingleLineText(tr('确认重启')),
        ),
      ],
    );
  }
}
