import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_secure_storage.dart';
import 'app_platform.dart';
import 'router_tool.dart';

part 'connection_profiles.dart';

class ConnectionSettings {
  const ConnectionSettings({
    this.deviceId,
    required this.host,
    required this.token,
    required this.sshPassword,
    this.sshPort = 22,
    this.routerTool = RouterTool.openClash,
    this.core = ProxyCore.unknown,
  });

  final String host;
  final String? deviceId;
  final String token;
  final String sshPassword;
  final int sshPort;
  final RouterTool routerTool;
  final ProxyCore core;

  static int? parseSshPort(String value) {
    final text = value.trim();
    if (text.isEmpty) return 22;
    if (!RegExp(r'^[0-9]+$').hasMatch(text)) return null;
    final port = int.tryParse(text);
    return port != null && port >= 1 && port <= 65535 ? port : null;
  }
}

enum ConnectionSettingsChange {
  controller,
  device,
  routerIdentity,
  sshPassword,
  reset
}

class ConnectionSettingsStore extends ChangeNotifier {
  ConnectionSettingsStore._();

  static final instance = ConnectionSettingsStore._();

  ConnectionSettingsChange? lastChange;
  int revision = 0;
  Future<void>? _controllerWrite;
  final profilesChanged = ValueNotifier<int>(0);
  DeviceProfile? activeDevice;
  int deviceGeneration = 0;
  int _remoteOperations = 0;
  bool _transitioning = false;
  final Set<String> _temporaryBackendSelections = {};

  bool hasTemporaryBackendSelection(String? deviceId) =>
      _temporaryBackendSelections.contains(deviceId ?? 'legacy');

  void expireTemporaryBackendSelections() =>
      _temporaryBackendSelections.clear();

  bool get canSwitchDevice => !_transitioning && _remoteOperations == 0;

  void requireDeviceGeneration(int expected) {
    if (deviceGeneration != expected || _transitioning) {
      throw StateError('The active device changed');
    }
  }

  Future<T> runRemoteOperation<T>(
    Future<T> Function() action, {
    int? expectedGeneration,
  }) async {
    requireDeviceGeneration(expectedGeneration ?? deviceGeneration);
    _remoteOperations++;
    profilesChanged.value++;
    try {
      return await action();
    } finally {
      _remoteOperations--;
      profilesChanged.value++;
    }
  }

  Future<T> _changeConnection<T>(Future<T> Function() action) async {
    if (!canSwitchDevice) throw StateError('A device operation is in progress');
    _transitioning = true;
    profilesChanged.value++;
    try {
      return await action();
    } finally {
      _transitioning = false;
      profilesChanged.value++;
    }
  }

  void _notify(ConnectionSettingsChange change) {
    lastChange = change;
    revision++;
    if (change == ConnectionSettingsChange.device ||
        change == ConnectionSettingsChange.controller ||
        change == ConnectionSettingsChange.reset) {
      deviceGeneration++;
    }
    notifyListeners();
  }

  static final _random = Random.secure();

  static String _newId() => List.generate(
      16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  static String reserveInitialDeviceId() => _newId();

  Future<void> initializeProfiles() => _serializeControllerWrite(() async {
        final prefs = await SharedPreferences.getInstance();
        await _initializeProfiles(prefs);
      });

  Future<_DeviceCatalog> _initializeProfiles(SharedPreferences prefs) async {
    final existing = _DeviceCatalog.read(prefs);
    if (existing != null) {
      activeDevice = existing.active;
      return existing;
    }
    final host = prefs.getString('clash_host') ?? '';
    if (host.isEmpty) {
      const empty = _DeviceCatalog([], null);
      await empty.write(prefs);
      activeDevice = null;
      return empty;
    }
    final String token;
    final String password;
    try {
      token =
          await AppSecureStorage.read('clash_token', preserveOnError: true) ??
              '';
      password =
          await AppSecureStorage.read('ssh_password', preserveOnError: true) ??
              '';
    } catch (_) {
      throw const SecureStorageUnavailableException();
    }
    final profile = await _storeProfile(
      prefs,
      const _DeviceCatalog([], null),
      name: host,
      host: host,
      token: token,
      password: password,
      port: ConnectionSettings.parseSshPort(
              prefs.get('ssh_port')?.toString() ?? '') ??
          22,
      tool: RouterTool.parse(prefs.getString('router_tool')),
      core: ProxyCore.parse(prefs.getString('proxy_core')),
      pending: prefs.getBool('router_tool_selection_pending') == true,
      confirmed: prefs.getBool('router_tool_confirmed') == true,
      id: 'legacy',
    );
    await _discardCredential('clash_token');
    await _discardCredential('ssh_password');
    return _DeviceCatalog([profile], profile.id);
  }

  Future<List<DeviceProfile>> loadDevices() =>
      _serializeControllerWrite(() async {
        final prefs = await SharedPreferences.getInstance();
        final catalog = await _initializeProfiles(prefs);
        return List.unmodifiable(catalog.devices);
      });

  Future<ConnectionSettings> loadDevice(String id) =>
      _serializeControllerWrite(() async {
        final catalog =
            _DeviceCatalog.read(await SharedPreferences.getInstance());
        final device = catalog?.find(id);
        if (device == null) throw StateError('Device no longer exists');
        return device._loadSettings();
      });

  Future<DeviceProfile> saveDevice({
    String? id,
    required String name,
    required String host,
    required String token,
    required String sshPassword,
    required int sshPort,
    RouterTool? routerTool,
  }) =>
      _serializeControllerWrite(() async {
        final prefs = await SharedPreferences.getInstance();
        final catalog = await _initializeProfiles(prefs);
        final old = catalog.find(id);
        if (id != null && old == null) {
          throw StateError('Device no longer exists');
        }
        final label = _validatedDeviceName(catalog, name, id);
        final sameTarget =
            old != null && old.host == host && old.sshPort == sshPort;
        Future<DeviceProfile> save() => _storeProfile(
              prefs,
              catalog,
              id: id,
              name: label,
              host: host,
              token: token,
              password: sshPassword,
              port: sshPort,
              tool: routerTool ??
                  (sameTarget ? old.routerTool : RouterTool.generic),
              core: sameTarget ? old.core : ProxyCore.unknown,
              pending: routerTool == null && sameTarget && old.selectionPending,
              confirmed: routerTool != null || sameTarget && old.toolConfirmed,
            );
        if (catalog.activeId == id) {
          return _changeConnection(() async {
            final result = await save();
            _notify(ConnectionSettingsChange.controller);
            return result;
          });
        }
        return save();
      });

  static String _validatedDeviceName(
    _DeviceCatalog catalog,
    String name,
    String? id,
  ) {
    final label = name.trim();
    if (label.isEmpty) throw ArgumentError('Device name is required');
    if (catalog.devices.any(
      (device) =>
          device.id != id && device.name.toLowerCase() == label.toLowerCase(),
    )) {
      throw ArgumentError('Device name is already in use');
    }
    return label;
  }

  Future<void> renameDevice(String id, String name) =>
      _serializeControllerWrite(() async {
        final prefs = await SharedPreferences.getInstance();
        final catalog = await _initializeProfiles(prefs);
        final device = catalog.find(id);
        if (device == null) throw StateError('Device no longer exists');
        final label = _validatedDeviceName(catalog, name, id);
        if (label == device.name) return;
        final updated = catalog.replace(
          device._withIdentity(
            device.routerTool,
            device.core,
            device.selectionPending,
            device.toolConfirmed,
            name: label,
          ),
        );
        await updated.write(prefs);
        activeDevice = updated.active;
        profilesChanged.value++;
      });

  Future<DeviceProfile> _storeProfile(
    SharedPreferences prefs,
    _DeviceCatalog catalog, {
    String? id,
    required String name,
    required String host,
    required String token,
    required String password,
    required int port,
    required RouterTool tool,
    required ProxyCore core,
    required bool pending,
    required bool confirmed,
  }) async {
    if (host.isEmpty || port < 1 || port > 65535) {
      throw ArgumentError('Invalid device endpoint');
    }
    final key = 'proxly_device_credentials_${_newId()}';
    final next = DeviceProfile._(
      id: id ?? _newId(),
      name: name,
      host: host,
      sshPort: port,
      routerTool: tool,
      core: core,
      selectionPending: pending,
      toolConfirmed: confirmed,
      credentialsKey: key,
    );
    final replacement = catalog.replace(next);
    await AppSecureStorage.write(
        key, jsonEncode({'token': token, 'sshPassword': password}),
        preserveOnError: true);
    await replacement.write(prefs);
    activeDevice = replacement.active;
    final previous = catalog.find(id);
    if (previous != null) await _discardCredential(previous.credentialsKey);
    profilesChanged.value++;
    return next;
  }

  Future<void> _discardCredential(String key) async {
    try {
      await AppSecureStorage.delete(key, preserveOnError: true);
    } catch (_) {
      // The catalog has already been committed and no longer references this key.
    }
  }

  Future<void> switchDevice(String id) => _serializeControllerWrite(() async {
        final prefs = await SharedPreferences.getInstance();
        final catalog = await _initializeProfiles(prefs);
        if (catalog.activeId == id) return;
        final device = catalog.find(id);
        if (device == null) throw StateError('Device no longer exists');
        await _changeConnection(() async {
          await device._loadSettings();
          await _DeviceCatalog(catalog.devices, id).write(prefs);
          activeDevice = device;
          _notify(ConnectionSettingsChange.device);
        });
      });

  Future<void> deleteDevice(String id) => _serializeControllerWrite(() async {
        final prefs = await SharedPreferences.getInstance();
        final catalog = await _initializeProfiles(prefs);
        if (catalog.activeId == id) {
          throw StateError('Cannot delete the active device');
        }
        final device = catalog.find(id);
        if (device == null) return;
        await _DeviceCatalog(
          catalog.devices.where((other) => other.id != id).toList(),
          catalog.activeId,
        ).write(prefs);
        _temporaryBackendSelections.remove(id);
        await _discardCredential(device.credentialsKey);
        profilesChanged.value++;
      });

  Future<T> _serializeControllerWrite<T>(Future<T> Function() action) {
    final next =
        (_controllerWrite ?? Future<void>.value()).then((_) => action());
    late final Future<void> settled;
    settled = next.then<void>((_) {}).catchError((_) {}).whenComplete(() {
      if (identical(_controllerWrite, settled)) _controllerWrite = null;
    });
    _controllerWrite = settled;
    return next;
  }

  Future<({String host, int revision})?> pendingRouterToolSelection() async {
    final pending = _controllerWrite;
    if (pending != null) await pending;
    final prefs = await SharedPreferences.getInstance();
    final catalog = _DeviceCatalog.read(prefs);
    if (catalog != null) {
      final device = catalog.active;
      return device != null && device.selectionPending
          ? (host: device.host, revision: revision)
          : null;
    }
    final host = prefs.getString('clash_host') ?? '';
    if (prefs.getBool('router_tool_selection_pending') != true ||
        host.isEmpty) {
      return null;
    }
    return (host: host, revision: revision);
  }

  Future<bool> confirmRouterTool(
    RouterTool tool, {
    required String expectedHost,
    required int expectedRevision,
  }) =>
      _saveRouterTool(tool,
          expectedHost: expectedHost,
          expectedRevision: expectedRevision,
          requirePending: true);

  Future<bool> selectRouterTool(
    RouterTool tool, {
    required String expectedHost,
    required int expectedRevision,
  }) =>
      _saveRouterTool(tool,
          expectedHost: expectedHost,
          expectedRevision: expectedRevision,
          requirePending: false);

  Future<({String host, int revision, RouterTool tool})> loadRouterIdentity() =>
      _serializeControllerWrite(() async {
        final prefs = await SharedPreferences.getInstance();
        final catalog = _DeviceCatalog.read(prefs);
        final device = catalog?.active;
        if (catalog != null) {
          return (
            host: device?.host ?? '',
            revision: revision,
            tool: device?.routerTool ?? RouterTool.generic
          );
        }
        return (
          host: prefs.getString('clash_host') ?? '',
          revision: revision,
          tool: RouterTool.parse(prefs.getString('router_tool'))
        );
      });

  Future<bool> _saveRouterTool(
    RouterTool tool, {
    required String expectedHost,
    required int expectedRevision,
    required bool requirePending,
  }) =>
      _serializeControllerWrite(() async {
        final prefs = await SharedPreferences.getInstance();
        final catalog = _DeviceCatalog.read(prefs);
        if (catalog != null) {
          final device = catalog.active;
          if (device == null ||
              revision != expectedRevision ||
              device.host != expectedHost ||
              (requirePending && !device.selectionPending)) {
            return false;
          }
          await _saveProfileIdentity(prefs, catalog,
              device._withIdentity(tool, device.core, false, true));
          return true;
        }
        if (revision != expectedRevision ||
            (prefs.getString('clash_host') ?? '') != expectedHost ||
            (requirePending &&
                prefs.getBool('router_tool_selection_pending') != true)) {
          return false;
        }
        if (!await prefs.setString('router_tool', tool.name) ||
            !await prefs.setBool('router_tool_selection_pending', false) ||
            !await prefs.setBool('router_tool_confirmed', true)) {
          throw StateError('Could not save router tool selection');
        }
        lastChange = ConnectionSettingsChange.routerIdentity;
        revision++;
        notifyListeners();
        return true;
      });

  Future<bool> applyRouterDetection({
    required String expectedHost,
    required int expectedRevision,
    required RouterTool tool,
    required ProxyCore core,
  }) =>
      _serializeControllerWrite(() async {
        final prefs = await SharedPreferences.getInstance();
        final catalog = _DeviceCatalog.read(prefs);
        if (catalog != null) {
          final device = catalog.active;
          if (device == null ||
              revision != expectedRevision ||
              device.host != expectedHost) {
            return false;
          }
          final preserve = hasTemporaryBackendSelection(device.id) ||
              tool == RouterTool.generic && device.toolConfirmed;
          final resolvedTool = preserve ? device.routerTool : tool;
          final resolvedCore =
              preserve && core == ProxyCore.unknown ? device.core : core;
          final pending = tool == RouterTool.generic && !preserve;
          if (resolvedTool != device.routerTool ||
              resolvedCore != device.core ||
              pending != device.selectionPending) {
            await _saveProfileIdentity(
                prefs,
                catalog,
                device._withIdentity(
                    resolvedTool, resolvedCore, pending, device.toolConfirmed));
          }
          return true;
        }
        if (revision != expectedRevision ||
            prefs.getString('clash_host') != expectedHost) {
          return false;
        }
        final preserveChoice = hasTemporaryBackendSelection(null) ||
            tool == RouterTool.generic &&
                prefs.getBool('router_tool_confirmed') == true;
        final resolvedTool = preserveChoice
            ? RouterTool.parse(prefs.getString('router_tool'))
            : tool;
        final resolvedCore = preserveChoice && core == ProxyCore.unknown
            ? ProxyCore.parse(prefs.getString('proxy_core'))
            : core;
        final pending = tool == RouterTool.generic && !preserveChoice;
        if (prefs.getString('router_tool') == resolvedTool.name &&
            prefs.getString('proxy_core') == resolvedCore.name &&
            prefs.getBool('router_tool_selection_pending') == pending) {
          return true;
        }
        if (!await prefs.setString('router_tool', resolvedTool.name) ||
            !await prefs.setString('proxy_core', resolvedCore.name) ||
            !await prefs.setBool('router_tool_selection_pending', pending)) {
          throw StateError('Could not save router detection');
        }
        lastChange = ConnectionSettingsChange.routerIdentity;
        revision++;
        notifyListeners();
        return true;
      });

  Future<void> _saveProfileIdentity(
    SharedPreferences prefs,
    _DeviceCatalog catalog,
    DeviceProfile device,
  ) async {
    await catalog.replace(device).write(prefs);
    activeDevice = device;
    _notify(ConnectionSettingsChange.routerIdentity);
    profilesChanged.value++;
  }

  Future<RouterTool> loadRouterTool() async {
    final pending = _controllerWrite;
    if (pending != null) await pending;
    final prefs = await SharedPreferences.getInstance();
    final catalog = _DeviceCatalog.read(prefs);
    if (catalog != null) {
      return catalog.active?.routerTool ?? RouterTool.generic;
    }
    return RouterTool.parse(prefs.getString('router_tool'));
  }

  Future<ConnectionSettings> load() => _serializeControllerWrite(_load);

  Future<ConnectionSettings> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final catalog = _DeviceCatalog.read(prefs);
    if (catalog != null) {
      final device = catalog.active;
      return device == null
          ? const ConnectionSettings(host: '', token: '', sshPassword: '')
          : device._loadSettings();
    }
    try {
      return ConnectionSettings(
        host: prefs.getString('clash_host') ?? '',
        routerTool: RouterTool.parse(prefs.getString('router_tool')),
        core: ProxyCore.parse(prefs.getString('proxy_core')),
        token: await AppSecureStorage.read('clash_token') ?? '',
        sshPassword: await AppSecureStorage.read('ssh_password') ?? '',
        sshPort: ConnectionSettings.parseSshPort(
              prefs.get('ssh_port')?.toString() ?? '',
            ) ??
            22,
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
    String? deviceName,
    String? initialDeviceId,
    int sshPort = 22,
    RouterTool routerTool = RouterTool.openClash,
    ProxyCore core = ProxyCore.unknown,
    bool routerSelectionPending = false,
    bool routerToolConfirmed = false,
    bool temporaryBackendSelection = false,
  }) =>
      _serializeControllerWrite(() async {
        if (sshPort < 1 || sshPort > 65535) {
          throw RangeError.range(sshPort, 1, 65535, 'sshPort');
        }
        final prefs = await SharedPreferences.getInstance();
        final catalog = deviceName == null && initialDeviceId == null
            ? _DeviceCatalog.read(prefs)
            : await _initializeProfiles(prefs);
        final device = catalog?.active;
        final keepBackend = !temporaryBackendSelection &&
            hasTemporaryBackendSelection(device?.id);
        final selectedTool = keepBackend
            ? device?.routerTool ??
                RouterTool.parse(prefs.getString('router_tool'))
            : routerTool;
        final pinBackend = temporaryBackendSelection || keepBackend;
        final pending = routerSelectionPending && !pinBackend;
        if (catalog != null) {
          if (initialDeviceId != null &&
              device != null &&
              device.id != initialDeviceId) {
            throw StateError('An active device already exists');
          }
          final inputName = deviceName?.trim();
          final name = inputName == null
              ? device?.name ?? host
              : _validatedDeviceName(
                  catalog, inputName.isEmpty ? host : inputName, device?.id);
          await _changeConnection(() async {
            final saved = await _storeProfile(prefs, catalog,
                id: device?.id ?? initialDeviceId,
                name: name,
                host: host,
                token: token,
                password: sshPassword,
                port: sshPort,
                tool: selectedTool,
                core: core,
                pending: pending,
                confirmed: !pending &&
                    (pinBackend ||
                        routerToolConfirmed ||
                        (device?.host == host &&
                            device?.routerTool == selectedTool &&
                            device!.toolConfirmed)));
            if (temporaryBackendSelection) {
              _temporaryBackendSelections.add(saved.id);
            }
            _notify(ConnectionSettingsChange.controller);
          });
          return;
        }
        final keepConfirmation = !pending &&
            (pinBackend ||
                routerToolConfirmed ||
                (prefs.getString('clash_host') == host &&
                    prefs.getString('router_tool') == selectedTool.name &&
                    prefs.getBool('router_tool_confirmed') == true));
        await AppSecureStorage.write('clash_token', token);
        await AppSecureStorage.write('ssh_password', sshPassword);
        if (!await prefs.setInt('ssh_port', sshPort)) {
          throw StateError('Could not save SSH port');
        }
        if (!await prefs.setString('router_tool', selectedTool.name)) {
          throw StateError('Could not save router tool');
        }
        if (!await prefs.setString('proxy_core', core.name)) {
          throw StateError('Could not save proxy core');
        }
        if (!await prefs.setBool('router_tool_confirmed', keepConfirmation) ||
            !await prefs.setBool('router_tool_selection_pending', pending)) {
          throw StateError('Could not save router selection state');
        }
        if (!await prefs.setString('clash_host', host)) {
          throw StateError('Could not save controller address');
        }
        if (temporaryBackendSelection) {
          _temporaryBackendSelections.add('legacy');
        }
        _notify(ConnectionSettingsChange.controller);
      });

  Future<void> saveSshPassword(String password, {int? expectedGeneration}) =>
      _serializeControllerWrite(() async {
        if (expectedGeneration != null) {
          requireDeviceGeneration(expectedGeneration);
        }
        final prefs = await SharedPreferences.getInstance();
        final catalog = _DeviceCatalog.read(prefs);
        if (catalog == null) {
          await AppSecureStorage.write('ssh_password', password);
        } else {
          final device = catalog.active;
          if (device == null) throw StateError('No active device');
          final settings = await device._loadSettings();
          await _storeProfile(prefs, catalog,
              id: device.id,
              name: device.name,
              host: device.host,
              token: settings.token,
              password: password,
              port: device.sshPort,
              tool: device.routerTool,
              core: device.core,
              pending: device.selectionPending,
              confirmed: device.toolConfirmed);
        }
        _notify(ConnectionSettingsChange.sshPassword);
      });

  Future<void> clearConnectionData() => _serializeControllerWrite(() async {
        final prefs = await SharedPreferences.getInstance();
        final catalog = _DeviceCatalog.read(prefs);
        if (catalog != null) {
          await _changeConnection(() async {
            await const _DeviceCatalog([], null).write(prefs);
            activeDevice = null;
            expireTemporaryBackendSelections();
            for (final device in catalog.devices) {
              await _discardCredential(device.credentialsKey);
            }
            _notify(ConnectionSettingsChange.reset);
            profilesChanged.value++;
          });
          return;
        }
        await prefs.remove('clash_host');
        await prefs.remove('ssh_port');
        await prefs.remove('router_tool');
        await prefs.remove('router_tool_selection_pending');
        await prefs.remove('router_tool_confirmed');
        await prefs.remove('proxy_core');
        await AppSecureStorage.deleteAll();
        expireTemporaryBackendSelections();
        lastChange = ConnectionSettingsChange.reset;
        revision++;
        notifyListeners();
      });

  Future<void> _resetAfterSecureStorageFailure(
    SharedPreferences prefs,
  ) async {
    await prefs.remove('clash_host');
    await prefs.remove('ssh_port');
    await prefs.remove('router_tool');
    await prefs.remove('router_tool_selection_pending');
    await prefs.remove('router_tool_confirmed');
    await prefs.remove('proxy_core');
    try {
      await AppSecureStorage.deleteAll();
    } catch (_) {
      // resetOnError recreates the Android storage on the next operation.
    }
    expireTemporaryBackendSelections();
    lastChange = ConnectionSettingsChange.reset;
    revision++;
    notifyListeners();
  }
}
