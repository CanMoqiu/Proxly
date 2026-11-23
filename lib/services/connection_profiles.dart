part of 'connection_settings_store.dart';

class DeviceProfile {
  const DeviceProfile._({
    required this.id,
    required this.name,
    required this.host,
    required this.sshPort,
    required this.routerTool,
    required this.core,
    required this.selectionPending,
    required this.toolConfirmed,
    required this.credentialsKey,
  });

  final String id, name, host;
  final int sshPort;
  final RouterTool routerTool;
  final ProxyCore core;
  final bool selectionPending, toolConfirmed;
  final String credentialsKey;

  factory DeviceProfile._fromJson(Map<String, dynamic> json) => DeviceProfile._(
        id: json['id'] as String,
        name: json['name'] as String,
        host: json['host'] as String,
        sshPort: json['sshPort'] as int,
        routerTool: RouterTool.parse(json['routerTool'] as String?),
        core: ProxyCore.parse(json['core'] as String?),
        selectionPending: json['selectionPending'] == true,
        toolConfirmed: json['toolConfirmed'] == true,
        credentialsKey: json['credentials'] as String,
      );

  Map<String, Object> _toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'sshPort': sshPort,
        'routerTool': routerTool.name,
        'core': core.name,
        'selectionPending': selectionPending,
        'toolConfirmed': toolConfirmed,
        'credentials': credentialsKey,
      };

  DeviceProfile _withIdentity(
    RouterTool tool,
    ProxyCore core,
    bool pending,
    bool confirmed, {
    String? name,
  }) =>
      DeviceProfile._(
        id: id,
        name: name ?? this.name,
        host: host,
        sshPort: sshPort,
        routerTool: tool,
        core: core,
        selectionPending: pending,
        toolConfirmed: confirmed,
        credentialsKey: credentialsKey,
      );

  Future<ConnectionSettings> _loadSettings() async {
    try {
      final raw =
          await AppSecureStorage.read(credentialsKey, preserveOnError: true);
      if (raw == null) throw const SecureStorageUnavailableException();
      final secret = jsonDecode(raw) as Map<String, dynamic>;
      return ConnectionSettings(
        deviceId: id,
        host: host,
        sshPort: sshPort,
        routerTool: routerTool,
        core: core,
        token: secret['token'] as String,
        sshPassword: secret['sshPassword'] as String,
      );
    } catch (_) {
      throw const SecureStorageUnavailableException();
    }
  }
}

class _DeviceCatalog {
  const _DeviceCatalog(this.devices, this.activeId);

  static const key = 'connection_profiles_v1';
  final List<DeviceProfile> devices;
  final String? activeId;

  DeviceProfile? find(String? id) {
    for (final profile in devices) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  DeviceProfile? get active => find(activeId);

  static _DeviceCatalog? read(SharedPreferences prefs) {
    final raw = prefs.getString(key);
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final devices = (data['devices'] as List<dynamic>)
        .map((entry) => DeviceProfile._fromJson(entry as Map<String, dynamic>))
        .toList(growable: false);
    final catalog = _DeviceCatalog(devices, data['activeId'] as String?);
    if (devices.map((device) => device.id).toSet().length != devices.length ||
        (devices.isNotEmpty && catalog.active == null)) {
      throw const FormatException('Invalid device catalog');
    }
    return catalog;
  }

  Future<void> write(SharedPreferences prefs) async {
    final encoded = jsonEncode({
      'activeId': activeId,
      'devices': devices.map((profile) => profile._toJson()).toList(),
    });
    try {
      if (await prefs.setString(key, encoded)) return;
    } catch (_) {
      await prefs.reload();
      if (prefs.getString(key) == encoded) return;
      rethrow;
    }
    await prefs.reload();
    if (prefs.getString(key) == encoded) return;
    throw StateError('Could not save devices');
  }

  _DeviceCatalog replace(DeviceProfile profile) => _DeviceCatalog(
        [
          for (final other in devices)
            if (other.id == profile.id) profile else other,
          if (find(profile.id) == null) profile,
        ],
        activeId ?? profile.id,
      );
}
