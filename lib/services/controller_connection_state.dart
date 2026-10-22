import 'package:flutter/foundation.dart';

import 'connection_feedback.dart';
import 'connection_settings_store.dart';
import 'openclash_restart_coordinator.dart';

enum ControllerConnectionPhase {
  unknown,
  online,
  offline,
  unauthorized,
  restarting
}

/// Shares observations from existing native and panel requests, without polling.
class ControllerConnectionState extends ChangeNotifier {
  ControllerConnectionState({
    OpenClashRestartCoordinator? restartCoordinator,
    ConnectionSettingsStore? settingsStore,
  })  : _restart = restartCoordinator,
        _settings = settingsStore {
    _restart?.addListener(_restartChanged);
    _settings?.addListener(_settingsChanged);
    if (_restart != null) _restartChanged();
  }

  static final instance = ControllerConnectionState(
    restartCoordinator: OpenClashRestartCoordinator.instance,
    settingsStore: ConnectionSettingsStore.instance,
  );

  final OpenClashRestartCoordinator? _restart;
  final ConnectionSettingsStore? _settings;
  ControllerConnectionPhase phase = ControllerConnectionPhase.unknown;
  String? message;
  int _generation = 0;
  int _sequence = 0;
  int _lastApplied = 0;
  Future<void>? _probe;

  int get generation => _generation;
  (int, int) observe() => (_generation, ++_sequence);

  void report((int, int) observation, ControllerConnectionPhase next,
      {String? error}) {
    if (observation.$1 != _generation ||
        observation.$2 < _lastApplied ||
        phase == ControllerConnectionPhase.restarting) {
      return;
    }
    _lastApplied = observation.$2;
    _set(next, error);
  }

  void reportStatus((int, int) observation, int status) {
    if (status >= 200 && status < 300) {
      report(observation, ControllerConnectionPhase.online);
    } else if (status == 401 || status == 403) {
      report(observation, ControllerConnectionPhase.unauthorized,
          error: ConnectionFeedback.authenticationFailed);
    }
    // Unsupported endpoints and rejected mutations do not prove disconnection.
  }

  void reportOffline((int, int) observation) =>
      report(observation, ControllerConnectionPhase.offline,
          error: ConnectionFeedback.routerUnavailable);

  Future<void> probe(Future<void> Function() load) {
    if (phase == ControllerConnectionPhase.restarting) return Future.value();
    return _probe ??= _runProbe(load).whenComplete(() => _probe = null);
  }

  Future<void> _runProbe(Future<void> Function() load) async {
    final observation = observe();
    await load();
    report(observation, ControllerConnectionPhase.online);
  }

  void reset() {
    _generation++;
    _set(ControllerConnectionPhase.unknown, null);
  }

  void _settingsChanged() {
    if (_settings!.lastChange != ConnectionSettingsChange.sshPassword) reset();
  }

  void _restartChanged() {
    final restart = _restart!;
    if (restart.isBusy) {
      if (phase != ControllerConnectionPhase.restarting) {
        _generation++;
        _set(ControllerConnectionPhase.restarting, '正在重启 OpenClash...');
      }
    } else if (phase == ControllerConnectionPhase.restarting) {
      _generation++;
      _set(
          restart.phase == OpenClashRestartPhase.succeeded
              ? ControllerConnectionPhase.online
              : ControllerConnectionPhase.unknown,
          restart.phase == OpenClashRestartPhase.failed ? '重启失败' : null);
    }
  }

  void _set(ControllerConnectionPhase next, String? error) {
    if (phase == next && message == error) return;
    phase = next;
    message = error;
    notifyListeners();
  }

  @override
  void dispose() {
    _restart?.removeListener(_restartChanged);
    _settings?.removeListener(_settingsChanged);
    super.dispose();
  }
}
