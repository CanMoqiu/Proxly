import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/openclash_restart_coordinator.dart';

void main() {
  test('runs save, restart, health checks and verification in order', () async {
    final events = <String>[];
    final phases = <OpenClashRestartPhase>[];
    final coordinator = OpenClashRestartCoordinator(
      restartCommand: (_) async => events.add('restart'),
      healthProbe: () async => events.add('health'),
      delay: (_) async {},
      initialWait: Duration.zero,
      pollInterval: Duration.zero,
      requiredHealthyChecks: 2,
      terminalStateDuration: const Duration(days: 1),
    );
    addTearDown(coordinator.dispose);
    coordinator.addListener(() => phases.add(coordinator.phase));

    final result = await coordinator.restart(
      reason: OpenClashRestartReason.activeConfig,
      beforeRestart: () async => events.add('save'),
      verify: () async => events.add('verify'),
    );

    expect(result.success, isTrue);
    expect(result.changesPersisted, isTrue);
    expect(events, ['save', 'restart', 'health', 'health', 'verify']);
    expect(
      phases,
      [
        OpenClashRestartPhase.saving,
        OpenClashRestartPhase.restarting,
        OpenClashRestartPhase.waitingForOnline,
        OpenClashRestartPhase.verifying,
        OpenClashRestartPhase.succeeded,
      ],
    );
  });

  test('does not restart when persistence fails', () async {
    var restartCount = 0;
    final coordinator = OpenClashRestartCoordinator(
      restartCommand: (_) async => restartCount++,
      healthProbe: () async {},
      delay: (_) async {},
      initialWait: Duration.zero,
      terminalStateDuration: const Duration(days: 1),
    );
    addTearDown(coordinator.dispose);

    final result = await coordinator.restart(
      beforeRestart: () async => throw Exception('UCI unavailable'),
    );

    expect(result.success, isFalse);
    expect(result.changesPersisted, isFalse);
    expect(restartCount, 0);
    expect(coordinator.phase, OpenClashRestartPhase.failed);
    expect(coordinator.canRetry, isTrue);
  });

  test('retry skips a persistence step that already succeeded', () async {
    var saveCount = 0;
    var restartCount = 0;
    var healthShouldFail = true;
    final coordinator = OpenClashRestartCoordinator(
      restartCommand: (_) async => restartCount++,
      healthProbe: () async {
        if (healthShouldFail) throw Exception('offline');
      },
      delay: (_) async {},
      initialWait: Duration.zero,
      pollInterval: Duration.zero,
      healthAttempts: 1,
      requiredHealthyChecks: 1,
      terminalStateDuration: const Duration(days: 1),
    );
    addTearDown(coordinator.dispose);

    final first = await coordinator.restart(
      beforeRestart: () async => saveCount++,
    );
    healthShouldFail = false;
    final second = await coordinator.retryLast();

    expect(first.success, isFalse);
    expect(first.changesPersisted, isTrue);
    expect(second.success, isTrue);
    expect(saveCount, 1);
    expect(restartCount, 2);
  });

  test('deduplicates restart requests while one is running', () async {
    final restartGate = Completer<void>();
    var restartCount = 0;
    final coordinator = OpenClashRestartCoordinator(
      restartCommand: (_) async {
        restartCount++;
        await restartGate.future;
      },
      healthProbe: () async {},
      delay: (_) async {},
      initialWait: Duration.zero,
      requiredHealthyChecks: 1,
      terminalStateDuration: const Duration(days: 1),
    );
    addTearDown(coordinator.dispose);

    final first = coordinator.restart();
    final second = coordinator.restart();
    restartGate.complete();

    expect(await first, same(await second));
    expect(restartCount, 1);
  });
}
