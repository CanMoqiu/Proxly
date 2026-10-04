/// Keeps version retries separate from the one-second traffic polling cadence.
/// Reset invalidates pending replies when the configured controller changes.
class CoreVersionLookup {
  CoreVersionLookup({
    required this.load,
    DateTime Function()? now,
    this.retryDelay = const Duration(seconds: 5),
  }) : _now = now ?? DateTime.now;

  final Future<String?> Function() load;
  final DateTime Function() _now;
  final Duration retryDelay;
  String value = '--';
  Future<void>? _inFlight;
  DateTime? _retryAt;
  int _generation = 0;
  bool _needsRefresh = true;

  void reset() {
    _generation++;
    value = '--';
    _inFlight = null;
    _retryAt = null;
    _needsRefresh = true;
  }

  Future<void> refresh({bool force = false}) {
    if (_inFlight != null) return _inFlight!;
    if (!force &&
        (!_needsRefresh || (_retryAt != null && _now().isBefore(_retryAt!)))) {
      return Future.value();
    }
    final generation = _generation;
    return _inFlight = _fetch(generation);
  }

  Future<void> _fetch(int generation) async {
    _needsRefresh = true;
    try {
      final version = (await Future.sync(load))?.trim();
      if (generation != _generation) return;
      if (version != null && version.isNotEmpty && version != '--') {
        value = version;
        _needsRefresh = false;
      }
    } catch (_) {
      // Connectivity may recover before /version does. The next traffic
      // snapshot can retry after the cooldown without blocking the page.
    } finally {
      if (generation == _generation) {
        _retryAt = _now().add(retryDelay);
        _inFlight = null;
      }
    }
  }
}
