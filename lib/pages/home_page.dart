import 'dart:async';
import 'package:flutter/material.dart';

import '../app_route_observer.dart';
import '../l10n/app_locale.dart';
import '../services/dashboard_layout_store.dart';
import '../services/connection_settings_store.dart';
import '../services/router_detection_session.dart';
import '../services/router_tool.dart';
import '../widgets/app_popup.dart';
import '../services/openclash_restart_coordinator.dart';
import '../services/web_panel_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_feedback.dart';
import '../widgets/dashboard/dashboard_card_list.dart';
import '../widgets/dashboard/dashboard_controls.dart';
import '../widgets/dashboard/dashboard_status.dart';
import '../widgets/dashboard/home_app_bar.dart';
import 'proxy_page.dart';

class HomePage extends StatefulWidget {
  final bool showConsoleButton;
  final bool active;
  final bool autoLoad;
  final OpenClashRestartCoordinator? restartCoordinator;
  final RouterDetectionSession? detectionSession;
  const HomePage(
      {super.key,
      this.showConsoleButton = false,
      this.active = true,
      this.autoLoad = true,
      this.restartCoordinator,
      this.detectionSession});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with RouteAware, WidgetsBindingObserver {
  final _layout = DashboardLayoutStore();
  ModalRoute<void>? _route;
  bool _routeVisible = true;
  bool _editing = false;
  bool _foreground = true;
  bool _selectionScheduled = false;
  bool _selectingTool = false;
  int? _promptedRevision;
  RouterDetectionSession get _detection =>
      widget.detectionSession ?? RouterDetectionSession.instance;

  void _scheduleToolSelection() {
    if (!mounted || _selectionScheduled) return;
    _selectionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionScheduled = false;
      if (mounted) unawaited(_chooseRouterToolIfNeeded());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool get _canChooseTool =>
      mounted &&
      widget.active &&
      _routeVisible &&
      _foreground &&
      !_detection.isDetecting &&
      ModalRoute.of(context)?.isCurrent == true;

  Future<void> _chooseRouterToolIfNeeded() async {
    if (_selectingTool || !_canChooseTool) return;
    _selectingTool = true;
    int? presentedRevision;
    final store = ConnectionSettingsStore.instance;
    try {
      final request = await store.pendingRouterToolSelection();
      if (!mounted ||
          !_canChooseTool ||
          request == null ||
          _promptedRevision == request.revision) {
        return;
      }
      _promptedRevision = presentedRevision = request.revision;
      final selected = await AppPopup.sheet<RouterTool>(
          context: context,
          builder: (_) => AppOptionsSheet<RouterTool>(
                title: tr('选择代理软件'),
                description: tr('未能自动识别代理软件，请选择当前使用的软件。'),
                options: [
                  for (final tool in RouterTool.values)
                    AppSheetOption(
                      value: tool,
                      label: tool.label,
                      icon: Icons.hub_outlined,
                      subtitle:
                          tool == RouterTool.generic ? tr('仅使用通用控制器功能') : null,
                    )
                ],
              ));
      if (!mounted || selected == null) return;
      await store.confirmRouterTool(selected,
          expectedHost: request.host, expectedRevision: request.revision);
    } catch (_) {
      _promptedRevision = null;
      if (mounted) {
        AppFeedback.showSnackBar(context, tr('保存代理软件失败，请重试'),
            tone: AppFeedbackTone.error);
      }
    } finally {
      _selectingTool = false;
      if (mounted &&
          presentedRevision != null &&
          presentedRevision != store.revision) {
        _scheduleToolSelection();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _scheduleToolSelection();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadLayout());
    WidgetsBinding.instance.addObserver(this);
    ConnectionSettingsStore.instance.addListener(_scheduleToolSelection);
    _detection.addListener(_scheduleToolSelection);
    _scheduleToolSelection();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) _editing = false;
    if (oldWidget.detectionSession != widget.detectionSession) {
      (oldWidget.detectionSession ?? RouterDetectionSession.instance)
          .removeListener(_scheduleToolSelection);
      _detection.addListener(_scheduleToolSelection);
    }
    if (widget.active) _scheduleToolSelection();
  }

  Future<void> _loadLayout() async {
    try {
      await _layout.load();
    } catch (_) {
      if (mounted) {
        AppFeedback.showSnackBar(context, tr('读取首页布局失败'),
            tone: AppFeedbackTone.error);
      }
    }
  }

  Future<void> _saveLayout(Future<void> save) async {
    try {
      await save;
    } catch (_) {
      if (mounted) {
        AppFeedback.showSnackBar(context, tr('保存首页布局失败，请重试'),
            tone: AppFeedbackTone.error);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (identical(route, _route)) return;
    if (_route != null) shellRouteObserver.unsubscribe(this);
    _route = route;
    if (route != null) {
      _routeVisible = route.isCurrent;
      shellRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() => setState(() {
        _routeVisible = false;
        _editing = false;
      });
  @override
  void didPopNext() {
    setState(() => _routeVisible = true);
    _scheduleToolSelection();
  }

  @override
  void dispose() {
    shellRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    ConnectionSettingsStore.instance.removeListener(_scheduleToolSelection);
    _detection.removeListener(_scheduleToolSelection);
    _layout.dispose();
    super.dispose();
  }

  Future<void> _openConsole() async {
    await WebPanelSync.instance.save();
    if (!mounted) return;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const ProxyPage()));
    await WebPanelSync.instance.reload();
    await WebPanelSync.instance.reloadConnections();
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final palette = AppPalette.of(context);
    final active = widget.active && _routeVisible && widget.autoLoad;
    return ListenableBuilder(
        listenable: _layout,
        builder: (context, _) => DashboardStatus(
              active: active &&
                  [
                    DashboardCardId.status,
                    DashboardCardId.traffic,
                    DashboardCardId.overview
                  ].any(_layout.isVisible),
              restartCoordinator: widget.restartCoordinator,
              builder: (context, status) => DashboardControls(
                active: active,
                recoveryRevision: status.recoveryRevision,
                autoLoad: widget.autoLoad,
                refreshConfig: _layout.isVisible(DashboardCardId.currentYaml),
                refreshQuickSettings:
                    _layout.isVisible(DashboardCardId.quickSettings),
                restartCoordinator: widget.restartCoordinator,
                builder: (context, controls) => Scaffold(
                  backgroundColor: palette.pageBackground,
                  appBar: HomeAppBar(
                      showConsoleButton: widget.showConsoleButton,
                      backgroundColor: palette.pageBackground,
                      foregroundColor: palette.textPrimary,
                      dividerColor: palette.border,
                      onConsolePressed: _openConsole,
                      activityLabel: widget.active && _routeVisible
                          ? controls.activityLabel ?? status.activityLabel
                          : null),
                  body: DashboardCardList(
                      unavailable: {
                        if (!controls.supportsYaml) DashboardCardId.currentYaml,
                        if (!controls.supportsQuickSettings)
                          DashboardCardId.quickSettings
                      },
                      sshTrustNotice: controls.trustNotice,
                      layout: _layout,
                      editing: _editing,
                      onEditPressed: () => setState(() => _editing = !_editing),
                      onSave: _saveLayout,
                      cards: {
                        DashboardCardId.status: status.status,
                        DashboardCardId.currentYaml: controls.currentYaml,
                        DashboardCardId.operations: controls.operations,
                        DashboardCardId.quickSettings: controls.quickSettings,
                        DashboardCardId.traffic: status.traffic,
                        DashboardCardId.overview: status.overview,
                      }),
                ),
              ),
            ));
  }
}
