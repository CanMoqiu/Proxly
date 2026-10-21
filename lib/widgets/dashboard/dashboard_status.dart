import '../../l10n/app_locale.dart';
import 'package:flutter/material.dart';
import 'clash_status_card.dart';
import 'clash_overview_card.dart';
import 'clash_traffic_card.dart';
import 'dart:async';
import '../../services/clash_service.dart';
import '../../services/clash_data_hub.dart';
import '../../services/core_version_lookup.dart';
import '../../services/connection_settings_store.dart';
import '../../services/connection_feedback.dart';
import '../../services/controller_connection_state.dart';
import '../../services/openclash_restart_coordinator.dart';

class DashboardStatus extends StatefulWidget {
  final bool active;
  final Widget Function(BuildContext, DashboardStatusCards) builder;
  final OpenClashRestartCoordinator? restartCoordinator;

  const DashboardStatus({
    super.key,
    this.active = true,
    required this.builder,
    this.restartCoordinator,
  });

  @override
  State<DashboardStatus> createState() => _DashboardStatusState();
}

class _DashboardStatusState extends State<DashboardStatus>
    with WidgetsBindingObserver {
  bool _foreground = true;
  Timer? _timer;
  bool _loading = true;
  String? _error;

  int _activeConnections = 0;
  int _totalDownload = 0;
  int _totalUpload = 0;
  List<ProviderTraffic> _displayProviders = [];

  final List<double> _downloadSpeeds = List.filled(60, 0, growable: true);
  final List<double> _uploadSpeeds = List.filled(60, 0, growable: true);
  double _currentDownSpeed = 0;
  double _currentUpSpeed = 0;

  Future<void>? _fetchFuture;
  bool _forceFetchRequested = false;
  bool _connectionReloadPending = false;
  bool _clashOnline = false;
  bool _recoveryPending = false;
  int _recoveryRevision = 0;
  String _coreVersion = '--';
  final _versionLookup = CoreVersionLookup(
    load: () async =>
        (await ClashService.instance.getVersionInfo())['coreVersion'],
  );
  int _lastSnapshotSequence = 0;
  final ClashDataHub _dataHub = ClashDataHub.instance;
  final _connection = ControllerConnectionState.instance;
  late final OpenClashRestartCoordinator _restartCoordinator;
  late OpenClashRestartPhase _lastRestartPhase;

  @override
  void initState() {
    super.initState();
    _restartCoordinator =
        widget.restartCoordinator ?? OpenClashRestartCoordinator.instance;
    _lastRestartPhase = _restartCoordinator.phase;
    WidgetsBinding.instance.addObserver(this);
    _dataHub.addListener(_handleDataHubChanged);
    _connection.addListener(_handleConnectionStateChanged);
    ConnectionSettingsStore.instance.addListener(
      _handleConnectionSettingsChanged,
    );
    _restartCoordinator.addListener(_handleRestartStateChanged);
    _syncPolling();
  }

  Future<void> _loadVersionInfo({bool force = true}) async {
    if (!widget.active || !_foreground) return;
    await _versionLookup.refresh(force: force);
    if (mounted && _coreVersion != _versionLookup.value) {
      setState(() => _coreVersion = _versionLookup.value);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dataHub.removeListener(_handleDataHubChanged);
    _connection.removeListener(_handleConnectionStateChanged);
    ConnectionSettingsStore.instance.removeListener(
      _handleConnectionSettingsChanged,
    );
    _restartCoordinator.removeListener(_handleRestartStateChanged);
    _timer?.cancel();
    _versionLookup.reset();
    super.dispose();
  }

  void _handleConnectionStateChanged() {
    if (!mounted || _connection.phase == ControllerConnectionPhase.restarting) {
      return;
    }
    final online = _connection.phase == ControllerConnectionPhase.online;
    final reconnected = online && !_clashOnline;
    setState(() {
      _clashOnline = online;
      _error = _connection.message;
      _loading = false;
      if (!online) {
        _recoveryPending = true;
      } else if (_recoveryPending) {
        _recoveryRevision++;
        _recoveryPending = false;
      }
    });
    if (reconnected) {
      unawaited(_loadVersionInfo());
      unawaited(_fetchData(force: true));
    }
  }

  void _handleRestartStateChanged() {
    if (!mounted) return;
    final previous = _lastRestartPhase;
    final current = _restartCoordinator.phase;
    setState(() {
      _lastRestartPhase = current;
      if (_restartCoordinator.isBusy) {
        _loading = false;
        _error = null;
      }
    });
    if (current == OpenClashRestartPhase.succeeded && current != previous) {
      _lastSnapshotSequence = 0;
      _dataHub.resetBaseline(clearSnapshot: true);
      unawaited(_loadVersionInfo());
      unawaited(_fetchData(force: true));
    }
  }

  void _handleConnectionSettingsChanged() {
    if (!mounted ||
        ConnectionSettingsStore.instance.lastChange ==
            ConnectionSettingsChange.sshPassword) {
      return;
    }
    _connectionReloadPending = true;
    _versionLookup.reset();
    setState(() {
      _coreVersion = '--';
      _clashOnline = false;
    });
    _lastSnapshotSequence = 0;
    _dataHub.resetBaseline(clearSnapshot: true);
    unawaited(_reloadConnectionSettings());
  }

  Future<void> _reloadConnectionSettings() async {
    await ClashService.instance.loadConfig();
    await _loadVersionInfo();
    if (!mounted) return;
    _connectionReloadPending = false;
    await _fetchData(force: true);
  }

  @override
  void didUpdateWidget(covariant DashboardStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncPolling();
  }

  void _syncPolling() {
    _timer?.cancel();
    _timer = null;
    if (!widget.active || !_foreground) return;
    _lastSnapshotSequence = 0;
    _dataHub.resetBaseline();
    unawaited(_fetchData(force: true));
    unawaited(_loadVersionInfo(force: false));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _fetchData());
  }

  Future<void> _fetchData({bool force = false}) {
    if (force) _forceFetchRequested = true;
    final active = _fetchFuture;
    if (active != null) return active;

    final future = _runFetchQueue();
    _fetchFuture = future;
    return future;
  }

  Future<void> _runFetchQueue() async {
    try {
      do {
        final force = _forceFetchRequested;
        _forceFetchRequested = false;
        await _performFetch(force: force);
        if (_connectionReloadPending && mounted) {
          _connectionReloadPending = false;
          _forceFetchRequested = true;
        }
      } while (_forceFetchRequested);
    } finally {
      _fetchFuture = null;
    }
  }

  Future<void> _performFetch({required bool force}) async {
    if (!widget.active || !_foreground) return;
    if (_restartCoordinator.isBusy) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }
      return;
    }
    try {
      if (!ClashService.instance.isConfigured) {
        if (mounted) {
          setState(() {
            _loading = false;
            _clashOnline = false;
            _recoveryPending = true;
            _error = '请先在设置页填写 Clash 地址';
          });
        }
        return;
      }

      final generation = _connection.generation;
      final snapshot = await _dataHub.refresh(force: force);
      if (generation != _connection.generation || !_canApplySnapshot) return;
      _applyRealtimeSnapshot(snapshot);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (!_restartCoordinator.isBusy) {
            _clashOnline = false;
            _recoveryPending = true;
            _error = ConnectionFeedback.forError(e);
          }
        });
      }
    }
  }

  void _handleDataHubChanged() {
    final snapshot = _dataHub.snapshot;
    if (snapshot == null || !mounted || !widget.active || !_foreground) return;
    // A reset baseline is cached data, not evidence of a recovered connection.
    if (snapshot.updatedAt.millisecondsSinceEpoch == 0) return;
    if (!_canApplySnapshot) return;
    _applyRealtimeSnapshot(snapshot);
  }

  bool get _canApplySnapshot =>
      _connection.phase != ControllerConnectionPhase.offline &&
      _connection.phase != ControllerConnectionPhase.unauthorized &&
      _connection.phase != ControllerConnectionPhase.restarting;

  void _applyRealtimeSnapshot(ClashRealtimeSnapshot snapshot) {
    if (!mounted || snapshot.sequence == _lastSnapshotSequence) return;
    // Cold launches can happen offline. Query again on reconnection and keep
    // retrying a temporarily unavailable version endpoint at a bounded rate.
    final reconnected = !_clashOnline;
    _lastSnapshotSequence = snapshot.sequence;

    _downloadSpeeds.removeAt(0);
    _downloadSpeeds.add(snapshot.downloadSpeed);
    _uploadSpeeds.removeAt(0);
    _uploadSpeeds.add(snapshot.uploadSpeed);

    setState(() {
      if (_recoveryPending) {
        _recoveryRevision++;
        _recoveryPending = false;
      }
      _loading = false;
      _error = null;
      _clashOnline = true;
      _activeConnections = snapshot.activeConnections;
      _totalDownload = snapshot.downloadTotal;
      _totalUpload = snapshot.uploadTotal;
      _displayProviders = snapshot.providers;
      _currentDownSpeed = snapshot.downloadSpeed;
      _currentUpSpeed = snapshot.uploadSpeed;
    });
    unawaited(_loadVersionInfo(force: reconnected));
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    return widget.builder(
        context,
        DashboardStatusCards(
          activityLabel: _loading && widget.active ? tr('正在读取...') : null,
          recoveryRevision: _recoveryRevision,
          status: ClashStatusCard(
              loading: _loading && widget.active,
              error: _error,
              online: _clashOnline,
              coreVersion: _coreVersion,
              restartBusy: _restartCoordinator.isBusy,
              restartFailed:
                  _restartCoordinator.phase == OpenClashRestartPhase.failed,
              onRetry: () => _fetchData(force: true)),
          traffic: ClashTrafficCard(providers: _displayProviders),
          overview: ClashOverviewCard(
              activeConnections: _activeConnections,
              totalDownload: _totalDownload,
              totalUpload: _totalUpload,
              downloadSpeeds: List.of(_downloadSpeeds),
              uploadSpeeds: List.of(_uploadSpeeds),
              currentDownSpeed: _currentDownSpeed,
              currentUpSpeed: _currentUpSpeed),
        ));
  }
}

class DashboardStatusCards {
  final Widget status, traffic, overview;
  final String? activityLabel;
  final int recoveryRevision;
  const DashboardStatusCards(
      {required this.status,
      required this.traffic,
      required this.overview,
      required this.activityLabel,
      required this.recoveryRevision});
}
