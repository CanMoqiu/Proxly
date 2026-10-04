import 'dart:async';

import 'package:flutter/foundation.dart';

import 'clash_config_file_service.dart';
import 'clash_data_hub.dart';
import 'clash_service.dart';

enum OpenClashRestartPhase {
  idle,
  saving,
  restarting,
  waitingForOnline,
  verifying,
  succeeded,
  failed,
}

enum OpenClashRestartReason {
  manual,
  activeConfig,
  yamlEditor,
  quickSetting,
}

class OpenClashRestartResult {
  final bool success;
  final bool changesPersisted;
  final Object? error;

  const OpenClashRestartResult({
    required this.success,
    required this.changesPersisted,
    this.error,
  });
}

typedef OpenClashRestartCommand = Future<void> Function(String? password);
typedef OpenClashHealthProbe = Future<void> Function();
typedef OpenClashDelay = Future<void> Function(Duration duration);

class OpenClashRestartCoordinator extends ChangeNotifier {
  OpenClashRestartCoordinator({
    OpenClashRestartCommand? restartCommand,
    OpenClashHealthProbe? healthProbe,
    OpenClashDelay? delay,
    this.initialWait = const Duration(seconds: 3),
    this.pollInterval = const Duration(seconds: 2),
    this.healthAttempts = 45,
    this.requiredHealthyChecks = 2,
    this.verificationAttempts = 5,
    this.terminalStateDuration = const Duration(seconds: 6),
  })  : _restartCommand = restartCommand ??
            ((password) =>
                ClashConfigFileService.restartOpenClash(password: password)),
        _healthProbe = healthProbe ?? _defaultHealthProbe,
        _delay = delay ?? ((duration) => Future<void>.delayed(duration));

  static final instance = OpenClashRestartCoordinator();

  final OpenClashRestartCommand _restartCommand;
  final OpenClashHealthProbe _healthProbe;
  final OpenClashDelay _delay;
  final Duration initialWait;
  final Duration pollInterval;
  final int healthAttempts;
  final int requiredHealthyChecks;
  final int verificationAttempts;
  final Duration terminalStateDuration;

  OpenClashRestartPhase _phase = OpenClashRestartPhase.idle;
  OpenClashRestartReason _reason = OpenClashRestartReason.manual;
  Object? _error;
  bool _changesPersisted = false;
  Future<OpenClashRestartResult>? _inFlight;
  _RestartRequest? _retryRequest;
  Timer? _terminalStateTimer;

  OpenClashRestartPhase get phase => _phase;
  OpenClashRestartReason get reason => _reason;
  Object? get error => _error;
  bool get changesPersisted => _changesPersisted;
  bool get canRetry => _retryRequest != null && !isBusy;

  bool get isBusy => switch (_phase) {
        OpenClashRestartPhase.saving ||
        OpenClashRestartPhase.restarting ||
        OpenClashRestartPhase.waitingForOnline ||
        OpenClashRestartPhase.verifying =>
          true,
        _ => false,
      };

  Future<OpenClashRestartResult> restart({
    String? password,
    Future<void> Function()? beforeRestart,
    Future<void> Function()? verify,
    OpenClashRestartReason reason = OpenClashRestartReason.manual,
  }) {
    final current = _inFlight;
    if (current != null) return current;
    final request = _RestartRequest(
      password: password,
      beforeRestart: beforeRestart,
      verify: verify,
      reason: reason,
    );
    return _start(request);
  }

  Future<OpenClashRestartResult> retryLast({String? password}) {
    final current = _inFlight;
    if (current != null) return current;
    final request = _retryRequest;
    if (request == null) {
      return Future.value(
        OpenClashRestartResult(
          success: false,
          changesPersisted: false,
          error: StateError('No OpenClash restart is available to retry'),
        ),
      );
    }
    return _start(request.withPassword(password));
  }

  Future<OpenClashRestartResult> _start(_RestartRequest request) {
    _error = null;
    _changesPersisted = request.changesAlreadyPersisted;
    _reason = request.reason;
    final future = _run(request);
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    return future;
  }

  Future<OpenClashRestartResult> _run(_RestartRequest request) async {
    var changesPersisted = request.changesAlreadyPersisted;
    try {
      final beforeRestart = request.beforeRestart;
      if (beforeRestart != null) {
        _setPhase(OpenClashRestartPhase.saving);
        await beforeRestart();
        changesPersisted = true;
        _changesPersisted = true;
      }

      _setPhase(OpenClashRestartPhase.restarting);
      await _restartCommand(request.password);

      _setPhase(OpenClashRestartPhase.waitingForOnline);
      await _delay(initialWait);
      await _waitUntilHealthy();

      final verify = request.verify;
      if (verify != null) {
        _setPhase(OpenClashRestartPhase.verifying);
        await _verifyWithRetry(verify);
      }

      ClashDataHub.instance.resetBaseline(clearSnapshot: true);
      _retryRequest = null;
      _setPhase(OpenClashRestartPhase.succeeded);
      return OpenClashRestartResult(
        success: true,
        changesPersisted: changesPersisted,
      );
    } catch (error) {
      _error = error;
      _changesPersisted = changesPersisted;
      _retryRequest =
          (changesPersisted ? request.withoutPersistenceStep() : request)
              .withoutPassword();
      _setPhase(OpenClashRestartPhase.failed);
      return OpenClashRestartResult(
        success: false,
        changesPersisted: changesPersisted,
        error: error,
      );
    }
  }

  Future<void> _waitUntilHealthy() async {
    var consecutiveHealthyChecks = 0;
    Object? lastError;
    for (var attempt = 0; attempt < healthAttempts; attempt++) {
      try {
        await _healthProbe();
        consecutiveHealthyChecks++;
        if (consecutiveHealthyChecks >= requiredHealthyChecks) return;
      } catch (error) {
        lastError = error;
        consecutiveHealthyChecks = 0;
      }
      if (attempt < healthAttempts - 1) await _delay(pollInterval);
    }
    throw TimeoutException(
      lastError == null
          ? 'Waiting for Clash to come back online timed out'
          : 'Waiting for Clash to come back online timed out: $lastError',
    );
  }

  Future<void> _verifyWithRetry(Future<void> Function() verify) async {
    Object? lastError;
    for (var attempt = 0; attempt < verificationAttempts; attempt++) {
      try {
        await verify();
        return;
      } catch (error) {
        lastError = error;
      }
      if (attempt < verificationAttempts - 1) await _delay(pollInterval);
    }
    throw StateError('OpenClash settings verification failed: $lastError');
  }

  void _setPhase(OpenClashRestartPhase value) {
    _terminalStateTimer?.cancel();
    _phase = value;
    notifyListeners();
    if ((value == OpenClashRestartPhase.succeeded ||
            value == OpenClashRestartPhase.failed) &&
        terminalStateDuration > Duration.zero) {
      _terminalStateTimer = Timer(terminalStateDuration, () {
        if (_phase == value) {
          _phase = OpenClashRestartPhase.idle;
          notifyListeners();
        }
      });
    }
  }

  @override
  void dispose() {
    _terminalStateTimer?.cancel();
    super.dispose();
  }

  static Future<void> _defaultHealthProbe() async {
    await ClashService.instance.loadConfig();
    await ClashService.instance.getVersionInfo();
  }
}

class _RestartRequest {
  final String? password;
  final Future<void> Function()? beforeRestart;
  final Future<void> Function()? verify;
  final OpenClashRestartReason reason;
  final bool changesAlreadyPersisted;

  const _RestartRequest({
    required this.password,
    required this.beforeRestart,
    required this.verify,
    required this.reason,
    this.changesAlreadyPersisted = false,
  });

  _RestartRequest withoutPersistenceStep() {
    return _RestartRequest(
      password: password,
      beforeRestart: null,
      verify: verify,
      reason: reason,
      changesAlreadyPersisted: true,
    );
  }

  _RestartRequest withPassword(String? value) {
    return _RestartRequest(
      password: value ?? password,
      beforeRestart: beforeRestart,
      verify: verify,
      reason: reason,
      changesAlreadyPersisted: changesAlreadyPersisted,
    );
  }

  _RestartRequest withoutPassword() {
    return _RestartRequest(
      password: null,
      beforeRestart: beforeRestart,
      verify: verify,
      reason: reason,
      changesAlreadyPersisted: changesAlreadyPersisted,
    );
  }
}
