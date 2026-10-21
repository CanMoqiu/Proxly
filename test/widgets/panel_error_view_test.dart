import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/connection_feedback.dart';
import 'package:proxly/services/clash_service.dart';
import 'package:proxly/services/web_panel_page_probe.dart';
import 'package:proxly/widgets/panel_error_view.dart';

void main() {
  test('network, authentication and initialization failures stay distinct', () {
    for (final status in [502, 503, 504]) {
      expect(
          WebPanelPageProbe.failureMessage({'state': 'api', 'status': status}),
          ConnectionFeedback.routerUnavailable);
    }
    expect(WebPanelPageProbe.failureMessage({'state': 'network'}),
        ConnectionFeedback.routerUnavailable);
    expect(WebPanelPageProbe.failureMessage({'state': 'api', 'status': 401}),
        ConnectionFeedback.authenticationFailed);
    expect(WebPanelPageProbe.failureMessage({'state': 'app_timeout'}),
        isNot(ConnectionFeedback.routerUnavailable));
    expect(
        ConnectionFeedback.forError(const ClashControllerException(
            ClashControllerFailureKind.unreachable)),
        ConnectionFeedback.routerUnavailable);
    expect(
        ConnectionFeedback.forError(const ClashControllerException(
            ClashControllerFailureKind.unauthorized)),
        ConnectionFeedback.authenticationFailed);
  });

  testWidgets('offline page retries quietly only while visible and foreground',
      (tester) async {
    var active = false;
    var reachable = false;
    var probes = 0;
    var retries = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PanelErrorView(
      message: ConnectionFeedback.routerUnavailable,
      isActive: () => active,
      probeConnection: () async {
        probes++;
        if (!reachable) throw StateError('offline');
      },
      onRetry: () async {
        retries++;
      },
    ))));
    await tester.pump(const Duration(seconds: 10));
    expect(probes, 0);
    active = true;
    await tester.pump(const Duration(seconds: 10));
    expect(probes, 1);
    expect(retries, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    reachable = true;
    await tester.pump(const Duration(seconds: 10));
    expect(probes, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(probes, 2);
    expect(retries, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('authentication errors never auto retry and taps cannot overlap',
      (tester) async {
    var probes = 0;
    var retries = 0;
    final gate = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PanelErrorView(
      message: ConnectionFeedback.authenticationFailed,
      probeConnection: () async {
        probes++;
      },
      onRetry: () async {
        retries++;
        await gate.future;
      },
    ))));
    await tester.pump(const Duration(seconds: 20));
    expect(probes, 0);
    final retry =
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!;
    retry();
    retry();
    expect(retries, 1);
    gate.complete();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a late successful probe cannot revive a closed page',
      (tester) async {
    var retries = 0;
    final gate = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PanelErrorView(
      message: ConnectionFeedback.routerUnavailable,
      probeConnection: () => gate.future,
      onRetry: () async {
        retries++;
      },
    ))));
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pump();
    expect(retries, 0);
    expect(tester.takeException(), isNull);
  });
}
