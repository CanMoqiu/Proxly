import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_route_observer.dart';
import '../../l10n/app_locale.dart';
import '../../services/clash_config_file_service.dart';
import '../../services/clash_data_hub.dart';
import '../../services/clash_service.dart';
import '../../services/connection_settings_store.dart';
import '../../services/openclash_quick_settings_service.dart';
import '../../services/openclash_restart_coordinator.dart';
import '../../theme/app_theme.dart';
import '../adaptive_ui.dart';
import '../app_feedback.dart';
import '../../pages/clash_config_editor_page.dart';
import '../yaml_config_picker.dart';
import 'current_yaml_card.dart';
import 'clash_operations_card.dart';
import 'quick_settings_card.dart';

class DashboardControls extends StatefulWidget {
  final bool autoLoad;
  final bool active;
  final bool refreshConfig;
  final bool refreshQuickSettings;
  final Widget Function(BuildContext, DashboardControlCards) builder;
  final Future<ClashActiveConfig> Function()? loadActiveConfig;
  final Future<List<ClashConfigFile>> Function()? listFiles;
  final Widget Function(ClashConfigFile?)? editorBuilder;
  final Future<void> Function(String)? activateConfig;
  final OpenClashQuickSettingsService? quickSettingsService;
  final OpenClashRestartCoordinator? restartCoordinator;

  const DashboardControls({
    super.key,
    this.autoLoad = true,
    this.active = true,
    this.refreshConfig = true,
    this.refreshQuickSettings = true,
    required this.builder,
    this.loadActiveConfig,
    this.listFiles,
    this.editorBuilder,
    this.activateConfig,
    this.quickSettingsService,
    this.restartCoordinator,
  });

  @override
  State<DashboardControls> createState() => _DashboardControlsState();
}

class _DashboardControlsState extends State<DashboardControls>
    with
        WidgetsBindingObserver,
        RouteAware,
        TransientFeedbackStateMixin<DashboardControls> {
  static const _autoSyncInterval = Duration(seconds: 5);

  late final OpenClashQuickSettingsService _quickSettingsService;
  late final OpenClashRestartCoordinator _restartCoordinator;
  ModalRoute<void>? _route;
  Timer? _autoSyncTimer;
  ClashActiveConfig? _activeConfig;
  OpenClashQuickSettings? _quickSettings;
  OpenClashQuickSettingKey? _applyingQuickSetting;
  int _quickSettingsMutationEpoch = 0;
  int _configMutationEpoch = 0;
  bool _loadingConfig = false;
  bool _loadingQuickSettings = false;
  bool _readingQuickSettings = false;
  bool _readingConfig = false;
  int _connectionEpoch = 0;
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
      widget.autoLoad &&
      (widget.refreshConfig || widget.refreshQuickSettings) &&
      widget.active &&
      _routeVisible &&
      _appForeground &&
      mounted;

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
    ConnectionSettingsStore.instance.addListener(_handleConnectionChanged);
    if (widget.autoLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _routeVisible = ModalRoute.of<void>(context)?.isCurrent ?? true;
        _syncAutoSyncTimer();
        if (_autoSyncEnabled) unawaited(_refreshPage());
      });
    }
  }

  @override
  void didUpdateWidget(covariant DashboardControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.refreshConfig != widget.refreshConfig ||
        oldWidget.refreshQuickSettings != widget.refreshQuickSettings) {
      _syncAutoSyncTimer();
      if (widget.active) _refreshVisibleStatus();
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
    ConnectionSettingsStore.instance.removeListener(_handleConnectionChanged);
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

  void _handleConnectionChanged() {
    if (!mounted) return;
    _connectionEpoch++;
    _quickSettingsMutationEpoch++;
    _configMutationEpoch++;
    setState(() {
      _activeConfig = null;
      _quickSettings = null;
      _configMessage = null;
    });
    _refreshVisibleStatus();
  }

  void _handleRestartStateChanged() {
    if (!mounted) return;
    final previous = _lastRestartPhase;
    final current = _restartCoordinator.phase;
    setState(() => _lastRestartPhase = current);
    if (current != previous &&
        (current == OpenClashRestartPhase.succeeded ||
            current == OpenClashRestartPhase.failed)) {
      _refreshVisibleStatus();
    }
  }

  Future<void> _refreshPage({bool silent = false}) async {
    if (_operationBusy && silent) return;
    await Future.wait([
      if (widget.refreshQuickSettings) _loadQuickSettings(silent: silent),
      if (widget.refreshConfig) _loadActiveConfig(silent: silent),
    ]);
  }

  Future<void> _loadQuickSettings({bool silent = false}) async {
    if (_readingQuickSettings || _operationBusy) return;
    _readingQuickSettings = true;
    final connectionEpoch = _connectionEpoch;
    final startedEpoch = _quickSettingsMutationEpoch;
    if (!silent) setState(() => _loadingQuickSettings = true);
    try {
      final settings = await _quickSettingsService.load();
      if (!mounted || connectionEpoch != _connectionEpoch) return;
      if (_applyingQuickSetting != null ||
          startedEpoch != _quickSettingsMutationEpoch) {
        return;
      }
      setState(() {
        _quickSettings = settings;
        if (!silent) _loadingQuickSettings = false;
      });
    } catch (error) {
      if (!mounted || connectionEpoch != _connectionEpoch) return;
      if (!silent) {
        setState(() => _loadingQuickSettings = false);
        AppFeedback.showSnackBar(
          context,
          tr(_formatConfigError('读取快捷设置', error)),
          tone: AppFeedbackTone.error,
        );
      }
    } finally {
      _readingQuickSettings = false;
      if (!silent && mounted && _loadingQuickSettings) {
        setState(() => _loadingQuickSettings = false);
      }
      if ((connectionEpoch != _connectionEpoch ||
              startedEpoch != _quickSettingsMutationEpoch) &&
          _autoSyncEnabled &&
          widget.refreshQuickSettings) {
        unawaited(_loadQuickSettings(silent: true));
      }
    }
  }

  Future<void> _loadActiveConfig({bool silent = false}) async {
    if (_readingConfig || _operationBusy) return;
    _readingConfig = true;
    final connectionEpoch = _connectionEpoch;
    final mutationEpoch = _configMutationEpoch;
    if (!silent) {
      cancelFeedbackClear('config');
      setState(() {
        _loadingConfig = true;
        _configMessage = null;
        _configMessageIsError = false;
      });
    }
    try {
      final active = await (widget.loadActiveConfig ??
          ClashConfigFileService.getActiveConfig)();
      if (!mounted ||
          connectionEpoch != _connectionEpoch ||
          mutationEpoch != _configMutationEpoch ||
          _operationBusy) {
        return;
      }
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
      _readingConfig = false;
      if (!silent && mounted) setState(() => _loadingConfig = false);
      if ((connectionEpoch != _connectionEpoch ||
              mutationEpoch != _configMutationEpoch) &&
          _autoSyncEnabled &&
          widget.refreshConfig) {
        unawaited(_loadActiveConfig(silent: true));
      }
    }
  }

  Future<void> _chooseActiveConfig() async {
    if (_operationBusy || _loadingConfig) return;
    _configMutationEpoch++;
    cancelFeedbackClear('config');
    setState(() {
      _switchingConfig = true;
      _configMessage = null;
      _configMessageIsError = false;
    });

    try {
      final files =
          await (widget.listFiles ?? ClashConfigFileService.listFiles)();
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
        isScrollControlled: true,
        builder: (context) => YamlConfigPickerSheet(
          files: files,
          activePath: _activeConfig?.file?.path,
        ),
      );
      if (selected == null ||
          !mounted ||
          selected.path == _activeConfig?.file?.path) {
        return;
      }

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
        beforeRestart: () => (widget.activateConfig ??
            ClashConfigFileService.setActiveConfigFile)(selected.path),
        verify: () async {
          final active = await (widget.loadActiveConfig ??
              ClashConfigFileService.getActiveConfig)();
          if (active.file?.path != selected.path) {
            throw StateError('OpenClash did not activate ${selected.name}');
          }
        },
      );
      final active = await (widget.loadActiveConfig ??
          ClashConfigFileService.getActiveConfig)();
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

  Future<void> _editConfig() async {
    if (_operationBusy) return;
    _configMutationEpoch++;
    await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              widget.editorBuilder?.call(_activeConfig?.file) ??
              ClashConfigEditorPage(
                file: _activeConfig?.file,
                restartCoordinator: _restartCoordinator,
              ),
        ));
    if (mounted) {
      _configMutationEpoch++;
      await _refreshPage();
    }
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
    final connectionEpoch = _connectionEpoch;
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
      if (!mounted || connectionEpoch != _connectionEpoch) return;
      setState(() =>
          _quickSettings = result.stateUncertain ? null : result.settings);
      if (!result.success) {
        AppFeedback.showSnackBar(
          context,
          tr(_quickSettingFailureMessage(result)),
          tone: AppFeedbackTone.error,
        );
      }
    } catch (error) {
      if (!mounted || connectionEpoch != _connectionEpoch) return;
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
    if (result.stateUncertain) {
      return '应用结果未确认，请检查 OpenClash 状态后重试';
    }
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
    final palette = AppPalette.of(context);
    return widget.builder(
        context,
        DashboardControlCards(
          activityLabel: _showAppBarActivity ? tr(_appBarActivityLabel) : null,
          refresh: _refreshPage,
          currentYaml: CurrentYamlCard(
            activeConfig: _activeConfig,
            loading: _loadingConfig,
            switching: _switchingConfig,
            operationBusy: _operationBusy,
            message: _configMessage,
            messageIsError: _configMessageIsError,
            cardBg: palette.surface,
            cardBorder: palette.border,
            textColor: palette.textPrimary,
            hintColor: palette.textSecondary,
            onRefresh: () => unawaited(_loadActiveConfig()),
            onSwitch: _chooseActiveConfig,
            onEdit: _editConfig,
          ),
          operations: ClashOperationsCard(
            restartLabel: _restartStatusLabel,
            busy: _operationBusy,
            flushingDns: _flushingDns,
            closingConnections: _closingConnections,
            onRestart: _restartOpenClash,
            onFlushDns: _flushDnsCache,
            onCloseConnections: _closeAllConnections,
          ),
          quickSettings: OpenClashQuickSettingsCard(
            settings: _quickSettings,
            loading: _loadingQuickSettings,
            busy: _operationBusy,
            cardBg: palette.surface,
            cardBorder: palette.border,
            textColor: palette.textPrimary,
            hintColor: palette.textSecondary,
            onRunVariantChanged: _changeRunVariant,
            onProxyModeChanged: _changeProxyMode,
            onAreaBypassChanged: _changeAreaBypass,
            onSnifferChanged: _changeSniffer,
            onDnsProxyChanged: _changeDnsProxy,
            onStreamUnlockChanged: _changeStreamUnlock,
          ),
        ));
  }
}

class DashboardControlCards {
  final Widget currentYaml, operations, quickSettings;
  final String? activityLabel;
  final Future<void> Function() refresh;
  const DashboardControlCards(
      {required this.currentYaml,
      required this.operations,
      required this.quickSettings,
      required this.activityLabel,
      required this.refresh});
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
