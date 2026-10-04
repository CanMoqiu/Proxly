import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/connection_settings_store.dart';
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

  test('secure storage reset clears restored connection data', () async {
    SharedPreferences.setMockInitialValues({'clash_host': '192.168.1.1:9090'});
    resetOnNextRead = true;

    final settings = await ConnectionSettingsStore.instance.load();
    final prefs = await SharedPreferences.getInstance();

    expect(settings.host, isEmpty);
    expect(settings.token, isEmpty);
    expect(settings.sshPassword, isEmpty);
    expect(prefs.containsKey('clash_host'), isFalse);
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
