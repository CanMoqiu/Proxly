import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/web_panel_page_probe.dart';

class _Controller implements InAppWebViewController {
  _Controller(this.response);
  final Future<CallAsyncJavaScriptResult?> response;
  @override
  Future<CallAsyncJavaScriptResult?> callAsyncJavaScript(
          {required String functionBody,
          Map<String, dynamic> arguments = const {},
          ContentWorld? contentWorld}) =>
      response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('healthy panel can resume without a new navigation', () async {
    final controller = _Controller(
        Future.value(CallAsyncJavaScriptResult(value: {'state': 'ready'})));
    expect(await WebPanelPageProbe.canResume(controller, '/bridge'), isTrue);
  });
  test('offline and invalid panel states require recovery', () async {
    for (final state in ['network', 'app_timeout', 'api']) {
      expect(
          await WebPanelPageProbe.canResume(
              _Controller(Future.value(
                  CallAsyncJavaScriptResult(value: {'state': state}))),
              '/bridge'),
          isFalse);
    }
  });
  testWidgets('stalled JavaScript falls back to recovery within three seconds',
      (tester) async {
    final pending = Completer<CallAsyncJavaScriptResult?>();
    final result =
        WebPanelPageProbe.canResume(_Controller(pending.future), '/bridge');
    await tester.pump(const Duration(seconds: 3));
    expect(await result, isFalse);
    pending.complete(CallAsyncJavaScriptResult(value: {'state': 'ready'}));
    await tester.pump();
  });
}
