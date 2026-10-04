import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/panel_load_monitor.dart';

void main() {
  test('native load-start keeps the server activation waiter', () async {
    final monitor = PanelLoadMonitor()..begin();
    addTearDown(monitor.dispose);
    final activation = monitor.waitUntilReady();
    monitor.navigationStarted();
    monitor.succeed();
    await activation;
    expect(monitor.ready, isTrue);
  });

  testWidgets('later navigations have their own load timeout', (tester) async {
    final monitor = PanelLoadMonitor(timeout: const Duration(seconds: 2));
    addTearDown(monitor.dispose);
    monitor.navigationStarted();
    monitor.succeed();
    monitor.navigationStarted();
    expect(monitor.ready, isFalse);
    final waiting = expectLater(monitor.waitUntilReady(), throwsStateError);
    await tester.pump(const Duration(seconds: 3));
    await waiting;
  });

  testWidgets('timed out WebView can recover on a new load', (tester) async {
    final monitor = PanelLoadMonitor(timeout: const Duration(seconds: 2));
    addTearDown(monitor.dispose);
    monitor.begin();
    final failed = expectLater(monitor.waitUntilReady(), throwsStateError);
    await tester.pump(const Duration(seconds: 3));
    await failed;
    expect(monitor.error, isNotNull);
    monitor.begin();
    monitor.succeed();
    await monitor.waitUntilReady();
    expect(monitor.ready, isTrue);
    expect(monitor.error, isNull);
  });

  test('disposing a loading page releases activation waiters', () async {
    final monitor = PanelLoadMonitor()..begin();
    final wait = expectLater(monitor.waitUntilReady(), throwsStateError);
    monitor.dispose();
    await wait;
  });
}
