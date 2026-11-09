import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/connection_settings_store.dart';
import 'package:proxly/services/router_tool.dart';
import 'package:proxly/services/clash_config_file_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final values = <String, String>{};
  var resetOnNextRead = false;
  var dropNextWrite = false;
  var writeCalls = 0;

  setUp(() {
    values.clear();
    resetOnNextRead = false;
    dropNextWrite = false;
    writeCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      final key = arguments['key'] as String?;
      switch (call.method) {
        case 'read':
          if (resetOnNextRead) {
            resetOnNextRead = false;
            values.clear();
            return 'Data has been reset';
          }
          return values[key];
        case 'write':
          writeCalls++;
          if (dropNextWrite) {
            dropNextWrite = false;
            values.clear();
            return null;
          }
          values[key!] = arguments['value'] as String;
          return null;
        case 'delete':
          values.remove(key);
          return null;
        case 'deleteAll':
          values.clear();
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('router adapter and core persist; legacy settings retain OpenClash',
      () async {
    SharedPreferences.setMockInitialValues({});
    expect((await ConnectionSettingsStore.instance.load()).routerTool,
        RouterTool.openClash);
    await ConnectionSettingsStore.instance.saveController(
        host: 'router.local:9090',
        token: '',
        sshPassword: 'p',
        routerTool: RouterTool.nikki,
        core: ProxyCore.mihomo);
    expect((await ConnectionSettingsStore.instance.load()).routerTool,
        RouterTool.nikki);
    expect(
        (await ConnectionSettingsStore.instance.load()).core, ProxyCore.mihomo);
    await ConnectionSettingsStore.instance.saveSshPassword('p2');
    expect(await ConnectionSettingsStore.instance.loadRouterTool(),
        RouterTool.nikki);
    await ConnectionSettingsStore.instance.clearConnectionData();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('router_tool'), isFalse);
    expect(prefs.containsKey('proxy_core'), isFalse);
    expect(RouterTool.parse('unsupported'), RouterTool.generic);
  });

  test('secure storage reset clears restored connection data', () async {
    SharedPreferences.setMockInitialValues({
      'clash_host': '192.168.1.1:9090',
      'ssh_port': 2222,
    });
    resetOnNextRead = true;

    final settings = await ConnectionSettingsStore.instance.load();
    final prefs = await SharedPreferences.getInstance();

    expect(settings.host, isEmpty);
    expect(settings.token, isEmpty);
    expect(settings.sshPassword, isEmpty);
    expect(prefs.containsKey('clash_host'), isFalse);
    expect(prefs.containsKey('ssh_port'), isFalse);
    expect(settings.sshPort, 22);
    expect(
      ConnectionSettingsStore.instance.lastChange,
      ConnectionSettingsChange.reset,
    );
  });

  test('save retries once if Android reset discards the first write', () async {
    SharedPreferences.setMockInitialValues({});
    dropNextWrite = true;

    await ConnectionSettingsStore.instance.saveController(
      host: '192.168.1.1:9090',
      token: 'secret',
      sshPassword: 'password',
    );
    final settings = await ConnectionSettingsStore.instance.load();

    expect(writeCalls, 3);
    expect(settings.host, '192.168.1.1:9090');
    expect(settings.token, 'secret');
    expect(settings.sshPassword, 'password');
    expect(
      ConnectionSettingsStore.instance.lastChange,
      ConnectionSettingsChange.controller,
    );
  });

  test('SSH port accepts only decimal ports and defaults blank to 22', () {
    for (final text in ['', '  ', '22', ' 22 ']) {
      expect(ConnectionSettings.parseSshPort(text), 22);
    }
    expect(ConnectionSettings.parseSshPort('1'), 1);
    expect(ConnectionSettings.parseSshPort('65535'), 65535);
    for (final text in ['0', '65536', '-1', '+22', '2.2', '2e2', 'abc']) {
      expect(ConnectionSettings.parseSshPort(text), isNull, reason: text);
    }
  });

  test('legacy settings use port 22 without changing stored credentials',
      () async {
    SharedPreferences.setMockInitialValues({'clash_host': 'router.local:9090'});
    values['ssh_password'] = 'password';
    final settings = await ClashConfigFileService.loadSettings();
    expect(settings.port, 22);
    expect(settings.host, 'router.local');
    expect(values['ssh_password'], 'password');
  });

  test('custom SSH port persists and reaches configuration and trust targets',
      () async {
    SharedPreferences.setMockInitialValues({});
    await ConnectionSettingsStore.instance.saveController(
      host: 'router.local:9090',
      token: 'secret',
      sshPassword: 'password',
      sshPort: 2222,
    );
    await ConnectionSettingsStore.instance.saveSshPassword('new-password');
    expect((await ConnectionSettingsStore.instance.load()).sshPort, 2222);
    final settings = await ClashConfigFileService.loadSettings();
    final target = await ClashConfigFileService.routerTarget();
    expect(settings.host, 'router.local');
    expect(settings.port, 2222);
    expect(settings.password, 'new-password');
    expect(settings.target.matches(target), isTrue);
    await ConnectionSettingsStore.instance.clearConnectionData();
    expect((await SharedPreferences.getInstance()).containsKey('ssh_port'),
        isFalse);
    expect((await ConnectionSettingsStore.instance.load()).sshPort, 22);
  });

  test('invalid saved port falls back and invalid writes preserve settings',
      () async {
    SharedPreferences.setMockInitialValues({'ssh_port': 65536});
    expect((await ConnectionSettingsStore.instance.load()).sshPort, 22);
    await expectLater(
        ConnectionSettingsStore.instance.saveController(
          host: 'router.local:9090',
          token: 'secret',
          sshPassword: 'password',
          sshPort: 0,
        ),
        throwsRangeError);
    expect(values, isEmpty);
    expect(writeCalls, 0);
    expect((await SharedPreferences.getInstance()).getInt('ssh_port'), 65536);
  });

  test('SSH password changes notify active settings consumers', () async {
    SharedPreferences.setMockInitialValues({});
    var notifications = 0;
    void listener() => notifications++;
    ConnectionSettingsStore.instance.addListener(listener);
    addTearDown(
        () => ConnectionSettingsStore.instance.removeListener(listener));

    await ConnectionSettingsStore.instance.saveSshPassword('new-password');

    expect(notifications, 1);
    expect(values['ssh_password'], 'new-password');
    expect(
      ConnectionSettingsStore.instance.lastChange,
      ConnectionSettingsChange.sshPassword,
    );
  });
}
