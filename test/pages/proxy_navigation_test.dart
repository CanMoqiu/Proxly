import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/proxy_page.dart';
import 'package:proxly/services/connection_settings_store.dart';
import 'package:proxly/services/web_panel_service.dart';
import 'package:proxly/widgets/panel_error_view.dart';
import 'package:proxly/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Platform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
          PlatformInAppWebViewWidgetCreationParams params) =>
      _View(params);
}

class _View extends PlatformInAppWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox();
  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;
  @override
  void dispose() {}
}

class _NativeController extends PlatformInAppWebViewController {
  _NativeController()
      : super.implementation(
            const PlatformInAppWebViewControllerCreationParams(id: 1));
}

class _Controller implements InAppWebViewController {
  @override
  final platform = _NativeController();
  @override
  void addJavaScriptHandler(
      {required String handlerName,
      required JavaScriptHandlerCallback callback}) {}
  @override
  Future<dynamic> evaluateJavascript(
          {required String source, ContentWorld? contentWorld}) async =>
      null;
  @override
  Future<CallAsyncJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    Map<String, dynamic> arguments = const {},
    ContentWorld? contentWorld,
  }) async =>
      CallAsyncJavaScriptResult(value: {'state': 'ready'});
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('native history return synchronizes the proxy header only',
      (tester) async {
    final oldPlatform = InAppWebViewPlatform.instance;
    InAppWebViewPlatform.instance = _Platform();
    addTearDown(() {
      if (oldPlatform != null) InAppWebViewPlatform.instance = oldPlatform;
    });
    SharedPreferences.setMockInitialValues(
        {'app_language': 'en', 'clash_host': '127.0.0.1:9090'});
    await AppLocaleController.instance.load();
    const storage =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, null));
    await ConnectionSettingsStore.instance.load();
    WebPanelSync.instance.proxyTabActive = true;
    addTearDown(() => WebPanelSync.instance.proxyTabActive = false);
    await tester.pumpWidget(AppLocaleScope(
      controller: AppLocaleController.instance,
      child: MaterialApp(
          theme: AppTheme.light(), home: const ProxyPage(asTab: true)),
    ));
    for (var i = 0;
        i < 40 && find.byType(InAppWebView).evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    final view = tester.widget<InAppWebView>(find.byType(InAppWebView));
    final params = view.platform.params;
    final controller = _Controller();
    params.onWebViewCreated!(controller);
    final initial = params.initialUrlRequest!.url!;
    expect(params.initialSettings!.allowsBackForwardNavigationGestures, isTrue);
    expect(
        params.initialUserScripts!
            .any((script) => script.source.contains('__proxly_native_history')),
        isTrue);
    params.onUpdateVisitedHistory!(controller,
        WebUri(initial.replace(fragment: '/rules').toString()), false);
    await tester.pump();
    expect(find.widgetWithText(AppBar, 'Rule'), findsOneWidget);
    expect(find.byTooltip('Proxy'), findsOneWidget);
    params.onUpdateVisitedHistory!(controller,
        WebUri(initial.replace(fragment: '/proxies').toString()), false);
    await tester.pump();
    expect(find.widgetWithText(AppBar, 'Proxy'), findsOneWidget);
    expect(find.byType(ProxyPage), findsOneWidget);
    params.onUpdateVisitedHistory!(_Controller(),
        WebUri(initial.replace(fragment: '/rules').toString()), false);
    params.onUpdateVisitedHistory!(
        controller, WebUri('https://example.invalid/#/rules'), false);
    await tester.pump();
    expect(find.widgetWithText(AppBar, 'Proxy'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    params.onWebContentProcessDidTerminate!(controller);
    await tester.pump(const Duration(minutes: 1));
    expect(find.byType(InAppWebView), findsNothing);
    expect(find.byType(PanelErrorView), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i = 0;
        i < 40 && find.byType(InAppWebView).evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    final replacement = tester.widget<InAppWebView>(find.byType(InAppWebView));
    expect(replacement.key, isNot(view.key));
    final recoveredController = _Controller();
    replacement.platform.params.onWebViewCreated!(recoveredController);
    replacement.platform.params.onLoadStop!(recoveredController,
        replacement.platform.params.initialUrlRequest!.url);
    await tester.pump();
    expect(find.byKey(const ValueKey('proxy_panel_ready')), findsOneWidget);
    expect(find.byType(PanelErrorView), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
