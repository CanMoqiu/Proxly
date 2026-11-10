import 'package:flutter/foundation.dart';
import 'connection_settings_store.dart';
import 'router_detection_service.dart';
import 'router_tool.dart';

/// One recognition pass per launch or background return; concurrent requests merge.
class RouterDetectionSession extends ChangeNotifier {
  RouterDetectionSession({RouterDetectionService? detector})
      : _detector = detector ?? RouterDetectionService();
  static final instance = RouterDetectionSession();
  final RouterDetectionService _detector;
  Future<void>? _inFlight;
  bool _repeat = false;
  ({String host, int revision})? _selectionIdentity;
  bool get isDetecting => _inFlight != null;

  bool canSelectFor(String host, int revision) =>
      _selectionIdentity == (host: host, revision: revision);

  Future<void> refresh() {
    final current = _inFlight;
    if (current != null) {
      _repeat = true;
      return current;
    }
    _selectionIdentity = null;
    // Defer the first read until the in-flight identity has been installed.
    final future = Future<void>.microtask(() async {
      do {
        _repeat = false;
        await _recognize();
      } while (_repeat);
    });
    _inFlight = future;
    notifyListeners();
    future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
        notifyListeners();
      }
    });
    return future;
  }

  Future<void> _recognize() async {
    _selectionIdentity = null;
    final store = ConnectionSettingsStore.instance;
    try {
      final settings = await store.load();
      if (settings.host.isEmpty) return;
      final revision = store.revision;
      final RouterDetectionResult result;
      try {
        result = await _detector.detect(
            host: settings.host,
            token: settings.token,
            sshPassword: settings.sshPassword,
            sshPort: settings.sshPort);
      } catch (_) {
        // Connection failure does not identify a generic controller or request a choice.
        if (store.revision != revision) _repeat = true;
        return;
      }
      final applied = await store.applyRouterDetection(
          expectedHost: settings.host,
          expectedRevision: revision,
          tool: result.tool,
          core: result.core);
      if (!applied) {
        _repeat = true;
      } else if (result.tool == RouterTool.generic) {
        _selectionIdentity = (host: settings.host, revision: store.revision);
      }
    } catch (_) {
      // Keychain and preference failures must not erase the saved configuration.
    }
  }
}
