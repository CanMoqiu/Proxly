import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:proxly/services/update_service.dart';
import 'package:proxly/services/web_panel_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final testHttpOverride = HttpOverrides.current;
  late Directory directory;
  late UpdateService updates;
  late ValueNotifier<bool> cancelled;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    HttpOverrides.global = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    directory = await Directory.systemTemp.createTemp('proxly-download-');
    updates =
        UpdateService.forTesting(temporaryDirectory: () async => directory);
    cancelled = ValueNotifier(false);
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'Proxly',
        packageName: 'top.canmoqiu.proxly',
        version: '26.8.2',
        buildNumber: '37',
        buildSignature: '');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (call) async => directory.path);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    HttpOverrides.global = testHttpOverride;
    debugDefaultTargetPlatformOverride = null;
    updates.availableUpdate.dispose();
    cancelled.dispose();
    await directory.delete(recursive: true);
  });

  Future<String> serve(void Function(HttpRequest) handle) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handle);
    addTearDown(() => server.close(force: true));
    return 'http://127.0.0.1:${server.port}/app.apk';
  }

  final apkBytes = Uint8List(1024 * 1024 + 1)
    ..setRange(0, 4, [0x50, 0x4b, 0x03, 0x04]);

  test('APK streams to disk, verifies its digest and reuses the cache',
      () async {
    var requests = 0;
    final url = await serve((request) {
      requests++;
      request.response
        ..headers.contentType = ContentType.binary
        ..contentLength = apkBytes.length
        ..add(apkBytes);
      unawaited(request.response.close());
    });
    final progress = <double>[];
    final digest = sha256.convert(apkBytes).toString();
    final file = await updates.downloadApk(
        url, 'v26.8.3', digest, progress.add, cancelled);
    expect(await file.readAsBytes(), orderedEquals(apkBytes));
    expect(progress.last, 1);
    expect(await updates.downloadApk(url, 'v26.8.3', digest, (_) {}, cancelled),
        isA<File>());
    expect(requests, 1);
  });

  for (final sendBody in [false, true]) {
    test('APK cancellation aborts stalled ${sendBody ? 'body' : 'headers'}',
        () async {
      final ready = Completer<void>();
      var requests = 0;
      final url = await serve((request) {
        requests++;
        if (sendBody) {
          request.response
            ..bufferOutput = false
            ..headers.contentType = ContentType.binary
            ..add(apkBytes.sublist(0, 1024));
          unawaited(request.response.flush().catchError((_) {}));
        } else {
          ready.complete();
        }
      });
      final operation = updates.downloadApk(url, 'v26.8.3', null, (_) {
        if (!ready.isCompleted) ready.complete();
      }, cancelled);
      final failure = expectLater(operation.timeout(const Duration(seconds: 3)),
          throwsA(allOf(isException, isNot(isA<TimeoutException>()))));
      await ready.future.timeout(const Duration(seconds: 2));
      cancelled.value = true;
      await failure;
      expect(requests, 1);
      expect(
          await File('${directory.path}/proxly_update.apk').exists(), isFalse);
      expect(
          (await SharedPreferences.getInstance()).getString('cached_apk_tag'),
          isNull);
    });
  }

  test('APK digest mismatch removes partial installer and keeps user files',
      () async {
    final keep =
        await File('${directory.path}/keep.yaml').writeAsString('keep');
    final url = await serve((request) {
      request.response.add(apkBytes);
      unawaited(request.response.close());
    });
    await expectLater(
        updates.downloadApk(url, 'v26.8.3', '0' * 64, (_) {}, cancelled),
        throwsException);
    expect(await File('${directory.path}/proxly_update.apk').exists(), isFalse);
    expect(await keep.readAsString(), 'keep');
  });

  test('already cancelled download does not return or delete a cached APK',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_apk_tag', 'v26.8.3');
    final apk = await File('${directory.path}/proxly_update.apk')
        .writeAsBytes(apkBytes);
    cancelled.value = true;
    await expectLater(
        updates.downloadApk('http://127.0.0.1:1/app.apk', 'v26.8.3', null,
            (_) => fail('Cancelled download reported progress'), cancelled),
        throwsException);
    expect(await apk.readAsBytes(), orderedEquals(apkBytes));
  });

  Future<void> installPanel(Stream<List<int>> stream, String digest,
      {int? contentLength}) {
    return http.runWithClient(
      () => WebPanelService.downloadAndInstall(
        WebPanelVersionInfo(
            tag: 'v3.30.0',
            downloadUrl:
                'https://github.com/Zephyruso/zashboard/releases/download/v3.30.0/dist.zip',
            sha256: digest),
        (_) {},
      ),
      () => MockClient.streaming((request, body) async =>
          http.StreamedResponse(stream, 200, contentLength: contentLength)),
    );
  }

  test('panel download pauses its producer while writing and installs intact',
      () async {
    final content = utf8.encode('<html>panel</html>');
    final zip = ZipEncoder().encode(Archive()
      ..addFile(ArchiveFile('index.html', content.length, content)))!;
    var pauses = 0;
    var offset = 0;
    late StreamController<List<int>> source;
    void emit() {
      // The producer resumes only after the previous byte reached the file.
      expect(File('${directory.path}/zashboard/download.zip').lengthSync(),
          offset);
      if (offset == zip.length) {
        unawaited(source.close());
      } else {
        source.add([zip[offset++]]);
      }
    }

    source = StreamController<List<int>>(
      onListen: emit,
      onPause: () => pauses++,
      onResume: emit,
    );
    await installPanel(source.stream, sha256.convert(zip).toString(),
        contentLength: zip.length);
    expect(pauses, greaterThan(1));
    expect(
        await File('${directory.path}/zashboard/v3.30.0/index.html')
            .readAsString(),
        '<html>panel</html>');
    expect(await File('${directory.path}/zashboard/download.zip').exists(),
        isFalse);
    expect(
        (await SharedPreferences.getInstance()).getString('webpanel_version'),
        'v3.30.0');
  });

  test('panel file-open failure preserves unrelated files at the cache path',
      () async {
    final occupied = await Directory('${directory.path}/zashboard/download.zip')
        .create(recursive: true);
    final keep = await File('${occupied.path}/keep.yaml').writeAsString('keep');
    await expectLater(installPanel(Stream.value([1, 2, 3]), '0' * 64),
        throwsA(isA<FileSystemException>()));
    expect(await keep.readAsString(), 'keep');
  });

  for (final failure in ['stream', 'size', 'digest']) {
    test('panel $failure failure cleans download and preserves installed data',
        () async {
      final old = await Directory('${directory.path}/installed').create();
      final index = await File('${old.path}/index.html').writeAsString('old');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('webpanel_path', old.path);
      await prefs.setString('webpanel_version', 'v3.29.2');
      Stream<List<int>> chunks() async* {
        yield [1, 2, 3];
        if (failure == 'stream') throw const HttpException('interrupted');
        if (failure == 'size') {
          final chunk = Uint8List(1024 * 1024);
          for (var i = 0; i < 50; i++) {
            yield chunk;
          }
        }
      }

      await expectLater(installPanel(chunks(), '0' * 64), throwsException);
      expect(await File('${directory.path}/zashboard/download.zip').exists(),
          isFalse);
      expect(await index.readAsString(), 'old');
      expect(prefs.getString('webpanel_path'), old.path);
      expect(prefs.getString('webpanel_version'), 'v3.29.2');
    });
  }

  test('startup removes only abandoned download and staging paths', () async {
    final base = await Directory('${directory.path}/zashboard').create();
    final stage = await Directory('${base.path}/v3.30.0.staging').create();
    await File('${stage.path}/partial.js').writeAsString('partial');
    final keep = await Directory('${base.path}/v3.29.1.backup').create();
    await File('${keep.path}/index.html').writeAsString('backup');
    final active = await Directory('${base.path}/v3.29.2.staging').create();
    await (await SharedPreferences.getInstance())
        .setString('webpanel_path', active.path);
    final yaml = await File('${base.path}/keep.yaml').writeAsString('keep');
    final zip =
        await File('${base.path}/download.zip').writeAsString('partial');
    await WebPanelService.cleanupTemporaryFiles();
    expect(await stage.exists(), isFalse);
    expect(await zip.exists(), isFalse);
    expect(await keep.exists(), isTrue);
    expect(await active.exists(), isTrue);
    expect(await yaml.readAsString(), 'keep');
  });

  test('background extraction rejects traversal before installing resources',
      () async {
    final data = utf8.encode('unsafe');
    final zip = ZipEncoder().encode(
        Archive()..addFile(ArchiveFile('../escape.html', data.length, data)))!;
    await expectLater(
        installPanel(Stream.value(zip), sha256.convert(zip).toString()),
        throwsA(isA<FormatException>()));
    expect(await File('${directory.path}/zashboard/escape.html').exists(),
        isFalse);
    expect((await SharedPreferences.getInstance()).getString('webpanel_path'),
        isNull);
  });
}
