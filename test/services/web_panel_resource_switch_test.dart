import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:proxly/services/web_panel_flag_font.dart';
import 'package:proxly/services/web_panel_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // This integration test talks only to its own loopback HTTP servers.
  final testHttpOverride = HttpOverrides.current;
  setUp(() => HttpOverrides.global = null);
  tearDown(() => HttpOverrides.global = testHttpOverride);

  test('bundled and downloaded panels serve the same app-owned flag font',
      () async {
    final root = await Directory.systemTemp.createTemp('proxly-font-test-');
    await File('${root.path}/index.html').writeAsString('downloaded panel');
    final bundled = AssetHttpServer('assets/web_panel');
    final downloaded = FileHttpServer(root.path);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await bundled.close();
      await downloaded.close();
      await root.delete(recursive: true);
    });
    await bundled.start();
    await downloaded.start();
    final asset = await rootBundle.load(WebPanelFlagFont.asset);
    final expected = asset.buffer.asUint8List(
      asset.offsetInBytes,
      asset.lengthInBytes,
    );
    for (final port in [bundled.port, downloaded.port]) {
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:$port${WebPanelFlagFont.path}'));
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(
          response.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
      expect(response.headers.contentType?.mimeType, 'font/woff2');
      final bytes = await response
          .fold<List<int>>([], (buffer, chunk) => buffer..addAll(chunk));
      expect(bytes, orderedEquals(expected));
    }
    for (final server in [bundled, downloaded]) {
      final port = server == bundled ? bundled.port : downloaded.port;
      for (final path in ['/', '/proxies']) {
        final response = await (await client
                .getUrl(Uri.parse('http://127.0.0.1:$port$path')))
            .close();
        expect(response.statusCode, 200);
        expect(
            response.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
        final content = await utf8.decoder.bind(response).join();
        expect(content,
            server == downloaded ? 'downloaded panel' : contains('<html'));
      }
    }
  });

  test('both localhost origins serve the bundled entry script and stylesheet',
      () async {
    final proxy = AssetHttpServer(WebPanelService.builtinAssetPath);
    final connections = AssetHttpServer(WebPanelService.builtinAssetPath);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await proxy.close();
      await connections.close();
    });
    await Future.wait([proxy.start(), connections.start()]);
    expect(proxy.port, isNot(connections.port));

    Future<HttpClientResponse> get(int port, String path) async =>
        (await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'))).close();

    final index = await utf8.decoder.bind(await get(proxy.port, '/')).join();
    final assets = RegExp(r'"\./(assets/[^"]+\.(?:js|css))"')
        .allMatches(index)
        .map((match) => match[1]!);
    expect(assets, isNotEmpty);
    expect(assets.any((path) => path.endsWith('.js')), isTrue);
    expect(assets.any((path) => path.endsWith('.css')), isTrue);
    for (final path in assets) {
      final bundled =
          await rootBundle.load('${WebPanelService.builtinAssetPath}/$path');
      for (final server in [proxy, connections]) {
        final response = await get(server.port, '/$path');
        expect(response.statusCode, HttpStatus.ok);
        expect(
            response.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
        expect(await response.fold<int>(0, (sum, bytes) => sum + bytes.length),
            bundled.lengthInBytes);
      }
    }
  });

  test(
      'all registered local servers switch to the installed resource directory',
      () async {
    final root = await Directory.systemTemp.createTemp('proxly-panel-switch-');
    final oldPath = await Directory('${root.path}/old').create();
    final newPath = await Directory('${root.path}/new').create();
    await File('${oldPath.path}/index.html').writeAsString('old panel');
    await File('${newPath.path}/index.html').writeAsString('new panel');
    SharedPreferences.setMockInitialValues({
      'webpanel_path': oldPath.path,
      'webpanel_version': 'v999.0.0',
      'webpanel_last_builtin_version': WebPanelService.builtinVersion,
    });
    final sync = WebPanelSync.instance;
    final servers = <Object, FileHttpServer>{};
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      for (final entry in servers.entries) {
        sync.unregisterWebView(entry.key);
        await entry.value.close();
      }
      await root.delete(recursive: true);
    });
    for (var i = 0; i < 3; i++) {
      final owner = Object();
      final server =
          FileHttpServer((await WebPanelService.getInstalledPath())!);
      await server.start();
      servers[owner] = server;
      sync.registerWebView(owner, () async {}, restartServer: () async {
        await servers[owner]!.close();
        final replacement =
            FileHttpServer((await WebPanelService.getInstalledPath())!);
        servers[owner] = replacement;
        await replacement.start();
      });
    }
    Future<String> content(FileHttpServer server) async {
      final request =
          await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/'));
      return utf8.decoder.bind(await request.close()).join();
    }

    expect(await Future.wait(servers.values.map(content)),
        List.filled(3, 'old panel'));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('webpanel_path', newPath.path);
    await prefs.setString('webpanel_version', 'v999.0.1');
    final result = await sync.restartAllWebViews();
    expect(result.total, 3);
    expect(result.succeeded, isTrue);
    expect(await Future.wait(servers.values.map(content)),
        List.filled(3, 'new panel'));
  });
}
