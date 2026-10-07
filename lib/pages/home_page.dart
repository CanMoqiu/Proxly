import '../l10n/app_locale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import '../services/clash_service.dart';
import '../services/clash_data_hub.dart';
import '../services/core_version_lookup.dart';
import '../services/connection_settings_store.dart';
import '../services/openclash_restart_coordinator.dart';
import '../services/web_panel_service.dart';
import '../theme/app_theme.dart';
import '../utils/traffic_formatter.dart';
import '../widgets/adaptive_ui.dart';
import 'clash_control_center_page.dart';
import 'proxy_page.dart';

class HomePage extends StatefulWidget {
  final bool showConsoleButton;
  final OpenClashRestartCoordinator? restartCoordinator;

  const HomePage({
    super.key,
    this.showConsoleButton = false,
    this.restartCoordinator,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
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
  String _coreVersion = '--';
  final _versionLookup = CoreVersionLookup(
    load: () async =>
        (await ClashService.instance.getVersionInfo())['coreVersion'],
  );
  int _lastSnapshotSequence = 0;
  final ClashDataHub _dataHub = ClashDataHub.instance;
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
    ConnectionSettingsStore.instance.addListener(
      _handleConnectionSettingsChanged,
    );
    _restartCoordinator.addListener(_handleRestartStateChanged);
    _fetchData();
    _loadVersionInfo();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _fetchData());
  }

  Future<void> _loadVersionInfo({bool force = true}) async {
    await _versionLookup.refresh(force: force);
    if (mounted && _coreVersion != _versionLookup.value) {
      setState(() => _coreVersion = _versionLookup.value);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dataHub.removeListener(_handleDataHubChanged);
    ConnectionSettingsStore.instance.removeListener(
      _handleConnectionSettingsChanged,
    );
    _restartCoordinator.removeListener(_handleRestartStateChanged);
    _timer?.cancel();
    _versionLookup.reset();
    super.dispose();
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _timer?.cancel();
    if (state == AppLifecycleState.resumed) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _fetchData());
      _lastSnapshotSequence = 0;
      _dataHub.resetBaseline();
      _fetchData(force: true);
    }
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
      // Refresh devMode during initialization and after returning from settings;
      // avoid reading SharedPreferences on every polling cycle.

      if (!ClashService.instance.isConfigured) {
        if (mounted) {
          setState(() {
            _loading = false;
            _clashOnline = false;
            _error = '请先在设置页填写 Clash 地址';
          });
        }
        return;
      }

      final snapshot = await _dataHub.refresh(force: force);
      _applyRealtimeSnapshot(snapshot);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (!_restartCoordinator.isBusy) {
            _clashOnline = false;
            _error = '错误：$e';
          }
        });
      }
    }
  }

  void _handleDataHubChanged() {
    final snapshot = _dataHub.snapshot;
    if (snapshot == null || !mounted) return;
    _applyRealtimeSnapshot(snapshot);
  }

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

  String _formatBytes(int bytes) => TrafficFormatter.formatBytes(bytes);

  String _formatSpeed(double bytes) => TrafficFormatter.formatSpeed(bytes);

  Future<void> _openDashboard() async {
    await WebPanelSync.instance.save();
    if (!mounted) return;
    await Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => const ProxyPage(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: SlideTransition(
              position:
                  Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: child,
            ),
          );
        },
      ),
    );
    await WebPanelSync.instance.reload();
    await WebPanelSync.instance.reloadConnections();
    if (mounted) {
      _lastSnapshotSequence = 0;
      _dataHub.resetBaseline();
      await _fetchData(force: true);
    }
  }

  Future<void> _openControlCenter() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ClashControlCenterPage()),
    );
    if (!mounted) return;
    _lastSnapshotSequence = 0;
    _dataHub.resetBaseline(clearSnapshot: true);
    await Future.wait([_loadVersionInfo(), _fetchData(force: true)]);
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final palette = AppPalette.of(context);
    final bgColor = palette.pageBackground;
    final dividerColor = palette.border;
    final cardBg = palette.surface;
    final cardBorder = palette.border;
    final textPrimary = palette.textPrimary;
    final textSecondary = palette.textSecondary;
    final primary = Theme.of(context).colorScheme.primary;
    final appBar = HomeAppBar(
      showConsoleButton: widget.showConsoleButton,
      backgroundColor: bgColor,
      foregroundColor: textPrimary,
      dividerColor: dividerColor,
      onConsolePressed: _openDashboard,
      onControlCenterPressed: _openControlCenter,
    );
    final restartBusy = _restartCoordinator.isBusy;
    final restartFailed =
        _restartCoordinator.phase == OpenClashRestartPhase.failed;

    if (_loading && !restartBusy && !restartFailed) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: appBar,
        body: Center(child: CircularProgressIndicator(color: primary)),
      );
    }

    if (_error != null && !restartBusy && !restartFailed) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: appBar,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 48, color: textSecondary),
              const SizedBox(height: 12),
              Text(
                tr(_error!),
                style: TextStyle(color: textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _fetchData(force: true);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: AdaptiveSingleLineText(
                    tr('重试'),
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    double maxChartSpeed = [
      ..._downloadSpeeds,
      ..._uploadSpeeds,
    ].fold(0.0, (a, b) => a > b ? a : b);
    if (maxChartSpeed < 1024) maxChartSpeed = 1024;
    final statusColor = restartBusy
        ? palette.warning
        : restartFailed
            ? palette.error
            : _clashOnline
                ? palette.success
                : palette.textSecondary;
    final statusLabel = restartBusy
        ? '重启中'
        : restartFailed
            ? '重启失败'
            : _clashOnline
                ? '运行中'
                : '未连接';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: appBar,
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: AdaptiveScrollPadding.page(context, top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Clash status
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cardBorder, width: 0.5),
              ),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Controller status and address.
                  Row(
                    children: [
                      Text(
                        tr('运行状态'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        tr(statusLabel),
                        style: TextStyle(
                          fontSize: 12,
                          color: restartBusy || restartFailed || _clashOnline
                              ? statusColor
                              : textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Core version.
                  Row(
                    children: [
                      Text(
                        tr('内核版本'),
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: palette.inputBackground,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _coreVersion,
                            style: TextStyle(
                              fontSize: 11,
                              color: textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (_displayProviders.isNotEmpty) ...[
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cardBorder, width: 0.5),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('流量信息'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._displayProviders.asMap().entries.map((entry) {
                      final i = entry.key;
                      final p = entry.value;
                      final trafficLabel = formatHomeProviderTrafficLabel(p);

                      final Color barColor;
                      barColor = switch (p.remainingLevel) {
                        ProviderTrafficLevel.healthy => palette.success,
                        ProviderTrafficLevel.warning => palette.warning,
                        ProviderTrafficLevel.critical => palette.error,
                      };

                      return Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                HomeSubscriptionTrafficRow(
                                  name: p.name,
                                  trafficLabel: trafficLabel,
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                ),
                                const SizedBox(height: 5),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: p.remainingPercentage,
                                    backgroundColor: palette.inputBackground,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      barColor,
                                    ),
                                    minHeight: 4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (i < _displayProviders.length - 1)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                              ),
                              child: Divider(
                                color: palette.border,
                                height: 1,
                                thickness: 0.5,
                              ),
                            ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cardBorder, width: 0.5),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('运行概览'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: tr('活跃连接'),
                          value: '$_activeConnections',
                          cardBg: palette.inputBackground,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          label: tr('累计下载'),
                          value: _formatBytes(_totalDownload),
                          valueColor: primary,
                          cardBg: palette.inputBackground,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          label: tr('累计上传'),
                          value: _formatBytes(_totalUpload),
                          valueColor: palette.success,
                          cardBg: palette.inputBackground,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 100,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 50,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (final label in [
                                _formatSpeed(maxChartSpeed),
                                _formatSpeed(maxChartSpeed * 0.75),
                                _formatSpeed(maxChartSpeed * 0.5),
                                _formatSpeed(maxChartSpeed * 0.25),
                                '0B/s',
                              ])
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 9,
                                          height: 1,
                                          color: textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: CustomPaint(
                            size: const Size(double.infinity, 100),
                            painter: _SpeedChartPainter(
                              downloadSpeeds: _downloadSpeeds,
                              uploadSpeeds: _uploadSpeeds,
                              gridColor: palette.border,
                              maxSpeed: maxChartSpeed,
                              primary: primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 56),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '60s',
                          style: TextStyle(fontSize: 9, color: textSecondary),
                        ),
                        Text(
                          '30s',
                          style: TextStyle(fontSize: 9, color: textSecondary),
                        ),
                        Text(
                          '0s',
                          style: TextStyle(fontSize: 9, color: textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _SpeedLegend(
                        color: primary,
                        label: '↓ ${_formatSpeed(_currentDownSpeed)}',
                      ),
                      const SizedBox(width: 24),
                      _SpeedLegend(
                        color: const Color(0xFF1D9E75),
                        label: '↑ ${_formatSpeed(_currentUpSpeed)}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatHomeProviderTrafficLabel(ProviderTraffic provider) {
  if (provider.isUnlimited) {
    return '${TrafficFormatter.formatBytes(provider.used)} / ${tr('无限制')}';
  }
  return '${TrafficFormatter.formatBytes(provider.remaining)} / '
      '${TrafficFormatter.formatBytes(provider.total)}';
}

class HomeSubscriptionTrafficRow extends StatelessWidget {
  final String name;
  final String trafficLabel;
  final Color textPrimary;
  final Color textSecondary;

  const HomeSubscriptionTrafficRow({
    super.key,
    required this.name,
    required this.trafficLabel,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AdaptiveMarqueeText(
            name,
            style: TextStyle(fontSize: 12, color: textPrimary),
            gap: 32,
            startDelay: const Duration(seconds: 3),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          trafficLabel,
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 11, color: textSecondary),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final Color cardBg;
  final Color textPrimary;
  final Color textSecondary;

  const _StatCard({
    required this.label,
    required this.value,
    this.valueColor,
    required this.cardBg,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        children: [
          AdaptiveSingleLineText(
            tr(label),
            style: TextStyle(fontSize: 10, color: textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SpeedLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _SpeedLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 2,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 4),
        Text(tr(label), style: TextStyle(fontSize: 10, color: color)),
      ],
    );
  }
}

class _SpeedChartPainter extends CustomPainter {
  final List<double> downloadSpeeds;
  final List<double> uploadSpeeds;
  final Color gridColor;
  final double maxSpeed;
  final Color primary;

  _SpeedChartPainter({
    required this.downloadSpeeds,
    required this.uploadSpeeds,
    required this.gridColor,
    required this.maxSpeed,
    required this.primary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final scale = maxSpeed > 0 ? (size.height - 4) / maxSpeed : 1.0;
    final step = size.width / (downloadSpeeds.length - 1);

    void drawLine(List<double> speeds, Color color) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (int i = 0; i < speeds.length; i++) {
        final x = i * step;
        final y = size.height - (speeds[i] * scale).clamp(0, size.height - 2);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }

    drawLine(downloadSpeeds, primary);
    drawLine(uploadSpeeds, const Color(0xFF1D9E75));
  }

  @override
  bool shouldRepaint(_SpeedChartPainter old) =>
      old.gridColor != gridColor ||
      old.maxSpeed != maxSpeed ||
      old.primary != primary ||
      old.downloadSpeeds.last != downloadSpeeds.last ||
      old.uploadSpeeds.last != uploadSpeeds.last;
}

class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool showConsoleButton;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color dividerColor;
  final VoidCallback onConsolePressed;
  final VoidCallback onControlCenterPressed;

  const HomeAppBar({
    super.key,
    required this.showConsoleButton,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.dividerColor,
    required this.onConsolePressed,
    required this.onControlCenterPressed,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 0.5);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: backgroundColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leading: showConsoleButton
          ? Tooltip(
              message: tr('控制台'),
              child: _DashboardButton(
                key: const ValueKey('home_console_button'),
                color: foregroundColor,
                onTap: onConsolePressed,
              ),
            )
          : null,
      title: Text(
        tr('首页'),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: foregroundColor,
        ),
      ),
      centerTitle: true,
      actions: [
        IconButton(
          key: const ValueKey('home_control_center_button'),
          tooltip: tr('Clash 控制中心'),
          onPressed: onControlCenterPressed,
          style: IconButton.styleFrom(overlayColor: Colors.transparent),
          icon: Icon(Icons.tune_rounded, color: foregroundColor),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(height: 0.5, color: dividerColor),
      ),
    );
  }
}

// Console entry button

class _DashboardButton extends StatefulWidget {
  final VoidCallback onTap;
  final Color color;

  const _DashboardButton({super.key, required this.onTap, required this.color});

  @override
  State<_DashboardButton> createState() => _DashboardButtonState();
}

class _DashboardButtonState extends State<_DashboardButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
    reverseDuration: const Duration(milliseconds: 200),
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 1.0,
    end: 0.78,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: ScaleTransition(
          scale: _scale,
          child: SvgPicture.asset(
            'assets/icons/console.svg',
            colorFilter: ColorFilter.mode(widget.color, BlendMode.srcIn),
            width: 22,
            height: 22,
            semanticsLabel: 'Zashboard',
          ),
        ),
      ),
    );
  }
}
