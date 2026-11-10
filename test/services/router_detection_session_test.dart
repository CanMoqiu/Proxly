import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/connection_settings_store.dart';
import 'package:proxly/services/router_detection_service.dart';
import 'package:proxly/services/controller_connection_state.dart';
import 'package:proxly/services/router_detection_session.dart';
import 'package:proxly/services/router_tool.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Detector extends RouterDetectionService {
  _Detector(this.respond);
  final Future<RouterDetectionResult> Function(String host) respond;
  @override
  Future<RouterDetectionResult> detect(
          {required String host,
          required String token,
          required String sshPassword,
          required int sshPort}) =>
      respond(host);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secrets = <String, String>{};
  var writes = 0;
  setUp(() {
    writes = 0;
    secrets.clear();
    SharedPreferences.setMockInitialValues({
      'clash_host': 'router.local:9090',
      'router_tool': 'generic',
      'proxy_core': 'unknown'
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, (call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      if (call.method == 'read') return secrets[args['key']];
      if (call.method == 'write') {
        writes++;
        secrets[args['key']] = args['value'];
      }
      if (call.method == 'deleteAll') secrets.clear();
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(storage, null));

  test(
      'controller reads cannot mix credentials from a concurrent endpoint save',
      () async {
    secrets
        .addAll({'clash_token': 'old-token', 'ssh_password': 'old-password'});
    final readStarted = Completer<void>();
    final release = Completer<void>();
    var firstRead = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, (call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      if (call.method == 'read') {
        if (firstRead) {
          firstRead = false;
          readStarted.complete();
          await release.future;
        }
        return secrets[args['key']];
      }
      if (call.method == 'write') {
        writes++;
        secrets[args['key']] = args['value'];
      }
      return null;
    });
    final store = ConnectionSettingsStore.instance;
    final old = store.load();
    await readStarted.future;
    final save = store.saveController(
        host: 'new-router.local:9090',
        token: 'new-token',
        sshPassword: 'new-password');
    await Future<void>.delayed(Duration.zero);
    expect(writes, 0);
    release.complete();
    final snapshot = await old;
    expect(snapshot.host, 'router.local:9090');
    expect(snapshot.token, 'old-token');
    expect(snapshot.sshPassword, 'old-password');
    await save;
    expect((await store.load()).host, 'new-router.local:9090');
  });

  test(
      'each refresh identifies software, while unchanged results do not reset controller state',
      () async {
    var calls = 0;
    final session = RouterDetectionSession(detector: _Detector((host) async {
      calls++;
      return const RouterDetectionResult(
          tool: RouterTool.nikki, core: ProxyCore.mihomo, version: 'v1');
    }));
    addTearDown(session.dispose);
    final store = ConnectionSettingsStore.instance;
    final connection = ControllerConnectionState(settingsStore: store);
    addTearDown(connection.dispose);
    connection.reportStatus(connection.observe(), 200);
    final generation = connection.generation;
    await session.refresh();
    expect(connection.phase, ControllerConnectionPhase.online);
    expect(connection.generation, generation);
    expect(await store.loadRouterTool(), RouterTool.nikki);
    final revision = store.revision;
    await session.refresh();
    expect(calls, 2);
    expect(store.revision, revision);
    expect(await store.pendingRouterToolSelection(), isNull);
    expect(writes, 0);
  });
  test(
      'failed connections preserve identity and never authorize automatic selection',
      () async {
    final session = RouterDetectionSession(
        detector: _Detector((host) async => throw StateError('offline')));
    addTearDown(session.dispose);
    final store = ConnectionSettingsStore.instance;
    await session.refresh();
    expect(await store.pendingRouterToolSelection(), isNull);
    expect(session.canSelectFor('router.local:9090', store.revision), isFalse);
    final apiOnly = RouterDetectionSession(
        detector: _Detector((host) async => const RouterDetectionResult(
            tool: RouterTool.generic, core: ProxyCore.mihomo, version: 'v2')));
    addTearDown(apiOnly.dispose);
    await apiOnly.refresh();
    final request = await store.pendingRouterToolSelection();
    expect(request, isNotNull);
    expect(apiOnly.canSelectFor(request!.host, request.revision), isTrue);
    expect(
        await store.confirmRouterTool(RouterTool.nikki,
            expectedHost: request.host, expectedRevision: request.revision),
        isTrue);
    await session.refresh();
    expect(await store.loadRouterTool(), RouterTool.nikki);
    expect(await store.pendingRouterToolSelection(), isNull);
    await apiOnly.refresh();
    expect((await store.load()).core, ProxyCore.mihomo);
    expect(await store.loadRouterTool(), RouterTool.nikki);
    expect(writes, 0);
  });
  test('a failed probe revokes an earlier successful automatic selection',
      () async {
    var online = true;
    final session = RouterDetectionSession(detector: _Detector((host) async {
      if (!online) throw StateError('offline');
      return const RouterDetectionResult(
          tool: RouterTool.generic, core: ProxyCore.mihomo, version: 'v2');
    }));
    addTearDown(session.dispose);
    final store = ConnectionSettingsStore.instance;
    await session.refresh();
    expect(session.canSelectFor('router.local:9090', store.revision), isTrue);
    final revision = store.revision;
    online = false;
    await session.refresh();
    expect(session.canSelectFor('router.local:9090', store.revision), isFalse);
    expect(store.revision, revision);
    expect((await store.load()).core, ProxyCore.mihomo);
  });
  test(
      'manual software selection is bound to identity without a pending prompt',
      () async {
    final store = ConnectionSettingsStore.instance;
    final identity = await store.loadRouterIdentity();
    expect(identity.tool, RouterTool.generic);
    expect(await store.pendingRouterToolSelection(), isNull);
    expect(
        await store.selectRouterTool(RouterTool.nikki,
            expectedHost: identity.host, expectedRevision: identity.revision),
        isTrue);
    expect(await store.loadRouterTool(), RouterTool.nikki);
    expect(
        await store.selectRouterTool(RouterTool.openClash,
            expectedHost: identity.host, expectedRevision: identity.revision),
        isFalse);
    expect(await store.loadRouterTool(), RouterTool.nikki);
    expect(writes, 0);
  });

  test('stale detection is discarded and refreshed for a changed controller',
      () async {
    final old = Completer<RouterDetectionResult>();
    final started = Completer<void>();
    final hosts = <String>[];
    final session = RouterDetectionSession(detector: _Detector((host) async {
      hosts.add(host);
      if (hosts.length == 1) {
        started.complete();
        return old.future;
      }
      return const RouterDetectionResult(
          tool: RouterTool.openClash, core: ProxyCore.mihomo, version: 'v2');
    }));
    addTearDown(session.dispose);
    final running = session.refresh();
    await started.future;
    final store = ConnectionSettingsStore.instance;
    await store.saveController(
        host: 'new-router.local:9095',
        token: 'new',
        sshPassword: 'p',
        routerTool: RouterTool.generic,
        routerSelectionPending: true);
    old.complete(const RouterDetectionResult(
        tool: RouterTool.nikki, core: ProxyCore.mihomo, version: 'old'));
    await running;
    final settings = await store.load();
    expect(hosts, ['router.local:9090', 'new-router.local:9095']);
    expect(settings.host, 'new-router.local:9095');
    expect(settings.routerTool, RouterTool.openClash);
  });
  test('a choice from an old popup cannot change a newly saved controller',
      () async {
    final store = ConnectionSettingsStore.instance;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('router_tool_selection_pending', true);
    final request = (await store.pendingRouterToolSelection())!;
    await store.saveController(
        host: 'new-router.local:9090',
        token: '',
        sshPassword: '',
        routerTool: RouterTool.generic,
        routerSelectionPending: true);
    expect(
        await store.confirmRouterTool(RouterTool.nikki,
            expectedHost: request.host, expectedRevision: request.revision),
        isFalse);
    expect(await store.loadRouterTool(), RouterTool.generic);
    expect((await store.pendingRouterToolSelection())!.host,
        'new-router.local:9090');
  });
}
