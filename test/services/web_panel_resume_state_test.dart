import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/web_panel_resume_state.dart';

void main() {
  test('duplicate background events preserve the original suspension time', () {
    var now = DateTime(2026);
    final state = WebPanelResumeState(now: () => now);
    state.didChangeState(AppLifecycleState.hidden);
    now = now.add(const Duration(minutes: 4));
    state.didChangeState(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 1));
    state.didChangeState(AppLifecycleState.resumed);
    expect(state.foreground, isTrue);
    expect(state.consumeBackgroundDuration(), const Duration(minutes: 5));
    expect(state.consumeBackgroundDuration(), isNull);
  });

  testWidgets('both mobile platforms retire a view at five minutes',
      (tester) async {
    var now = DateTime(2026);
    final state = WebPanelResumeState(now: () => now);
    state.didChangeState(AppLifecycleState.inactive);
    now = now.add(const Duration(minutes: 5));
    expect(state.consumeLongBackground(), isFalse);
    state.didChangeState(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 4, seconds: 59));
    state.didChangeState(AppLifecycleState.resumed);
    expect(state.consumeLongBackground(), isFalse);
    state.didChangeState(AppLifecycleState.hidden);
    now = now.add(const Duration(minutes: 5));
    state.didChangeState(AppLifecycleState.resumed);
    expect(state.consumeLongBackground(), isTrue);
    expect(state.consumeLongBackground(), isFalse);
  },
      variant:
          TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));
}
