import 'dart:async';
import 'package:flutter/material.dart';

import '../app_route_observer.dart';
import '../l10n/app_locale.dart';
import '../services/dashboard_layout_store.dart';
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
  const HomePage(
      {super.key,
      this.showConsoleButton = false,
      this.active = true,
      this.autoLoad = true,
      this.restartCoordinator});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with RouteAware {
  final _layout = DashboardLayoutStore();
  ModalRoute<void>? _route;
  bool _routeVisible = true;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLayout());
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
  void didPushNext() => setState(() => _routeVisible = false);
  @override
  void didPopNext() => setState(() => _routeVisible = true);

  @override
  void dispose() {
    shellRouteObserver.unsubscribe(this);
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
                      editing: _editing,
                      activityLabel: controls.activityLabel,
                      onCustomizePressed: () =>
                          setState(() => _editing = !_editing)),
                  body: DashboardCardList(
                      layout: _layout,
                      editing: _editing,
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
