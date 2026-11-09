import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_secure_storage.dart';
import 'app_platform.dart';
import 'router_tool.dart';

class ConnectionSettings {
  const ConnectionSettings({
    required this.host,
    required this.token,
    required this.sshPassword,
    this.sshPort = 22,
    this.routerTool = RouterTool.openClash,
    this.core = ProxyCore.unknown,
  });

  final String host;
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

enum ConnectionSettingsChange { controller, routerIdentity, sshPassword, reset }

class ConnectionSettingsStore extends ChangeNotifier {
  ConnectionSettingsStore._();

  static final instance = ConnectionSettingsStore._();

  ConnectionSettingsChange? lastChange;
  int revision = 0;
  Future<void>? _controllerWrite;

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
      _serializeControllerWrite(() async {
        final prefs = await SharedPreferences.getInstance();
        if (revision != expectedRevision ||
            prefs.getString('clash_host') != expectedHost ||
            prefs.getBool('router_tool_selection_pending') != true) {
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
        if (revision != expectedRevision ||
            prefs.getString('clash_host') != expectedHost) {
          return false;
        }
        final preserveChoice = tool == RouterTool.generic &&
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

  Future<RouterTool> loadRouterTool() async {
    final pending = _controllerWrite;
    if (pending != null) await pending;
    final prefs = await SharedPreferences.getInstance();
    return RouterTool.parse(prefs.getString('router_tool'));
  }

  Future<ConnectionSettings> load() => _serializeControllerWrite(_load);

  Future<ConnectionSettings> _load() async {
    final prefs = await SharedPreferences.getInstance();
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
    int sshPort = 22,
    RouterTool routerTool = RouterTool.openClash,
    ProxyCore core = ProxyCore.unknown,
    bool routerSelectionPending = false,
  }) =>
      _serializeControllerWrite(() async {
        if (sshPort < 1 || sshPort > 65535) {
          throw RangeError.range(sshPort, 1, 65535, 'sshPort');
        }
        final prefs = await SharedPreferences.getInstance();
        final keepConfirmation = !routerSelectionPending &&
            prefs.getString('clash_host') == host &&
            prefs.getString('router_tool') == routerTool.name &&
            prefs.getBool('router_tool_confirmed') == true;
        await AppSecureStorage.write('clash_token', token);
        await AppSecureStorage.write('ssh_password', sshPassword);
        if (!await prefs.setInt('ssh_port', sshPort)) {
          throw StateError('Could not save SSH port');
        }
        if (!await prefs.setString('router_tool', routerTool.name)) {
          throw StateError('Could not save router tool');
        }
        if (!await prefs.setString('proxy_core', core.name)) {
          throw StateError('Could not save proxy core');
        }
        if (!await prefs.setBool('router_tool_confirmed', keepConfirmation) ||
            !await prefs.setBool(
                'router_tool_selection_pending', routerSelectionPending)) {
          throw StateError('Could not save router selection state');
        }
        await prefs.setString('clash_host', host);
        lastChange = ConnectionSettingsChange.controller;
        revision++;
        notifyListeners();
      });

  Future<void> saveSshPassword(String password) async {
    await AppSecureStorage.write('ssh_password', password);
    lastChange = ConnectionSettingsChange.sshPassword;
    revision++;
    notifyListeners();
  }

  Future<void> clearConnectionData() => _serializeControllerWrite(() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('clash_host');
        await prefs.remove('ssh_port');
        await prefs.remove('router_tool');
        await prefs.remove('router_tool_selection_pending');
        await prefs.remove('router_tool_confirmed');
        await prefs.remove('proxy_core');
        await AppSecureStorage.deleteAll();
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
    lastChange = ConnectionSettingsChange.reset;
    revision++;
    notifyListeners();
  }
}
