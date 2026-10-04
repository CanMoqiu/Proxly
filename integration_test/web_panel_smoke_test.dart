import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:proxly/main.dart';
import 'package:proxly/pages/connections_page.dart';
import 'package:proxly/pages/proxy_page.dart';
import 'package:proxly/services/connection_settings_store.dart';
import 'package:proxly/services/web_panel_service.dart';
import 'package:proxly/services/web_panel_flag_font.dart';
import 'package:proxly/services/web_panel_page_probe.dart';
import 'package:proxly/widgets/panel_error_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bundled editor font has equal ASCII advances on iOS',
      (tester) async {
    final loader = FontLoader('ProxlyMono')
      ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'));
    await loader.load();
    double width(String text) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(fontFamily: 'ProxlyMono', fontSize: 13),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final result = painter.width;
      painter.dispose();
      return result;
    }

    expect(width('iiii'), closeTo(width('WWWW'), 0.01));
    expect(width('    '), closeTo(width('0123'), 0.01));
    expect(width('abcd'), closeTo(13 * 0.6 * 4, 0.1));
  });

  testWidgets('WKWebView loads localhost and executes JavaScript',
      (tester) async {
    final requests = <String>[];
    final errors = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request.uri.path);
      request.response.headers.contentType = ContentType.html;
      request.response.write(
          '<!doctype html><html><body><div id="probe">ready</div></body></html>');
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    InAppWebViewController? controller;
    InAppWebViewController? loadController;
    var loaded = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: InAppWebView(
      initialUrlRequest:
          URLRequest(url: WebUri('http://127.0.0.1:${server.port}/')),
      onWebViewCreated: (value) => controller = value,
      onLoadStop: (value, url) async {
        loadController = value;
        loaded = true;
      },
      onReceivedError: (_, request, error) =>
          errors.add('${error.type}: ${error.description}'),
    ))));
    for (var i = 0; i < 80 && !loaded && errors.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(loaded, isTrue, reason: 'requests=$requests; errors=$errors');
    expect(identical(controller!.platform, loadController!.platform), isTrue);
    expect(
        await controller!
            .evaluateJavascript(
                source: 'document.querySelector("#probe").textContent')
            .timeout(const Duration(seconds: 5)),
        'ready');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('native WKWebViews load and navigation survives a stalled page',
      (tester) async {
    final requests = <String>[];
    final sockets = <WebSocket>[];
    var controllerOnline = false;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request.uri.path);
      if (!controllerOnline) {
        request.response.statusCode = 503;
        await request.response.close();
        return;
      }
      if (request.headers.value(HttpHeaders.authorizationHeader) !=
          'Bearer test-only-token') {
        request.response.statusCode = 401;
        await request.response.close();
        return;
      }
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.add(jsonEncode(switch (request.uri.path) {
          '/traffic' => {'up': 0, 'down': 0},
          '/memory' => {'inuse': 0, 'oslimit': 0},
          '/connections' => {
              'connections': [],
              'uploadTotal': 0,
              'downloadTotal': 0
            },
          _ => {'type': 'info', 'payload': 'test'},
        }));
        return;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(switch (request.uri.path) {
        '/version' => {'meta': true, 'version': 'v1.19.0'},
        '/configs' => {'mode': 'rule', 'mixed-port': 7890},
        '/proxies' => {
            'proxies': {
              'DIRECT': {
                'name': 'DIRECT',
                'type': 'Direct',
                'history': [],
                'alive': true
              },
              'GLOBAL': {
                'name': 'GLOBAL',
                'type': 'Selector',
                'all': ['DIRECT'],
                'now': 'DIRECT',
                'history': []
              },
            }
          },
        '/providers/proxies' || '/providers/rules' => {'providers': {}},
        '/connections' => {
            'connections': [],
            'uploadTotal': 0,
            'downloadTotal': 0
          },
        '/rules' => {'rules': []},
        _ => {},
      }));
      await request.response.close();
    });
    addTearDown(() async {
      for (final socket in sockets) {
        unawaited(socket.close());
      }
      await server.close(force: true);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setString('app_language', 'en');
    await prefs.setBool('automatic_update_check_enabled', false);
    await ConnectionSettingsStore.instance.saveController(
        host: '127.0.0.1:${server.port}',
        token: 'test-only-token',
        sshPassword: '');
    await tester.pumpWidget(const ProxlyApp());
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('v1.19.0'), findsNothing);
    expect(requests, contains('/version'));
    controllerOnline = true;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.text('v1.19.0').evaluate().isNotEmpty) break;
    }
    expect(find.text('v1.19.0'), findsOneWidget,
        reason: 'Version must recover after an offline cold start');

    // These checks exercise the native WebView, Keychain, ATS and localhost
    // bridge together. Unit tests cannot observe their integration failures.
    tester
        .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
        .onTap!(1);
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find
          .byKey(const ValueKey('proxy_panel_ready'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(find.byKey(const ValueKey('proxy_panel_ready')), findsOneWidget,
        reason:
            'requests=$requests; errors=${tester.widgetList<PanelErrorView>(find.byType(PanelErrorView, skipOffstage: false)).map((error) => error.message).toList()}');
    expect(requests, contains('/proxies'));
    // Zashboard 3.29 fetches rules lazily; opening proxies need not load them.
    expect(find.byType(PanelErrorView), findsNothing);
    expect(find.byType(ProxyPage), findsOneWidget);

    tester
        .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
        .onTap!(2);
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find
          .byKey(const ValueKey('connections_panel_ready'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(
        find.byKey(const ValueKey('connections_panel_ready')), findsOneWidget,
        reason:
            'requests=$requests; errors=${tester.widgetList<PanelErrorView>(find.byType(PanelErrorView, skipOffstage: false)).map((error) => error.message).toList()}');
    expect(requests, contains('/connections'));

    WebPanelReloadResult? activation;
    unawaited(WebPanelSync.instance.restartAllWebViews().then((result) {
      activation = result;
    }));
    for (var i = 0; i < 160 && activation == null; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(activation?.total, 2);
    expect(activation?.succeeded, isTrue,
        reason:
            'errors=${tester.widgetList<PanelErrorView>(find.byType(PanelErrorView, skipOffstage: false)).map((error) => error.message).toList()}');
    tester
        .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
        .onTap!(1);
    await tester.pump();

    // A hidden WebView may never finish evaluating JS on iOS. Reproduce that
    // condition without freezing the native engine and verify tab navigation.
    WebPanelSync.instance
        .register(save: () => Completer<void>().future, reload: () async {});
    tester
        .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
        .onTap!(2);
    await tester.pump();
    tester
        .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
        .onTap!(3);
    await tester.pump();
    expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .currentIndex,
        3);
    tester
        .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
        .onTap!(2);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(ConnectionsPage), findsOneWidget);
    expect(find.byType(PanelErrorView), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));

    await verifyBundledPanelLayoutAndFlags(tester, server.port);
  });
}

Future<void> verifyBundledPanelLayoutAndFlags(
    WidgetTester tester, int controllerPort) async {
  final bridge = WebPanelControllerBridge(
      hostname: '127.0.0.1', port: controllerPort, token: 'test-only-token');
  final panel = AssetHttpServer('assets/web_panel', controllerBridge: bridge);
  await panel.start();
  addTearDown(panel.close);
  InAppWebViewController? web;
  final scripts = [
    WebPanelPageProbe.disableServiceWorker,
    WebPanelAuthScript.build(
      hostname: '127.0.0.1',
      port: '${panel.port}',
      secondaryPath: bridge.secondaryPath,
    ),
    // An Android-exported preference must not revert to system emoji on iOS.
    "localStorage.setItem('config/emoji', 'noto-color-emoji');",
    WebPanelFlagFont.buildScript(),
    WebPanelLayoutScript.buildDockless(proxyTab: true),
  ];
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: InAppWebView(
    initialUrlRequest:
        URLRequest(url: WebUri('http://127.0.0.1:${panel.port}/#/proxies')),
    initialUserScripts: UnmodifiableListView(scripts
        .map((script) => UserScript(
            source: script,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START))
        .toList()),
    onWebViewCreated: (value) => web = value,
  ))));
  var ready = false;
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    ready = await web?.evaluateJavascript(
            source: "!!document.querySelector('.home-page nav.tab-bar')") ==
        true;
    if (ready) break;
  }
  expect(ready, isTrue);
  final result = await web!.callAsyncJavaScript(functionBody: r'''
    const fonts = await document.fonts.load('48px ProxlyFlags', '🇹🇼');
    const canvas = document.createElement('canvas');
    canvas.width = 96; canvas.height = 80;
    const ctx = canvas.getContext('2d');
    ctx.font = '48px ProxlyFlags';
    ctx.fillText('🇹🇼', 4, 58);
    const pixels = ctx.getImageData(0, 0, 96, 80).data;
    let red = 0, blue = 0;
    for (let i = 0; i < pixels.length; i += 4) {
      if (pixels[i + 3] < 128) continue;
      if (pixels[i] > 150 && pixels[i] > 2 * pixels[i + 2]) red++;
      if (pixels[i + 2] > 80 && pixels[i + 2] > 2 * pixels[i]) blue++;
    }
    const bar = document.querySelector('.home-page nav.tab-bar');
    const scroll = document.querySelector('.home-page .overflow-y-scroll');
    return {
      fonts: fonts.length, red, blue,
      family: getComputedStyle(document.querySelector('#app-content')).fontFamily,
      hidden: getComputedStyle(bar).visibility === 'hidden',
      bottomGap: Math.abs(innerHeight - bar.getBoundingClientRect().top),
      padding: parseFloat(getComputedStyle(scroll).paddingBottom)
    };
  ''');
  expect(result?.error, isNull);
  final values = result!.value as Map;
  expect(values['fonts'], 1);
  expect(values['family'], startsWith('ProxlyFlags'));
  expect(values['red'], greaterThan(20));
  expect(values['blue'], greaterThan(20));
  expect(values['hidden'], isTrue);
  expect(values['bottomGap'], lessThan(2));
  expect(values['padding'], 0);

  // The standalone console retains Zashboard's own navigation.
  expect(await web!.evaluateJavascript(source: r'''
    document.documentElement.classList.remove('__proxly_dockless');
    getComputedStyle(document.querySelector('.home-page nav.tab-bar')).visibility;
  '''), 'visible');
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
