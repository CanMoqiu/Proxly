import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageResetException implements Exception {
  const SecureStorageResetException();

  @override
  String toString() => 'Secure storage data was reset';
}

class SecureStorageUnavailableException implements Exception {
  const SecureStorageUnavailableException();

  @override
  String toString() =>
      'Credentials are temporarily unavailable. Unlock the device and retry.';
}

class AppSecureStorage {
  AppSecureStorage._();

  static const _resetResponse = 'Data has been reset';
  static const instance = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
  );
  static const _profileStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
  );

  static Future<String?> read(String key,
      {bool preserveOnError = false}) async {
    final storage = preserveOnError ? _profileStorage : instance;
    final value = await storage.read(key: key);
    if (value == _resetResponse) throw const SecureStorageResetException();
    return value;
  }

  static Future<void> write(
    String key,
    String value, {
    bool preserveOnError = false,
  }) async {
    final storage = preserveOnError ? _profileStorage : instance;
    await storage.write(key: key, value: value);
    var saved = await storage.read(key: key);
    if (saved == _resetResponse || saved != value) {
      await storage.write(key: key, value: value);
      saved = await storage.read(key: key);
    }
    if (saved == _resetResponse || saved != value) {
      throw const SecureStorageResetException();
    }
  }

  static Future<void> delete(String key, {bool preserveOnError = false}) =>
      (preserveOnError ? _profileStorage : instance).delete(key: key);

  static Future<void> deleteAll() => instance.deleteAll();
}
