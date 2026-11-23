import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/app_secure_storage.dart';
import 'package:proxly/services/connection_settings_store.dart';
import 'package:proxly/services/router_tool.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final store = ConnectionSettingsStore.instance;
  final secrets = <String, String>{};
  bool failWrites = false;
  String? unavailableKey;

  setUp(() {
    secrets.clear();
    failWrites = false;
    unavailableKey = null;
    SharedPreferences.setMockInitialValues({
      'clash_host': 'router.local:9090',
      'router_tool': 'nikki',
      'proxy_core': 'mihomo',
      'ssh_port': 2222,
      'router_tool_confirmed': true,
    });
    secrets.addAll(
        {'clash_token': 'legacy-token', 'ssh_password': 'legacy-password'});
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          if (key == unavailableKey) {
            throw PlatformException(code: 'unavailable');
          }
          return secrets[key];
        case 'write':
          if (!failWrites) secrets[key!] = args['value'] as String;
          return null;
        case 'delete':
          secrets.remove(key);
          return null;
      }
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<DeviceProfile> addOther() => store.saveDevice(
        name: 'Office',
        host: 'router.local:9090',
        token: 'office-token',
        sshPassword: 'office-password',
        sshPort: 22,
      );

  test(
      'migrate once, keep same-address profiles separate, and remember selection',
      () async {
    await store.initializeProfiles();
    final original = store.activeDevice!;
    expect(original.name, 'router.local:9090');
    expect((await store.load()).routerTool, RouterTool.nikki);
    expect((await store.load()).core, ProxyCore.mihomo);
    expect((await store.load()).sshPort, 2222);
    expect((await store.load()).token, 'legacy-token');
    final other = await addOther();
    expect(other.id, isNot(original.id));
    expect(store.activeDevice?.id, original.id);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('connection_profiles_v1'),
        isNot(contains('office-token')));

    await store.switchDevice(other.id);
    await store.initializeProfiles();
    expect(store.activeDevice?.id, other.id);
    expect((await store.load()).token, 'office-token');
    expect((await store.load()).sshPassword, 'office-password');
    await expectLater(store.deleteDevice(other.id), throwsStateError);
    await store.switchDevice(original.id);
    await store.deleteDevice(other.id);
    expect(
        (await store.loadDevices()).map((device) => device.id), [original.id]);
    expect(
        secrets.values.any((value) => value.contains('office-token')), isFalse);
  });

  test('failed secure migration retains the usable legacy record for retry',
      () async {
    failWrites = true;
    await expectLater(store.initializeProfiles(),
        throwsA(isA<SecureStorageResetException>()));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('connection_profiles_v1'), isNull);
    expect(secrets['clash_token'], 'legacy-token');
    expect(secrets['ssh_password'], 'legacy-password');
    failWrites = false;
    await store.initializeProfiles();
    expect((await store.load()).token, 'legacy-token');
  });

  test('unavailable target credentials leave the old device and epoch active',
      () async {
    await store.initializeProfiles();
    final original = store.activeDevice!.id;
    final target = await addOther();
    unavailableKey = target.credentialsKey;
    final generation = store.deviceGeneration;
    await expectLater(store.switchDevice(target.id),
        throwsA(isA<SecureStorageUnavailableException>()));
    expect(store.activeDevice?.id, original);
    expect(store.deviceGeneration, generation);
    expect((await store.load()).token, 'legacy-token');
  });

  test(
    'renaming changes only metadata and uses the same name validation',
    () async {
      await store.initializeProfiles();
      final original = store.activeDevice!;
      final other = await addOther();
      final generation = store.deviceGeneration;
      final saved = Map<String, String>.of(secrets);
      unavailableKey = original.credentialsKey;

      await expectLater(
        store.renameDevice(original.id, ' office '),
        throwsArgumentError,
      );
      await store.renameDevice(original.id, ' Home ');
      await store.renameDevice(other.id, 'Work');
      expect(store.activeDevice?.name, 'Home');
      expect(store.activeDevice?.id, original.id);
      expect(store.deviceGeneration, generation);
      expect(secrets, saved);
      expect((await store.loadDevices()).map((device) => device.name), [
        'Home',
        'Work',
      ]);
    },
  );

  test('a rejected active selection write keeps the previous selection',
      () async {
    await store.initializeProfiles();
    final original = store.activeDevice!.id;
    final target = await addOther();
    final generation = store.deviceGeneration;
    final platform = SharedPreferencesStorePlatform.instance;
    final current = await platform.getAll();
    SharedPreferencesStorePlatform.instance = _RejectCatalogWrite(current);
    addTearDown(() => SharedPreferencesStorePlatform.instance = platform);

    await expectLater(store.switchDevice(target.id), throwsStateError);
    expect(store.deviceGeneration, generation);
    expect(store.activeDevice?.id, original);
    expect((await store.load()).deviceId, original);
    await store.initializeProfiles();
    expect(store.activeDevice?.id, original);
  });

  test(
      'remote writes prevent switching and stale detection cannot overwrite another device',
      () async {
    await store.initializeProfiles();
    final original = store.activeDevice!.id;
    final target = await addOther();
    final revision = store.revision;
    final generation = store.deviceGeneration;
    final gate = Completer<void>();
    final writing = store.runRemoteOperation(() => gate.future);
    expect(store.canSwitchDevice, isFalse);
    await expectLater(store.switchDevice(target.id), throwsStateError);
    expect(store.activeDevice?.id, original);
    gate.complete();
    await writing;

    await store.switchDevice(target.id);
    expect(() => store.requireDeviceGeneration(generation), throwsStateError);
    expect(
        await store.applyRouterDetection(
          expectedHost: target.host,
          expectedRevision: revision,
          tool: RouterTool.openClash,
          core: ProxyCore.clash,
        ),
        isFalse);
    expect((await store.load()).routerTool, RouterTool.generic);
    await Future.wait(
        [store.switchDevice(original), store.switchDevice(target.id)]);
    expect((await store.load()).deviceId, target.id);
  });

  test('the first configuration saved by onboarding becomes the active device',
      () async {
    SharedPreferences.setMockInitialValues({});
    await store.initializeProfiles();
    expect(store.activeDevice, isNull);
    await store.saveController(
        host: 'first.local:9090', token: 'new', sshPassword: '');
    expect(store.activeDevice?.name, 'first.local:9090');
    expect((await store.load()).token, 'new');
    expect(await store.loadDevices(), hasLength(1));
  });
}

class _RejectCatalogWrite extends InMemorySharedPreferencesStore {
  _RejectCatalogWrite(super.data) : super.withData();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.connection_profiles_v1') return false;
    return super.setValue(valueType, key, value);
  }
}
