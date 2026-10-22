import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/controller_connection_state.dart';
import 'package:proxly/services/openclash_restart_coordinator.dart';

void main() {
  test('old responses cannot override a newer observation or controller', () {
    final state = ControllerConnectionState();
    addTearDown(state.dispose);
    final old = state.observe();
    state.reportOffline(state.observe());
    state.reportStatus(old, 200);
    expect(state.phase, ControllerConnectionPhase.offline);
    final previousController = state.observe();
    state.reset();
    state.reportStatus(previousController, 401);
    expect(state.phase, ControllerConnectionPhase.unknown);
    state.reportStatus(state.observe(), 200);
    expect(state.phase, ControllerConnectionPhase.online);
  });

  test('authentication errors differ from offline and unsupported endpoints',
      () {
    final state = ControllerConnectionState();
    addTearDown(state.dispose);
    state.reportStatus(state.observe(), 401);
    expect(state.phase, ControllerConnectionPhase.unauthorized);
    state.reportStatus(state.observe(), 404);
    expect(state.phase, ControllerConnectionPhase.unauthorized);
    state.reportStatus(state.observe(), 200);
    state.reportStatus(state.observe(), 500);
    expect(state.phase, ControllerConnectionPhase.online);
  });

  test('concurrent recovery probes share one request', () async {
    final state = ControllerConnectionState();
    addTearDown(state.dispose);
    final response = Completer<void>();
    var calls = 0;
    Future<void> probe() {
      calls++;
      return response.future;
    }

    final first = state.probe(probe);
    final second = state.probe(probe);
    expect(calls, 1);
    response.complete();
    await Future.wait([first, second]);
    expect(state.phase, ControllerConnectionPhase.online);
  });

  test('restart owns the shared state until health verification completes',
      () async {
    final command = Completer<void>();
    final restart = OpenClashRestartCoordinator(
        restartCommand: (_) => command.future,
        healthProbe: () async {},
        delay: (_) async {},
        terminalStateDuration: Duration.zero);
    final state = ControllerConnectionState(restartCoordinator: restart);
    addTearDown(state.dispose);
    addTearDown(restart.dispose);
    final old = state.observe();
    final operation = restart.restart();
    expect(state.phase, ControllerConnectionPhase.restarting);
    state.reportStatus(state.observe(), 200);
    state.reportOffline(old);
    expect(state.phase, ControllerConnectionPhase.restarting);
    var probes = 0;
    await state.probe(() async {
      probes++;
    });
    expect(probes, 0);
    command.complete();
    expect((await operation).success, isTrue);
    expect(state.phase, ControllerConnectionPhase.online);
    state.reportOffline(old);
    expect(state.phase, ControllerConnectionPhase.online);
  });
}
