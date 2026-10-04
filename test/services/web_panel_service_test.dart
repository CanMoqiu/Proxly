import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/web_panel_service.dart';

void main() {
  test('bundled panel version matches the imported release', () {
    expect(WebPanelService.builtinVersion, 'v3.29.1');
  });

  testWidgets('new image and font formats are included in the asset bundle',
      (tester) async {
    final jpg = await rootBundle.load(
      'assets/web_panel/assets/metacubex-BlQkOUXT.jpg',
    );
    final ttf = await rootBundle.load(
      'assets/web_panel/assets/NotoColorEmoji-flagsonly-CWWDk9km.ttf',
    );
    final webp = await rootBundle.load(
      'assets/web_panel/assets/earth-day-O5DYyPrv.webp',
    );

    expect(jpg.lengthInBytes, greaterThan(0));
    expect(ttf.lengthInBytes, greaterThan(0));
    expect(webp.lengthInBytes, greaterThan(0));
  });

  test('bundled release retains the embedded panel integration hooks', () {
    final index = File('assets/web_panel/index.html').readAsStringSync();
    final mainScriptMatch = RegExp(
      r'src="\.\/assets\/(index-[^"]+\.js)"',
    ).firstMatch(index);
    expect(mainScriptMatch, isNotNull);

    final mainScript = File(
      'assets/web_panel/assets/${mainScriptMatch!.group(1)}',
    ).readAsStringSync();
    expect(mainScript, contains('home-page bg-base-200 flex size-full'));
    expect(mainScript, contains('overflow-y-scroll'));
    expect(mainScript, contains('base-container m-3 h-full overflow-auto'));
    expect(mainScript, contains('tab-bar absolute'));
    expect(mainScript, contains('/storage/zashboard'));
  });

  test('panel auth uses the current Zashboard clash endpoint schema', () {
    final script = WebPanelAuthScript.build(
      hostname: '127.0.0.1',
      port: '12345',
      secondaryPath: '/__proxly_clash/session',
    );

    expect(script, contains(r'\"type\":\"clash\"'));
    expect(script, contains(r'\"protocol\":\"http\"'));
    expect(script, contains(r'\"secondaryPath\":\"/__proxly_clash/session\"'));
    expect(script, contains(r'\"password\":\"\"'));
    expect(script, isNot(contains('secret')));
  });

  test('core settings sync captures confirmed fetch and XHR imports once', () {
    final script = WebPanelCoreSettingsSyncScript.build();
    final consume = WebPanelCoreSettingsSyncScript.consumePending();

    expect(script, contains('__proxlyCoreSettingsSyncV1'));
    expect(script, contains('/storage/zashboard'));
    expect(script, contains('originalFetch'));
    expect(script, contains('response.clone().json()'));
    expect(script, contains('XMLHttpRequest.prototype.open'));
    expect(script, contains('XMLHttpRequest.prototype.send'));
    expect(script, contains('Storage.prototype.setItem'));
    expect(script, contains("startsWith('config/')"));
    expect(script, contains('hasOwnProperty.call(candidate, key)'));
    expect(script, contains('String(candidate[key]) !== String(value)'));
    expect(script, contains("key === 'cache/auto-sync-settings-hash'"));
    expect(script, contains('sessionStorage.setItem'));
    expect(consume, contains('sessionStorage.removeItem'));
    expect(consume, contains('__proxly_core_settings_import_pending_v1'));
  });

  test('dockless layout script hides dock and trims bottom reserves', () {
    final script = WebPanelLayoutScript.buildDockless();

    expect(script, contains('__proxly_dockless'));
    expect(script, contains('__proxly_dockless_layout_style'));
    expect(script, contains('var(--app-height, 100dvh)'));
    expect(script, contains('--app-height'));
    expect(script, contains('.dock + .fixed.bottom-0'));
    expect(script, contains('resize'));
    expect(script, contains('visualViewport'));
    expect(script, isNot(contains('MutationObserver')));
    expect(script, isNot(contains('dispatchEvent')));
  });

  test('proxy tab layout assigns vertical scrolling to the proxy container',
      () {
    final script = WebPanelLayoutScript.buildDockless(proxyTab: true);

    expect(script, contains('__proxly_proxy_tab_scroll'));
    expect(script, contains('overflow-y-auto'));
    expect(script, contains(':has('));
    expect(script, contains('overflow-y-scroll'));
    expect(script, contains('overflow-y: hidden !important'));
    expect(script, contains('min-height: 0 !important'));
    expect(script, contains('touch-action: pan-y !important'));
    expect(script, contains('overscroll-behavior-y: none !important'));
    expect(script, contains('padding-bottom: 0 !important'));
    expect(script, isNot(contains('touchstart')));
    expect(script, isNot(contains('touchmove')));
    expect(script, isNot(contains('preventDefault')));
    expect(script, isNot(contains('scrollTop')));
    expect(script, isNot(contains('MutationObserver')));
    expect(script, isNot(contains('trimVirtualScrollerTail')));
    expect(script, isNot(contains("addEventListener('scroll'")));
    expect(script, isNot(contains('querySelectorAll')));
    expect(script, isNot(contains('getBoundingClientRect')));
    expect(script, isNot(contains('scrollHeight')));
  });

  test('connections tab layout targets card and table scroll containers', () {
    final script = WebPanelLayoutScript.buildDockless(connectionsTab: true);

    expect(script, contains('__proxly_connections_tab_scroll'));
    expect(script, contains('__proxly_dockless_connections_style'));
    expect(script, contains(r'[class~=\"size-full\"]'));
    expect(script, contains(r'[class~=\"overflow-y-auto\"]'));
    expect(script, contains('.base-container.m-3.h-full.overflow-auto'));
    expect(script, contains('height: auto !important'));
    expect(script, contains('flex: 1 1 auto !important'));
    expect(script, contains('margin-bottom: 0 !important'));
    expect(script, contains('touch-action: pan-y !important'));
    expect(script, isNot(contains('touchstart')));
    expect(script, isNot(contains('touchmove')));
    expect(script, isNot(contains('preventDefault')));
    expect(script, isNot(contains('scrollTop')));
  });

  test('proxy tab scroll mode is only wired to proxy page', () {
    final proxySource = File('lib/pages/proxy_page.dart').readAsStringSync();
    final connectionsSource =
        File('lib/pages/connections_page.dart').readAsStringSync();

    expect(proxySource, contains('buildDockless(proxyTab: true)'));
    expect(
      RegExp(r'buildDockless\(proxyTab: true\)').allMatches(proxySource).length,
      1,
    );
    expect(proxySource, isNot(contains('buildProxyTabTouchBoundaryGuard')));
    expect(
      connectionsSource,
      contains('buildDockless(connectionsTab: true)'),
    );
    expect(
      RegExp(r'buildDockless\(connectionsTab: true\)')
          .allMatches(connectionsSource)
          .length,
      1,
    );
    expect(connectionsSource, isNot(contains('proxyTab: true')));
  });

  test('all Zashboard WebViews install the core import bridge first', () {
    final proxySource = File('lib/pages/proxy_page.dart').readAsStringSync();
    final connectionsSource =
        File('lib/pages/connections_page.dart').readAsStringSync();

    for (final source in [proxySource, connectionsSource]) {
      expect(source, contains('WebPanelCoreSettingsSyncScript.build()'));
      expect(
          source, contains('WebPanelCoreSettingsSyncScript.consumePending()'));
      expect(source, contains('window.__proxlyCoreImportPending'));
      expect(source, contains('reloadAllWebViews()'));
    }
  });

  test('archive validator strips one safe common directory', () {
    final root = ArchiveFile('dist/', 0, Uint8List(0))..isFile = false;
    final archive = Archive()
      ..addFile(root)
      ..addFile(ArchiveFile.string('dist/index.html', 'ok'))
      ..addFile(ArchiveFile.string('dist/assets/app.js', 'ok'));

    final entries = WebPanelService.validateArchive(archive);
    expect(entries.map((entry) => entry.path), [
      'index.html',
      'assets/app.js',
    ]);
  });

  test('archive validator rejects traversal, links, and duplicate paths', () {
    final traversal = Archive()
      ..addFile(ArchiveFile.string('../escape.txt', 'bad'));
    expect(
      () => WebPanelService.validateArchive(traversal),
      throwsFormatException,
    );

    final link = ArchiveFile.string('link', 'target')..isSymbolicLink = true;
    expect(
      () => WebPanelService.validateArchive(Archive()..addFile(link)),
      throwsFormatException,
    );

    final rootLink = ArchiveFile('dist/', 0, Uint8List(0))
      ..isFile = false
      ..isSymbolicLink = true;
    final prefixedLink = Archive()
      ..addFile(rootLink)
      ..addFile(ArchiveFile.string('dist/index.html', 'ok'));
    expect(
      () => WebPanelService.validateArchive(prefixedLink),
      throwsFormatException,
    );

    final duplicate = Archive()
      ..addFile(ArchiveFile.string('Index.html', 'one'))
      ..addFile(ArchiveFile.string('index.html', 'two'));
    expect(
      () => WebPanelService.validateArchive(duplicate),
      throwsFormatException,
    );
  });

  test('archive validator rejects size and compression bombs', () {
    final singleFile = Archive()
      ..addFile(ArchiveFile(
        'large.bin',
        WebPanelService.maxArchiveFileBytes + 1,
        Uint8List(1),
      ));
    expect(
      () => WebPanelService.validateArchive(singleFile),
      throwsFormatException,
    );

    final ratioBomb = Archive()
      ..addFile(ArchiveFile(
        'ratio.bin',
        WebPanelService.maxArchiveCompressionRatio + 1,
        Uint8List(1),
      ));
    expect(
      () => WebPanelService.validateArchive(ratioBomb),
      throwsFormatException,
    );

    final totalBomb = Archive();
    for (var index = 0; index < 6; index++) {
      totalBomb.addFile(ArchiveFile(
        '$index.bin',
        19 * 1024 * 1024,
        Uint8List(200 * 1024),
      ));
    }
    expect(
      () => WebPanelService.validateArchive(totalBomb),
      throwsFormatException,
    );
  });

  test('archive validator rejects excessive entry count', () {
    final archive = Archive();
    for (var index = 0; index <= WebPanelService.maxArchiveEntries; index++) {
      archive.addFile(ArchiveFile('$index.txt', 0, const <int>[]));
    }
    expect(
      () => WebPanelService.validateArchive(archive),
      throwsFormatException,
    );
  });

  test('installer rejects a version tag that could escape its directory',
      () async {
    const info = WebPanelVersionInfo(
      tag: '../../outside',
      downloadUrl:
          'https://github.com/Zephyruso/zashboard/releases/download/v1/dist.zip',
      sha256:
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    );
    expect(
      () => WebPanelService.downloadAndInstall(info, (_) {}),
      throwsFormatException,
    );
  });

  test('web panel refresh registry isolates callback failures', () async {
    final firstOwner = Object();
    final secondOwner = Object();
    var firstCalls = 0;
    var secondCalls = 0;
    WebPanelSync.instance.registerWebView(firstOwner, () async {
      firstCalls++;
    });
    WebPanelSync.instance.registerWebView(secondOwner, () async {
      secondCalls++;
      throw StateError('reload failed');
    });
    addTearDown(() {
      WebPanelSync.instance.unregisterWebView(firstOwner);
      WebPanelSync.instance.unregisterWebView(secondOwner);
    });

    final result = await WebPanelSync.instance.reloadAllWebViews();
    expect(firstCalls, 1);
    expect(secondCalls, 1);
    expect(result.total, 2);
    expect(result.failed, 1);
  });
}
