import '../l10n/app_locale.dart';
import 'package:flutter/foundation.dart';

import 'clash_service.dart';

class ClashRealtimeSnapshot {
  final int sequence;
  final DateTime updatedAt;
  final int downloadTotal;
  final int uploadTotal;
  final int activeConnections;
  final double downloadSpeed;
  final double uploadSpeed;
  final List<ConnectionEntry> connections;
  final List<ProviderTraffic> providers;

  const ClashRealtimeSnapshot({
    required this.sequence,
    required this.updatedAt,
    required this.downloadTotal,
    required this.uploadTotal,
    required this.activeConnections,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.connections,
    required this.providers,
  });

  ClashRealtimeSnapshot copyWith({
    int? sequence,
    DateTime? updatedAt,
    int? downloadTotal,
    int? uploadTotal,
    int? activeConnections,
    double? downloadSpeed,
    double? uploadSpeed,
    List<ConnectionEntry>? connections,
    List<ProviderTraffic>? providers,
  }) {
    return ClashRealtimeSnapshot(
      sequence: sequence ?? this.sequence,
      updatedAt: updatedAt ?? this.updatedAt,
      downloadTotal: downloadTotal ?? this.downloadTotal,
      uploadTotal: uploadTotal ?? this.uploadTotal,
      activeConnections: activeConnections ?? this.activeConnections,
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      uploadSpeed: uploadSpeed ?? this.uploadSpeed,
      connections: connections ?? this.connections,
      providers: providers ?? this.providers,
    );
  }
}

class ClashDataHub extends ChangeNotifier {
  ClashDataHub._();
  static final instance = ClashDataHub._();

  static const _cacheWindow = Duration(milliseconds: 750);

  ClashRealtimeSnapshot? _snapshot;
  Future<ClashRealtimeSnapshot>? _inFlight;
  int _sequence = 0;
  int _lastDownload = -1;
  int _lastUpload = -1;
  DateTime? _lastPollTime;
  bool _baselineResetPending = false;

  ClashRealtimeSnapshot? get snapshot => _snapshot;

  void resetBaseline({bool clearSnapshot = false}) {
    _lastDownload = -1;
    _lastUpload = -1;
    _lastPollTime = null;
    _baselineResetPending = true;
    if (clearSnapshot) {
      _snapshot = null;
      notifyListeners();
    } else if (_snapshot != null) {
      _snapshot = _snapshot!.copyWith(
        sequence: ++_sequence,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        downloadSpeed: 0,
        uploadSpeed: 0,
      );
      notifyListeners();
    }
  }

  Future<ClashRealtimeSnapshot> refresh({bool force = false}) async {
    if (!ClashService.instance.isConfigured) {
      throw Exception(tr('请先在设置页填写 Clash 地址'));
    }

    final current = _snapshot;
    final now = DateTime.now();
    if (!_baselineResetPending &&
        !force &&
        current != null &&
        now.difference(current.updatedAt) < _cacheWindow) {
      return current;
    }

    final existing = _inFlight;
    if (existing != null) return existing;

    final next = _load();
    _inFlight = next;
    try {
      return await next;
    } finally {
      if (identical(_inFlight, next)) _inFlight = null;
    }
  }

  Future<ClashRealtimeSnapshot> _load() async {
    final results = await Future.wait([
      ClashService.instance.getTrafficSnapshot(),
      ClashService.instance.getProviderTraffic(),
    ]);

    final rawSnapshot = results[0] as Map<String, dynamic>;
    final providers = results[1] as List<ProviderTraffic>;
    final connections =
        List<ConnectionEntry>.from(rawSnapshot['connections'] as List? ?? []);
    final downloadTotal = rawSnapshot['downloadTotal'] as int? ?? 0;
    final uploadTotal = rawSnapshot['uploadTotal'] as int? ?? 0;

    final now = DateTime.now();
    double downloadSpeed = 0;
    double uploadSpeed = 0;
    if (_lastDownload >= 0 && _lastPollTime != null) {
      final elapsedSeconds =
          now.difference(_lastPollTime!).inMilliseconds / 1000.0;
      if (elapsedSeconds > 0) {
        downloadSpeed = ((downloadTotal - _lastDownload) / elapsedSeconds)
            .clamp(0, double.infinity)
            .toDouble();
        uploadSpeed = ((uploadTotal - _lastUpload) / elapsedSeconds)
            .clamp(0, double.infinity)
            .toDouble();
      }
    }

    _lastDownload = downloadTotal;
    _lastUpload = uploadTotal;
    _lastPollTime = now;
    _baselineResetPending = false;

    final nextSnapshot = ClashRealtimeSnapshot(
      sequence: ++_sequence,
      updatedAt: now,
      downloadTotal: downloadTotal,
      uploadTotal: uploadTotal,
      activeConnections: rawSnapshot['count'] as int? ?? connections.length,
      downloadSpeed: downloadSpeed,
      uploadSpeed: uploadSpeed,
      connections: connections,
      providers: providers,
    );
    _snapshot = nextSnapshot;
    notifyListeners();
    return nextSnapshot;
  }

  void removeConnection(String id) {
    final current = _snapshot;
    if (current == null) return;
    final nextConnections =
        current.connections.where((connection) => connection.id != id).toList();
    if (nextConnections.length == current.connections.length) return;
    _snapshot = current.copyWith(
      sequence: ++_sequence,
      updatedAt: DateTime.now(),
      activeConnections: nextConnections.length,
      connections: nextConnections,
    );
    notifyListeners();
  }
}
