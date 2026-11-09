import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/connection_panel_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Controller implements InAppWebViewController {
  WebUri? url = WebUri('http://127.0.0.1:12345/#/settings');
  late JavaScriptHandlerCallback callback;
  @override
  void addJavaScriptHandler(
      {required String handlerName,
      required JavaScriptHandlerCallback callback}) {
    this.callback = callback;
  }

  @override
  Future<WebUri?> getUrl() async => url;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('phone and tablet share phone defaults without overriding saved content',
      () async {
    final store = ConnectionPanelPreferences();
    final phone = await store.load(tablet: false);
    final tablet = await store.load(tablet: true);
    expect(tablet, phone);
    expect(jsonDecode(phone['config/connection-card-lines']!), hasLength(4));
    expect(tablet['config/show-full-proxy-chain'], 'true');
    expect(tablet.containsKey('config/connection-table-columns'), isFalse);
    expect(tablet.containsKey('config/connection-table-size'), isFalse);
  });

  test(
      'content persists across store recreation without mixing device profiles',
      () async {
    final store = ConnectionPanelPreferences();
    await store.save({'config/connection-card-lines': '[["host","rule"]]'},
        tablet: false);
    await store.save({'config/connection-card-lines': '[["type","close"]]'},
        tablet: true);
    final fresh = ConnectionPanelPreferences();
    expect((await fresh.load(tablet: false))['config/connection-card-lines'],
        '[["host","rule"]]');
    expect((await fresh.load(tablet: true))['config/connection-card-lines'],
        '[["type","close"]]');
  });

  test('queued content patches merge and unrelated settings are never saved',
      () async {
    final store = ConnectionPanelPreferences();
    await Future.wait([
      store.save({'config/connection-card-lines': '[["host"]]'}, tablet: false),
      store.save({'config/show-full-proxy-chain': 'false'}, tablet: false),
      store.save({
        'clash_token': 'secret',
        'config/connection-display-style': 'table',
        'config/connection-sort-type': 'host'
      }, tablet: false),
    ]);
    final prefs = await SharedPreferences.getInstance();
    final saved =
        jsonDecode(prefs.getString(ConnectionPanelPreferences.phoneKey)!);
    expect(saved, {
      'config/connection-card-lines': '[["host"]]',
      'config/show-full-proxy-chain': 'false'
    });
    expect(prefs.getString(ConnectionPanelPreferences.tabletKey), isNull);
  });

  test('invalid content cannot poison a valid stored layout', () async {
    final store = ConnectionPanelPreferences();
    await store
        .save({'config/connection-card-lines': '[["host"]]'}, tablet: true);
    await store.save({
      'config/connection-card-lines': '[["password"]]',
      'config/connection-table-size': 'huge',
      'config/show-full-proxy-chain': 'yes',
      'config/connection-table-columns': 'not JSON'
    }, tablet: true);
    expect((await store.load(tablet: true))['config/connection-card-lines'],
        '[["host"]]');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(ConnectionPanelPreferences.tabletKey, '{broken');
    expect(await store.load(tablet: true),
        ConnectionPanelPreferences.defaults(tablet: true));
  });

  test('bridge rejects external origins and retired controllers', () async {
    final store = ConnectionPanelPreferences();
    final controller = _Controller();
    var current = true;
    store.bind(controller, tablet: true, port: 12345, isCurrent: () => current);
    final patch = {'config/connection-card-lines': '[["host"]]'};
    controller.url = WebUri('https://example.com:12345');
    expect(await controller.callback([patch]), isFalse);
    controller.url = WebUri('http://127.0.0.1:54321');
    expect(await controller.callback([patch]), isFalse);
    controller.url = WebUri('http://127.0.0.1:12345');
    current = false;
    expect(await controller.callback([patch]), isFalse);
    current = true;
    expect(await controller.callback([patch]), isTrue);
    expect((await store.load(tablet: true))['config/connection-card-lines'],
        '[["host"]]');
  });

  const jsc =
      '/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc';
  test(
      'web content edits survive reapply and delayed native bridge availability',
      () {
    final script = ConnectionPanelPreferences.script(
      ConnectionPanelPreferences.defaults(tablet: true),
      tablet: true,
    );
    final result = Process.runSync(jsc, [
      '-e',
      '''
$_environment
$script
$script
$_checks
'''
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }, skip: !File(jsc).existsSync());
}

const _environment = r'''
const window = globalThis;
class Storage {
  constructor() { this.values = new Map(); }
  getItem(k) { return this.values.has(k) ? this.values.get(k) : null; }
  setItem(k,v) { this.values.set(String(k), String(v)); }
}
const localStorage = window.localStorage = new Storage();
const sessionStorage = new Storage();
const listeners = {};
window.addEventListener = (name, fn) => listeners[name] = fn;
window.dispatchEvent = () => {};
const document = {addEventListener() {}};
class StorageEvent { constructor() {} }
function check(value, message) { if (!value) throw new Error(message); }
''';
const _checks = r'''
check(localStorage.getItem('config/connection-display-style') === 'card', 'tablet uses phone cards');
check(localStorage.getItem('config/show-full-proxy-chain') === 'true', 'shared phone chain default');
localStorage.setItem('config/connection-card-lines', '[["host","close"]]');
window.__proxlyConnectionContent.apply({'config/connection-card-lines':'[["rule"]]'});
check(localStorage.getItem('config/connection-card-lines') === '[["host","close"]]', 'pending edit not reset');
const calls = [];
window.flutter_inappwebview = {callHandler(name, patch) { calls.push({...patch}); return Promise.resolve(true); }};
listeners.flutterInAppWebViewPlatformReady();
localStorage.setItem('config/show-full-proxy-chain', 'false');
sessionStorage.setItem('config/connection-card-lines', '[["rule"]]');
localStorage.setItem('clash_token', 'never-save');
Promise.resolve().then(() => Promise.resolve()).then(() => {
  check(calls.length === 2, 'serialize edits and flush edits made while sending');
  check(calls[0]['config/connection-card-lines'] === '[["host","close"]]', 'user content saved');
  check(calls[1]['config/show-full-proxy-chain'] === 'false', 'short-chain edit saved');
  check(calls.every(patch => !('clash_token' in patch)), 'unrelated keys excluded');
  print('Connection content bridge checks passed');
});
''';
