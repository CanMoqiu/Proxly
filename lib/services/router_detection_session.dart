import 'package:flutter/foundation.dart';
import 'connection_settings_store.dart';
import 'controller_connection_state.dart';
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
      final generation = store.deviceGeneration;
      final settings = await store.load();
      if (generation != store.deviceGeneration) {
        _repeat = true;
        return;
      }
      if (settings.host.isEmpty) return;
      final revision = store.revision;
      final keepBackend = store.hasTemporaryBackendSelection(settings.deviceId);
      final connection = ControllerConnectionState.instance;
      final observation = connection.observe();
      final RouterDetectionResult result;
      try {
        result = await _detector.detect(
            host: settings.host,
            token: settings.token,
            sshPassword: keepBackend ? '' : settings.sshPassword,
            sshPort: settings.sshPort);
      } catch (error) {
        // Connection failure does not identify a generic controller or request a choice.
        if (generation == store.deviceGeneration) {
          if (error is StateError && error.message == 'unauthorized') {
            connection.reportStatus(observation, 401);
          } else {
            connection.reportOffline(observation);
          }
        }
        if (store.revision != revision) _repeat = true;
        return;
      }
      if (generation == store.deviceGeneration) {
        connection.reportStatus(observation, 200);
      }
      final applied = await store.applyRouterDetection(
          expectedHost: settings.host,
          expectedRevision: revision,
          tool: result.tool,
          core: result.core);
      if (!applied) {
        _repeat = true;
      } else if (!keepBackend && result.tool == RouterTool.generic) {
        _selectionIdentity = (host: settings.host, revision: store.revision);
      }
    } catch (_) {
      // Keychain and preference failures must not erase the saved configuration.
    }
  }
}
