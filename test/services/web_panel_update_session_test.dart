import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/web_panel_service.dart';
import 'package:proxly/services/web_panel_update_session.dart';

const release = WebPanelVersionInfo(
    tag: 'v3.22.0',
    downloadUrl: 'https://example.test/panel.zip',
    sha256: 'digest');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('iOS activates all panels and exits busy state without process restart',
      () async {
    final events = <String>[];
    final session = WebPanelUpdateSession(
      getActiveVersion: () async => 'v3.21.0',
      checkLatest: () async => release,
      save: () async => events.add('save'),
      downloadAndInstall: (_, progress) async {
        events.add('install');
        progress(1);
      },
      restartPanels: () async {
        events.add('activate');
        return const WebPanelReloadResult(total: 3, failed: 0);
      },
      restartApp: () async => events.add('exit'),
      usesProcessRestart: () => false,
    );
    addTearDown(session.dispose);
    await session.check();
    await session.install();
    expect(events, ['save', 'install', 'activate']);
    expect(session.phase, WebPanelUpdatePhase.updated);
    expect(session.busy, isFalse);
    expect(session.hasUpdate, isFalse);
    expect(session.installedVersion, release.tag);
  });

  test('activation retry does not redownload installed resources', () async {
    var installs = 0;
    var attempts = 0;
    final session = WebPanelUpdateSession(
      save: () async {},
      downloadAndInstall: (_, progress) async {
        installs++;
      },
      restartPanels: () async =>
          WebPanelReloadResult(total: 3, failed: ++attempts == 1 ? 1 : 0),
      usesProcessRestart: () => false,
    )..availableInfo = release;
    addTearDown(session.dispose);
    await expectLater(session.install(), throwsStateError);
    expect(session.busy, isFalse);
    expect(session.activationPending, isTrue);
    await session.install();
    expect(installs, 1);
    expect(attempts, 2);
    expect(session.activationPending, isFalse);
    expect(session.phase, WebPanelUpdatePhase.updated);
  });

  test('simultaneous requests install once and Android uses its restart path',
      () async {
    final saved = Completer<void>();
    var installs = 0;
    var restarts = 0;
    final session = WebPanelUpdateSession(
      save: () => saved.future,
      downloadAndInstall: (_, progress) async {
        installs++;
      },
      restartApp: () async {
        restarts++;
      },
      restartPanels: () async => throw StateError('Android must restart'),
      usesProcessRestart: () => true,
    )..availableInfo = release;
    addTearDown(session.dispose);
    final first = session.install();
    await session.install();
    saved.complete();
    await first;
    expect(installs, 1);
    expect(restarts, 1);
  });

  test(
      'server restart registry isolates failures and unregisters disposed pages',
      () async {
    final sync = WebPanelSync.instance;
    final a = Object(), b = Object(), closed = Object();
    var first = true;
    var reloads = 0;
    sync.registerWebView(a, () async {
      reloads++;
    }, restartServer: () async {});
    sync.registerWebView(b, () async {}, restartServer: () async {
      if (first) throw StateError('load failed');
    });
    sync.registerWebView(closed, () async {},
        restartServer: () async => throw StateError('disposed'));
    sync.unregisterWebView(closed);
    addTearDown(() {
      sync.unregisterWebView(a);
      sync.unregisterWebView(b);
    });
    final failed = await sync.restartAllWebViews();
    expect(failed.total, 2);
    expect(failed.failed, 1);
    expect(failed.results, {a: true, b: false});
    first = false;
    expect((await sync.restartAllWebViews()).succeeded, isTrue);
    expect(reloads, 0);
  });

  test('a stalled panel cannot leave batch activation busy forever', () async {
    final sync = WebPanelSync.instance;
    final owner = Object();
    final stalled = Completer<void>();
    sync.registerWebView(owner, () async {},
        restartServer: () => stalled.future);
    addTearDown(() => sync.unregisterWebView(owner));
    final result = await sync.restartAllWebViews(
        timeout: const Duration(milliseconds: 10));
    expect(result.results[owner], isFalse);
    expect(result.succeeded, isFalse);
    stalled.complete();
  });
}
