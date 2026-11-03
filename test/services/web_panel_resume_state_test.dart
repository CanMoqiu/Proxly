import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/web_panel_resume_state.dart';

void main() {
  test('duplicate background events preserve the original suspension time', () {
    var now = DateTime(2026);
    final state = WebPanelResumeState(now: () => now);
    state.didChangeState(AppLifecycleState.hidden);
    now = now.add(const Duration(seconds: 25));
    state.didChangeState(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 10));
    state.didChangeState(AppLifecycleState.resumed);
    expect(state.foreground, isTrue);
    expect(state.consumeLongBackground(isIOS: true), isTrue);
    expect(state.consumeLongBackground(isIOS: true), isFalse);
  });

  test('short interruptions and Android background stays preserve the view',
      () {
    var now = DateTime(2026);
    final state = WebPanelResumeState(now: () => now);
    state.didChangeState(AppLifecycleState.inactive);
    now = now.add(const Duration(minutes: 1));
    expect(state.consumeLongBackground(isIOS: true), isFalse);
    state.didChangeState(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 3));
    expect(state.consumeLongBackground(isIOS: true), isFalse);
    state.didChangeState(AppLifecycleState.hidden);
    now = now.add(const Duration(minutes: 2));
    expect(state.consumeLongBackground(isIOS: false), isFalse);
  });
}
