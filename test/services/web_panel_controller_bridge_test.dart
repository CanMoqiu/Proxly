import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/web_panel_service.dart';
import 'package:proxly/services/controller_connection_state.dart';

void main() {
  test(
      'panel observations update shared state and old bridges cannot update new controllers',
      () async {
    final state = ControllerConnectionState();
    addTearDown(state.dispose);
    var status = 401;
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      request.response.statusCode = status;
      await request.response.close();
    });
    addTearDown(() => upstream.close(force: true));
    final bridge = WebPanelControllerBridge(
        hostname: '127.0.0.1',
        port: upstream.port,
        token: '',
        connectionState: state);
    final server =
        AssetHttpServer('assets/web_panel', controllerBridge: bridge);
    await server.start();
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    Future<void> request() async {
      final request = await client.getUrl(Uri.parse(
          'http://127.0.0.1:${server.port}${bridge.secondaryPath}/version'));
      await (await request.close()).drain<void>();
    }

    await request();
    expect(state.phase, ControllerConnectionPhase.unauthorized);
    status = 200;
    await request();
    expect(state.phase, ControllerConnectionPhase.online);
    state.reset();
    await request();
    expect(state.phase, ControllerConnectionPhase.unknown);
  });

  test('upstream WebSocket closure marks the shared controller offline',
      () async {
    final state = ControllerConnectionState();
    final online = Completer<void>();
    state.addListener(() {
      if (state.phase == ControllerConnectionPhase.online &&
          !online.isCompleted) {
        online.complete();
      }
    });
    addTearDown(state.dispose);
    final accepted = Completer<WebSocket>();
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((_) {});
      accepted.complete(socket);
    });
    addTearDown(() => upstream.close(force: true));
    final bridge = WebPanelControllerBridge(
        hostname: '127.0.0.1',
        port: upstream.port,
        token: '',
        connectionState: state);
    final server =
        AssetHttpServer('assets/web_panel', controllerBridge: bridge);
    await server.start();
    addTearDown(server.close);
    final downstream = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}${bridge.secondaryPath}/traffic');
    final closed = Completer<void>();
    downstream.listen((_) {}, onDone: closed.complete);
    await online.future.timeout(const Duration(seconds: 3));
    expect(state.phase, ControllerConnectionPhase.online);
    await (await accepted.future).close(WebSocketStatus.goingAway);
    await closed.future.timeout(const Duration(seconds: 3));
    expect(state.phase, ControllerConnectionPhase.offline);
  });

  test('gzip upstream bytes are decoded exactly once by the browser client',
      () async {
    const payload = '{"version":"test-gzip"}';
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      request.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      request.response.add(gzip.encode(utf8.encode(payload)));
      await request.response.close();
    });
    addTearDown(() => upstream.close(force: true));
    final bridge = WebPanelControllerBridge(
        hostname: '127.0.0.1', port: upstream.port, token: '');
    final server =
        AssetHttpServer('assets/web_panel', controllerBridge: bridge);
    await server.start();
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(Uri.parse(
        'http://127.0.0.1:${server.port}${bridge.secondaryPath}/version'));
    final response = await request.close();
    expect(await utf8.decoder.bind(response).join(), payload);
  });
  test('controller bridge adds auth without exposing it to the panel',
      () async {
    String? authorization;
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      authorization = request.headers.value(HttpHeaders.authorizationHeader);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'path': request.uri.toString()}));
      await request.response.close();
    });
    addTearDown(() => upstream.close(force: true));

    final bridge = WebPanelControllerBridge(
      hostname: '127.0.0.1',
      port: upstream.port,
      token: 'controller-secret',
      session: 'test-session',
    );
    final server = AssetHttpServer(
      'assets/web_panel',
      controllerBridge: bridge,
    );
    await server.start();
    addTearDown(server.close);

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(Uri.parse(
      'http://127.0.0.1:${server.port}${bridge.secondaryPath}/version?x=1',
    ));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();

    expect(response.statusCode, HttpStatus.ok);
    expect(authorization, 'Bearer controller-secret');
    expect(body, contains('/version?x=1'));
  });

  test('controller bridge proxies authenticated websocket traffic', () async {
    String? authorization;
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      authorization = request.headers.value(HttpHeaders.authorizationHeader);
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((message) => socket.add('echo:$message'));
    });
    addTearDown(() => upstream.close(force: true));

    final bridge = WebPanelControllerBridge(
      hostname: '127.0.0.1',
      port: upstream.port,
      token: 'controller-secret',
      session: 'test-websocket',
    );
    final server = AssetHttpServer(
      'assets/web_panel',
      controllerBridge: bridge,
    );
    await server.start();
    addTearDown(server.close);

    final socket = await WebSocket.connect(
      'ws://127.0.0.1:${server.port}${bridge.secondaryPath}/traffic',
    );
    addTearDown(socket.close);
    socket.add('ping');

    expect(await socket.first, 'echo:ping');
    expect(authorization, 'Bearer controller-secret');
  });

  test('controller bridge never follows an upstream redirect', () async {
    var redirectedRequests = 0;
    final redirected = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    redirected.listen((request) async {
      redirectedRequests++;
      await request.response.close();
    });
    addTearDown(() => redirected.close(force: true));

    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(
        HttpHeaders.locationHeader,
        'http://127.0.0.1:${redirected.port}/outside',
      );
      await request.response.close();
    });
    addTearDown(() => upstream.close(force: true));

    final bridge = WebPanelControllerBridge(
      hostname: '127.0.0.1',
      port: upstream.port,
      token: 'controller-secret',
      session: 'redirect-test',
    );
    final server = AssetHttpServer(
      'assets/web_panel',
      controllerBridge: bridge,
    );
    await server.start();
    addTearDown(server.close);

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(Uri.parse(
      'http://127.0.0.1:${server.port}${bridge.secondaryPath}/version',
    ));
    request.followRedirects = false;
    final response = await request.close();
    await response.drain<void>();

    expect(response.statusCode, HttpStatus.found);
    expect(redirectedRequests, 0);
  });
  test('WebSocket redirects must not forward controller authentication',
      () async {
    String? receivedAuth;
    var requests = 0;
    final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    target.listen((request) async {
      requests++;
      receivedAuth = request.headers.value(HttpHeaders.authorizationHeader);
      request.response.statusCode = 400;
      await request.response.close();
    });
    addTearDown(() => target.close(force: true));
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      request.response.statusCode = 302;
      request.response.headers.set(HttpHeaders.locationHeader,
          'http://127.0.0.1:${target.port}/redirect-target');
      await request.response.close();
    });
    addTearDown(() => upstream.close(force: true));
    final bridge = WebPanelControllerBridge(
        hostname: '127.0.0.1',
        port: upstream.port,
        token: 'synthetic-audit-token');
    final server =
        AssetHttpServer('assets/web_panel', controllerBridge: bridge);
    await server.start();
    addTearDown(server.close);
    try {
      final socket = await WebSocket.connect(
              'ws://127.0.0.1:${server.port}${bridge.secondaryPath}/traffic')
          .timeout(const Duration(seconds: 5));
      await socket.close();
    } on WebSocketException {
      // A rejected upstream redirect is expected.
    }
    expect(receivedAuth, isNull,
        reason: 'A different server received the controller Bearer header');
    expect(requests, 0, reason: 'The bridge followed a WebSocket redirect');
  });
}
