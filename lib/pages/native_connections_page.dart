import '../l10n/app_locale.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import '../services/clash_data_hub.dart';
import '../services/clash_service.dart';
import '../services/web_panel_service.dart';
import '../theme/app_theme.dart';
import '../utils/traffic_formatter.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/connection_detail_sheet.dart';

class NativeConnectionsPage extends StatefulWidget {
  const NativeConnectionsPage({super.key});

  @override
  State<NativeConnectionsPage> createState() => _NativeConnectionsPageState();
}

class _NativeConnectionsPageState extends State<NativeConnectionsPage>
    with WidgetsBindingObserver {
  Timer? _timer;
  Timer? _clockTimer;
  bool _loading = true;
  String? _error;
  Future<void>? _fetchFuture;
  bool _forceFetchRequested = false;

  List<ConnectionEntry> _connections = [];
  Map<String, int> _prevConnUpload = {};
  Map<String, int> _prevConnDownload = {};
  Map<String, int> _connUpSpeed = {};
  Map<String, int> _connDownSpeed = {};

  String _connSortBy = 'time_desc';
  bool _chainFullDisplay = true;
  String _filterIp = '';
  int _lastSnapshotSequence = 0;
  final ClashDataHub _dataHub = ClashDataHub.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dataHub.addListener(_handleDataHubChanged);
    WebPanelSync.instance.registerConnections(
      reload: () => _fetchData(force: true),
    );
    _fetchData();
    _startTimers();
  }

  void _startTimers() {
    _timer?.cancel();
    _clockTimer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _fetchData());
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _connections.isNotEmpty) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _timer?.cancel();
    _clockTimer?.cancel();
    if (state == AppLifecycleState.resumed) {
      _prevConnUpload.clear();
      _prevConnDownload.clear();
      _dataHub.resetBaseline();
      _startTimers();
      _fetchData(force: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dataHub.removeListener(_handleDataHubChanged);
    WebPanelSync.instance.unregisterConnections();
    _timer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
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
      } while (_forceFetchRequested);
    } finally {
      _fetchFuture = null;
    }
  }

  Future<void> _performFetch({required bool force}) async {
    try {
      if (!ClashService.instance.isConfigured) {
        if (mounted) {
          setState(() {
            _loading = false;
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
          _error = '错误：$e';
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
    // ClashDataHub.sequence is globally monotonic; identical sequences mean this
    // page has already rendered the snapshot, including resetBaseline updates.
    if (!mounted || snapshot.sequence == _lastSnapshotSequence) return;
    final connections = snapshot.connections;

    final newUpSpeed = <String, int>{};
    final newDownSpeed = <String, int>{};
    for (final c in connections) {
      final prevUp = _prevConnUpload[c.id];
      final prevDown = _prevConnDownload[c.id];
      if (prevUp != null && prevDown != null) {
        final calculatedUp = (c.upload - prevUp).clamp(0, 999999999).toInt();
        final calculatedDown =
            (c.download - prevDown).clamp(0, 999999999).toInt();
        newUpSpeed[c.id] = c.apiUpSpeed > 0 ? c.apiUpSpeed : calculatedUp;
        newDownSpeed[c.id] =
            c.apiDownSpeed > 0 ? c.apiDownSpeed : calculatedDown;
      } else {
        newUpSpeed[c.id] = c.apiUpSpeed;
        newDownSpeed[c.id] = c.apiDownSpeed;
      }
    }
    _prevConnUpload = {for (final c in connections) c.id: c.upload};
    _prevConnDownload = {for (final c in connections) c.id: c.download};
    _lastSnapshotSequence = snapshot.sequence;

    setState(() {
      _loading = false;
      _error = null;
      _connections = connections;
      _connUpSpeed = newUpSpeed;
      _connDownSpeed = newDownSpeed;
    });
  }

  String _formatBytes(int bytes) => TrafficFormatter.formatBytes(bytes);

  String _formatSpeed(double bytes) => TrafficFormatter.formatSpeed(bytes);

  String _formatElapsed(DateTime startTime) {
    final elapsed = DateTime.now().difference(startTime);
    if (elapsed.inSeconds < 60) return '新连接';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}分钟前';
    return '${elapsed.inHours}小时前';
  }

  List<ConnectionEntry> get _filteredSortedConnections {
    var list = List<ConnectionEntry>.from(_connections);
    if (_filterIp.isNotEmpty) {
      list = list.where((c) => c.sourceIp == _filterIp).toList();
    }
    switch (_connSortBy) {
      case 'time_asc':
        list.sort((a, b) => a.startTime.compareTo(b.startTime));
        break;
      case 'down_desc':
        list.sort((a, b) => b.download.compareTo(a.download));
        break;
      case 'up_desc':
        list.sort((a, b) => b.upload.compareTo(a.upload));
        break;
      case 'down_speed_desc':
        list.sort(
          (a, b) =>
              (_connDownSpeed[b.id] ?? 0).compareTo(_connDownSpeed[a.id] ?? 0),
        );
        break;
      case 'up_speed_desc':
        list.sort(
          (a, b) =>
              (_connUpSpeed[b.id] ?? 0).compareTo(_connUpSpeed[a.id] ?? 0),
        );
        break;
      default:
        list.sort((a, b) => b.startTime.compareTo(a.startTime));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.of(context);
    final bgColor = palette.pageBackground;
    final cardBg = palette.surface;
    final cardBorder = palette.border;
    final textPrimary = palette.textPrimary;
    final textSecondary = palette.textSecondary;
    final dividerColor = palette.border;
    final chainColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: _filterIp.isEmpty
            ? Text(
                tr('连接'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              )
            : GestureDetector(
                onTap: () => setState(() => _filterIp = ''),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr('连接'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: chainColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: chainColor.withValues(alpha: 0.4),
                          width: 0.6,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _filterIp,
                            style: TextStyle(fontSize: 11, color: chainColor),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.close, size: 12, color: chainColor),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        centerTitle: true,
        actions: [
          GestureDetector(
            onTap: () => setState(() => _chainFullDisplay = !_chainFullDisplay),
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _chainFullDisplay
                    ? chainColor.withValues(alpha: 0.10)
                    : Colors.transparent,
                border: Border.all(
                  color: _chainFullDisplay ? chainColor : textSecondary,
                  width: 0.8,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: AdaptiveSingleLineText(
                tr(_chainFullDisplay ? '完整链路' : '仅首尾'),
                style: TextStyle(
                  fontSize: 12,
                  color: _chainFullDisplay ? chainColor : textSecondary,
                  fontWeight:
                      _chainFullDisplay ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: tr('排序'),
            icon: Icon(Icons.sort_rounded, color: textSecondary, size: 20),
            initialValue: _connSortBy,
            onSelected: (v) => setState(() => _connSortBy = v),
            itemBuilder: (_) => [
              for (final e in const [
                ('time_desc', '时间 新→旧'),
                ('time_asc', '时间 旧→新'),
                ('down_desc', '下载量'),
                ('up_desc', '上传量'),
                ('down_speed_desc', '下载速度'),
                ('up_speed_desc', '上传速度'),
              ])
                PopupMenuItem(
                  value: e.$1,
                  child: AdaptiveSingleLineText(
                    tr(e.$2),
                    alignment: Alignment.centerLeft,
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      fontSize: 13,
                      color: _connSortBy == e.$1 ? chainColor : textPrimary,
                    ),
                  ),
                ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: dividerColor),
        ),
      ),
      body: _buildBody(
        isDark: isDark,
        bgColor: bgColor,
        cardBg: cardBg,
        cardBorder: cardBorder,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
        chainColor: chainColor,
      ),
    );
  }

  Widget _buildBody({
    required bool isDark,
    required Color bgColor,
    required Color cardBg,
    required Color cardBorder,
    required Color textPrimary,
    required Color textSecondary,
    required Color chainColor,
  }) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: chainColor));
    }
    if (_error != null) {
      return _buildRefreshableState(
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
                  color: chainColor,
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
      );
    }

    final list = _filteredSortedConnections;

    if (list.isEmpty) {
      return _buildRefreshableState(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lan_outlined, size: 48, color: textSecondary),
            const SizedBox(height: 12),
            Text(
              tr('暂无活跃连接'),
              style: TextStyle(color: textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final c = list[i];
        final upSpeed = _connUpSpeed[c.id] ?? 0;
        final downSpeed = _connDownSpeed[c.id] ?? 0;
        return GestureDetector(
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => ConnectionDetailSheet(
              conn: c,
              upSpeed: upSpeed,
              downSpeed: downSpeed,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cardBorder, width: 0.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 第一行：来源 IP + 连接时间 + 关闭
                Row(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(
                        () => _filterIp =
                            _filterIp == c.sourceIp ? '' : c.sourceIp,
                      ),
                      child: Text(
                        c.sourceIp,
                        style: TextStyle(fontSize: 11, color: textSecondary),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      tr(_formatElapsed(c.startTime)),
                      style: TextStyle(fontSize: 10, color: textSecondary),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        ClashService.instance
                            .closeConnection(c.id)
                            .catchError((_) {});
                        _dataHub.removeConnection(c.id);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // 第二行：目标主机
                Text(
                  c.host,
                  style: TextStyle(fontSize: 12, color: textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // 第三行：代理链路
                Text(
                  () {
                    if (_chainFullDisplay) return c.chain;
                    final parts = c.chain.split(' → ');
                    if (parts.length <= 2) return c.chain;
                    return '${parts.first} → ${parts.last}';
                  }(),
                  style: TextStyle(fontSize: 10, color: chainColor),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // 第四行：规则 + 速度 + 累计流量
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.rule,
                        style: TextStyle(fontSize: 10, color: textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '↓${_formatSpeed(downSpeed.toDouble())} ↑${_formatSpeed(upSpeed.toDouble())}  ↓${_formatBytes(c.download)} ↑${_formatBytes(c.upload)}',
                      style: TextStyle(fontSize: 10, color: textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRefreshableState({
    required Widget child,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final topPadding =
            (constraints.maxHeight * 0.32).clamp(48.0, 180.0).toDouble();
        return ListView(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, topPadding, 16, 24),
          children: [Center(child: child)],
        );
      },
    );
  }
}
