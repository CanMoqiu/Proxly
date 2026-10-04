import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_secure_storage.dart';
import 'app_platform.dart';

class ConnectionSettings {
  const ConnectionSettings({
    required this.host,
    required this.token,
    required this.sshPassword,
  });

  final String host;
  final String token;
  final String sshPassword;
}

enum ConnectionSettingsChange { controller, sshPassword, reset }

class ConnectionSettingsStore extends ChangeNotifier {
  ConnectionSettingsStore._();

  static final instance = ConnectionSettingsStore._();

  ConnectionSettingsChange? lastChange;

  Future<ConnectionSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      return ConnectionSettings(
        host: prefs.getString('clash_host') ?? '',
        token: await AppSecureStorage.read('clash_token') ?? '',
        sshPassword: await AppSecureStorage.read('ssh_password') ?? '',
      );
    } catch (_) {
      // A locked/inaccessible iOS Keychain is not evidence of corruption.
      // Preserve both preferences and secrets so a later retry can recover.
      if (AppPlatform.isIOS) throw const SecureStorageUnavailableException();
      await _resetAfterSecureStorageFailure(prefs);
      return const ConnectionSettings(host: '', token: '', sshPassword: '');
    }
  }

  Future<void> saveController({
    required String host,
    required String token,
    required String sshPassword,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await AppSecureStorage.write('clash_token', token);
    await AppSecureStorage.write('ssh_password', sshPassword);
    await prefs.setString('clash_host', host);
    lastChange = ConnectionSettingsChange.controller;
    notifyListeners();
  }

  Future<void> saveSshPassword(String password) async {
    await AppSecureStorage.write('ssh_password', password);
    lastChange = ConnectionSettingsChange.sshPassword;
    notifyListeners();
  }

  Future<void> clearConnectionData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('clash_host');
    await AppSecureStorage.deleteAll();
    lastChange = ConnectionSettingsChange.reset;
    notifyListeners();
  }

  Future<void> _resetAfterSecureStorageFailure(
    SharedPreferences prefs,
  ) async {
    await prefs.remove('clash_host');
    try {
      await AppSecureStorage.deleteAll();
    } catch (_) {
      // resetOnError recreates the Android storage on the next operation.
    }
    lastChange = ConnectionSettingsChange.reset;
    notifyListeners();
  }
}
