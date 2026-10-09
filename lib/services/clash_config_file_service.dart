import '../l10n/app_locale.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'connection_settings_store.dart';
import 'ssh_service.dart';

class SshPasswordRequiredException implements Exception {
  const SshPasswordRequiredException();

  @override
  String toString() => tr('需要 SSH 密码');
}

class ClashConfigNameConflictException implements Exception {
  const ClashConfigNameConflictException();

  @override
  String toString() => tr('目标文件名已存在');
}

class ClashConfigRenameRollbackException implements Exception {
  const ClashConfigRenameRollbackException();

  @override
  String toString() => tr('重命名失败且无法完整回滚，请检查当前配置文件和 OpenClash 配置引用');
}

class ClashConfigActiveReferenceException implements Exception {
  const ClashConfigActiveReferenceException();

  @override
  String toString() => tr('无法更新 OpenClash 配置引用，文件名已恢复');
}

class ClashConfigFile {
  final String path;

  const ClashConfigFile({required this.path});

  String get name {
    final parts = path.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  String get directory {
    final index = path.lastIndexOf('/');
    return index <= 0 ? '/' : path.substring(0, index);
  }

  String get displayPath {
    const openClashConfig = '/openclash/config/';
    final openClashIndex = path.indexOf(openClashConfig);
    if (openClashIndex >= 0) {
      return '...$openClashConfig${path.substring(openClashIndex + openClashConfig.length)}';
    }

    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length <= 3) return path;
    return '.../${parts.sublist(parts.length - 3).join('/')}';
  }
}

enum ClashActiveConfigSource { localYaml, subscription, unknown }

class ClashSubscriptionInfo {
  final String section;
  final String address;
  final String name;
  final String generatedPath;

  const ClashSubscriptionInfo({
    required this.section,
    required this.address,
    required this.name,
    required this.generatedPath,
  });
}

class ClashActiveConfig {
  final ClashConfigFile? file;
  final ClashActiveConfigSource source;
  final ClashSubscriptionInfo? subscription;

  const ClashActiveConfig({
    required this.file,
    bool subscriptionMode = false,
    ClashActiveConfigSource? source,
    this.subscription,
  }) : source = source ??
            (subscriptionMode
                ? ClashActiveConfigSource.subscription
                : file != null
                    ? ClashActiveConfigSource.localYaml
                    : ClashActiveConfigSource.unknown);

  bool get subscriptionMode => source == ClashActiveConfigSource.subscription;

  bool get usesYaml => file != null;

  String get displayText {
    if (file != null) return file!.name;
    return tr('未使用 YAML 配置');
  }

  String get detailText {
    if (file != null) return file!.displayPath;
    return subscriptionMode
        ? tr('当前更像是订阅链接或远程配置模式')
        : tr('没有从 OpenClash 配置中找到本地 YAML 文件');
  }
}

class ClashConfigSshSettings {
  final String host;
  final int port;
  final String username;
  final String password;

  const ClashConfigSshSettings({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });
}

class ClashConfigFileService {
  static const defaultUploadDirectory = '/etc/openclash/config';
  static const maxConfigBytes = 5 * 1024 * 1024;
  static const _sftpTimeout = Duration(seconds: 20);
  static const _searchRoots = [
    '/etc/openclash/config',
    '/openclash/config',
    '/etc/clash/config',
    '/root/.config/clash/config',
  ];

  static Future<String> routerHost() async {
    final settings = await ConnectionSettingsStore.instance.load();
    return _routerHostFromClashHost(settings.host);
  }

  static Future<String> savedPassword() async {
    return (await ConnectionSettingsStore.instance.load()).sshPassword;
  }

  static Future<void> savePassword(String password) async {
    await ConnectionSettingsStore.instance.saveSshPassword(password);
  }

  static Future<ClashConfigSshSettings> loadSettings({
    String? passwordOverride,
  }) async {
    final host = await routerHost();
    if (host.isEmpty) {
      throw Exception(tr('请先在设置页填写 OpenClash 地址'));
    }

    final password = passwordOverride ?? await savedPassword();
    if (password.isEmpty) {
      throw const SshPasswordRequiredException();
    }

    return ClashConfigSshSettings(
      host: host,
      port: 22,
      username: 'root',
      password: password,
    );
  }

  static Future<List<ClashConfigFile>> listFiles({
    String? password,
  }) async {
    final settings = await loadSettings(passwordOverride: password);
    final output = await SshService.runText(
      settings.host,
      settings.password,
      _listCommand(),
      username: settings.username,
      port: settings.port,
      operationTimeout: const Duration(seconds: 30),
    );
    final paths = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where(isYamlPath)
        .where(isConfigFolderFile)
        .map(normalizeRemotePath)
        .toSet()
        .toList()
      ..sort();
    return paths.map((path) => ClashConfigFile(path: path)).toList();
  }

  static Future<ClashActiveConfig> getActiveConfig({
    String? password,
  }) async {
    final settings = await loadSettings(passwordOverride: password);
    final output = await SshService.runText(
      settings.host,
      settings.password,
      _activeConfigCommand(),
      username: settings.username,
      port: settings.port,
      operationTimeout: const Duration(seconds: 20),
    );

    return parseActiveConfigOutput(output);
  }

  static ClashActiveConfig parseActiveConfigOutput(String output) {
    final values = <String, String>{};
    for (final rawLine in output.split('\n')) {
      final parsed = _parseConfigLine(rawLine);
      if (parsed != null && parsed.value.isNotEmpty) {
        values[parsed.key] = parsed.value;
      }
    }

    ClashConfigFile? yamlFile;
    const activeKeys = [
      'openclash.config.config_path',
      'openclash.config.config_update_path',
      'openclash.config.config_file',
      'openclash.config.config_name',
      'openclash.config.config',
    ];
    for (final key in activeKeys) {
      final value = values[key];
      if (value == null) continue;
      final candidate = _yamlCandidateFromValue(value);
      if (candidate == null) continue;
      try {
        yamlFile = ClashConfigFile(path: normalizeConfigFilePath(candidate));
        break;
      } catch (_) {
        continue;
      }
    }

    if (yamlFile == null) {
      for (final entry in values.entries) {
        if (!_isActiveYamlConfigKey(entry.key)) continue;
        final candidate = _yamlCandidateFromValue(entry.value);
        if (candidate == null) continue;
        try {
          yamlFile = ClashConfigFile(path: normalizeConfigFilePath(candidate));
          break;
        } catch (_) {
          continue;
        }
      }
    }

    if (yamlFile != null) {
      final activeIdentity = _configPathIdentity(yamlFile.path);
      for (final entry in values.entries) {
        if (entry.value != 'config_subscribe') continue;
        final section = entry.key;
        if (values['$section.enabled'] == '0') continue;
        final address = values['$section.address'] ?? '';
        if (!_isHttpUrl(address)) continue;
        final name = values['$section.name'] ?? '';
        final safeName = name.replaceAll('\\', '/').split('/').last;
        final generatedName = safeName.isEmpty
            ? 'config.yaml'
            : isYamlPath(safeName)
                ? safeName
                : '$safeName.yaml';
        final generatedPath = '$defaultUploadDirectory/$generatedName';
        if (_configPathIdentity(generatedPath) != activeIdentity) continue;
        return ClashActiveConfig(
          file: null,
          source: ClashActiveConfigSource.subscription,
          subscription: ClashSubscriptionInfo(
            section: section,
            address: address,
            name: name,
            generatedPath: generatedPath,
          ),
        );
      }
      return ClashActiveConfig(
        file: yamlFile,
        source: ClashActiveConfigSource.localYaml,
      );
    }

    final legacySubscription = values.entries.any(
      (entry) =>
          entry.key.startsWith('openclash.config.') &&
          _isSubscriptionConfigValue(entry.key, entry.value),
    );
    return ClashActiveConfig(
      file: null,
      source: legacySubscription
          ? ClashActiveConfigSource.subscription
          : ClashActiveConfigSource.unknown,
    );
  }

  static Future<void> setActiveConfigFile(
    String path, {
    String? password,
  }) async {
    final safePath = normalizeConfigFilePath(path);
    final settings = await loadSettings(passwordOverride: password);
    await SshService.execute(
      settings.host,
      settings.password,
      _setActiveConfigCommand(safePath),
    );
  }

  static bool isConfigFolderFile(String path) {
    try {
      final normalized = normalizeRemotePath(path).toLowerCase();
      return isYamlPath(normalized) &&
          _searchRoots.any((root) {
            final normalizedRoot = normalizeRemotePath(root).toLowerCase();
            return normalized.startsWith('$normalizedRoot/');
          });
    } catch (_) {
      return false;
    }
  }

  static bool isYamlPath(String value) {
    final lower = value.toLowerCase();
    return lower.endsWith('.yaml') || lower.endsWith('.yml');
  }

  static String normalizeUploadFileName(String fileName) {
    final value = fileName.trim();
    if (value.isEmpty) throw ArgumentError('File name is empty');
    if (value == '.' || value == '..') {
      throw ArgumentError('File name cannot be . or ..');
    }
    if (value.contains('/') ||
        value.contains('\\') ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(value)) {
      throw ArgumentError('File name contains an invalid character');
    }
    if (!isYamlPath(value)) {
      throw ArgumentError('File name must end with .yaml or .yml');
    }
    return value;
  }

  static String uploadPathForFileName(String fileName) {
    final safeName = normalizeUploadFileName(fileName);
    return normalizeConfigFilePath('$defaultUploadDirectory/$safeName');
  }

  static String renamePathForFileName(String sourcePath, String fileName) {
    final safeSource = normalizeConfigFilePath(sourcePath);
    final safeName = normalizeUploadFileName(fileName);
    return normalizeConfigFilePath('${_directoryOf(safeSource)}/$safeName');
  }

  static String? matchActiveConfigPath(
    List<ClashConfigFile> files,
    ClashActiveConfig? activeConfig,
  ) {
    if (activeConfig == null || activeConfig.subscriptionMode) return null;
    final activeFile = activeConfig.file;
    if (activeFile == null) return null;

    for (final file in files) {
      if (file.path == activeFile.path) return file.path;
    }

    final identity = _configPathIdentity(activeFile.path);
    final aliases = files
        .where((file) => _configPathIdentity(file.path) == identity)
        .toList();
    return aliases.length == 1 ? aliases.single.path : null;
  }

  static String normalizeConfigFilePath(String path) {
    final normalized = normalizeRemotePath(path);
    if (!isYamlPath(normalized)) {
      throw ArgumentError('Remote path must end with .yaml or .yml');
    }
    if (!isConfigFolderFile(normalized)) {
      throw ArgumentError(
        'Only YAML files under Clash/OpenClash config directories are allowed',
      );
    }
    return normalized;
  }

  static String normalizeRemotePath(String path) {
    var value = path.trim().replaceAll('\\', '/');
    if (value.isEmpty) throw ArgumentError('Remote path is empty');
    if (value.contains('\u0000')) {
      throw ArgumentError('Remote path contains an invalid character');
    }
    if (!value.startsWith('/')) {
      throw ArgumentError('Remote path must be absolute');
    }

    final segments = <String>[];
    for (final part in value.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (segments.isEmpty) {
          throw ArgumentError('Remote path escapes the root directory');
        }
        segments.removeLast();
        continue;
      }
      segments.add(part);
    }
    return '/${segments.join('/')}';
  }

  static Future<String> readFile(
    String path, {
    String? password,
  }) async {
    final bytes = await readFileBytes(path, password: password);
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Future<Uint8List> readFileBytes(
    String path, {
    String? password,
  }) {
    final safePath = normalizeConfigFilePath(path);
    return _withSftp(password, (sftp) async {
      final stat = await _withTimeout(sftp.stat(safePath), 'SFTP stat');
      final size = stat.size;
      if (size != null && size > maxConfigBytes) {
        throw Exception(
          'File is too large (${(size / 1048576).toStringAsFixed(1)} MB), max 5 MB',
        );
      }

      final file = await _withTimeout(
        sftp.open(safePath, mode: SftpFileOpenMode.read),
        'SFTP open',
      );
      try {
        final bytes = await _withTimeout(file.readBytes(), 'SFTP read');
        if (bytes.length > maxConfigBytes) {
          throw Exception(
            'File is too large (${(bytes.length / 1048576).toStringAsFixed(1)} MB), max 5 MB',
          );
        }
        return bytes;
      } finally {
        await _withTimeout(file.close(), 'SFTP close').catchError((_) {});
      }
    });
  }

  static Future<void> writeTextFile(
    String path,
    String content, {
    String? password,
  }) {
    return writeFileBytes(
      path,
      Uint8List.fromList(utf8.encode(content)),
      password: password,
    );
  }

  static Future<void> writeFileBytes(
    String path,
    Uint8List bytes, {
    String? password,
  }) async {
    final safePath = normalizeConfigFilePath(path);
    if (bytes.length > maxConfigBytes) {
      throw Exception(
        'File is too large (${(bytes.length / 1048576).toStringAsFixed(1)} MB), max 5 MB',
      );
    }

    final settings = await loadSettings(passwordOverride: password);
    await SshService.withClient(
      settings.host,
      settings.password,
      (client) async {
        final directory = _directoryOf(safePath);
        if (directory != '/') {
          await SshService.runCommandOnClient(
            client,
            'mkdir -p ${_shellQuote(directory)}',
          ).timeout(_sftpTimeout);
        }
        final sftp = await _withTimeout(client.sftp(), 'SFTP init');
        final tmpPath =
            '$safePath.proxly_tmp_${DateTime.now().microsecondsSinceEpoch}';
        try {
          final file = await _withTimeout(
            sftp.open(
              tmpPath,
              mode: SftpFileOpenMode.create |
                  SftpFileOpenMode.write |
                  SftpFileOpenMode.truncate,
            ),
            'SFTP open',
          );
          try {
            await _withTimeout(file.writeBytes(bytes), 'SFTP write');
          } finally {
            await _withTimeout(file.close(), 'SFTP close').catchError((_) {});
          }

          try {
            await _withTimeout(sftp.rename(tmpPath, safePath), 'SFTP rename');
          } catch (_) {
            await SshService.runCommandOnClient(
              client,
              'mv -f ${_shellQuote(tmpPath)} ${_shellQuote(safePath)}',
            ).timeout(_sftpTimeout);
          }
        } catch (_) {
          await _withTimeout(sftp.remove(tmpPath), 'SFTP cleanup')
              .catchError((_) {});
          rethrow;
        } finally {
          sftp.close();
        }
      },
      username: settings.username,
      port: settings.port,
    );
  }

  static Future<ClashConfigFile> renameFile(
    String sourcePath,
    String fileName, {
    String? password,
  }) async {
    final safeSource = normalizeConfigFilePath(sourcePath);
    final safeTarget = renamePathForFileName(safeSource, fileName);
    if (safeSource == safeTarget) return ClashConfigFile(path: safeSource);

    final settings = await loadSettings(passwordOverride: password);
    try {
      return await SshService.withClient(
        settings.host,
        settings.password,
        (client) async {
          final sftp = await _withTimeout(client.sftp(), 'SFTP init');
          try {
            final attrs = await _withTimeout(
                sftp.stat(safeSource, followLink: false), 'SFTP stat');
            if (!attrs.isFile) {
              throw FormatException(tr('只能重命名配置目录中的普通 YAML 文件'));
            }
            return await renameWithActiveConfig(
              sourcePath: safeSource,
              fileName: fileName,
              resolvePath: (path) =>
                  _withTimeout(sftp.absolute(path), 'SFTP realpath'),
              loadActiveConfig: () async {
                final result = await _withTimeout(
                    SshService.runCommandOnClient(
                        client, _activeConfigCommand()),
                    'Read active configuration');
                return parseActiveConfigOutput(result.stdout);
              },
              rename: (source, target, updateActiveReference) async {
                await _withTimeout(
                    SshService.runCommandOnClient(
                        client,
                        _renameConfigCommand(source, target,
                            updateActiveReference: updateActiveReference)),
                    'Rename configuration');
              },
            );
          } finally {
            sftp.close();
          }
        },
        username: settings.username,
        port: settings.port,
        operationTimeout: const Duration(seconds: 30),
      );
    } on SshCommandException catch (error) {
      final detail = '${error.stdout}\n${error.stderr}';
      if (detail.contains('PROXLY_TARGET_EXISTS')) {
        throw const ClashConfigNameConflictException();
      }
      if (detail.contains('PROXLY_ROLLBACK_FAILED')) {
        throw const ClashConfigRenameRollbackException();
      }
      if (detail.contains('PROXLY_ACTIVE_UPDATE_FAILED')) {
        throw const ClashConfigActiveReferenceException();
      }
      rethrow;
    }
  }

  /// Mutation checks use remote identities on the same SSH connection, rather
  /// than the display-only path aliases or a filename match from the picker.
  static Future<ClashConfigFile> renameWithActiveConfig({
    required String sourcePath,
    required String fileName,
    required Future<String> Function(String) resolvePath,
    required Future<ClashActiveConfig> Function() loadActiveConfig,
    required Future<void> Function(String, String, bool) rename,
  }) async {
    final safeSource = normalizeConfigFilePath(sourcePath);
    final safeName = normalizeUploadFileName(fileName);
    final source = normalizeConfigFilePath(await resolvePath(safeSource));
    final target = renamePathForFileName(source, safeName);
    if (source == target) return ClashConfigFile(path: source);
    final active = await loadActiveConfig();
    final activePath = active.file?.path ?? active.subscription?.generatedPath;
    if (activePath == null) {
      throw FormatException(tr('无法确认当前运行配置，请刷新连接后重试重命名'));
    }
    final activeIdentity = normalizeConfigFilePath(
        await resolvePath(normalizeConfigFilePath(activePath)));
    final isActive = source == activeIdentity;
    if (isActive && active.subscriptionMode) {
      throw FormatException(tr('不能重命名当前运行的订阅配置，请先切换到其他配置'));
    }
    await rename(source, target, isActive);
    return ClashConfigFile(path: target);
  }

  static Future<void> deleteFile(String path, {String? password}) async {
    final safePath = normalizeConfigFilePath(path);
    final settings = await loadSettings(passwordOverride: password);
    await SshService.withClient(settings.host, settings.password,
        (client) async {
      final sftp = await _withTimeout(client.sftp(), 'SFTP init');
      try {
        final sourceAttrs = await _withTimeout(
            sftp.stat(safePath, followLink: false), 'SFTP stat');
        if (!sourceAttrs.isFile) {
          throw FormatException(tr('只能删除配置目录中的普通 YAML 文件'));
        }
        await deleteInactiveConfigFile(
          path: safePath,
          loadActiveConfig: () async {
            final result = await _withTimeout(
                SshService.runCommandOnClient(client, _activeConfigCommand()),
                'Read active configuration');
            return parseActiveConfigOutput(result.stdout);
          },
          resolvePath: (path) =>
              _withTimeout(sftp.absolute(path), 'SFTP realpath'),
          removeFile: (path) async {
            final attrs = await _withTimeout(
                sftp.stat(path, followLink: false), 'SFTP stat');
            if (!attrs.isFile) {
              throw FormatException(tr('只能删除配置目录中的普通 YAML 文件'));
            }
            await _withTimeout(sftp.remove(path), 'SFTP remove');
          },
        );
      } finally {
        sftp.close();
      }
    }, username: settings.username, port: settings.port);
  }

  /// Resolves both identities before deleting one inactive YAML. Callers supply
  /// operations bound to the same remote connection; lookup failures fail closed.
  static Future<void> deleteInactiveConfigFile({
    required String path,
    required Future<ClashActiveConfig> Function() loadActiveConfig,
    required Future<String> Function(String) resolvePath,
    required Future<void> Function(String) removeFile,
  }) async {
    final safePath = normalizeConfigFilePath(path);
    final resolvedPath = normalizeConfigFilePath(await resolvePath(safePath));
    final active = await loadActiveConfig();
    final activePath = active.file?.path ?? active.subscription?.generatedPath;
    if (activePath == null) {
      throw FormatException(tr('无法确认当前运行配置，请刷新连接后重试删除'));
    }
    final safeActivePath = normalizeConfigFilePath(activePath);
    // Resolve directory aliases too, so an alternate spelling cannot bypass
    // protection of the active local or subscription-generated configuration.
    final resolvedActivePath =
        normalizeConfigFilePath(await resolvePath(safeActivePath));
    if (resolvedPath == resolvedActivePath) {
      throw FormatException(tr('不能删除当前运行配置，请先切换到其他配置'));
    }
    await removeFile(resolvedPath);
  }

  static String _directoryOf(String path) {
    final index = path.lastIndexOf('/');
    return index <= 0 ? '/' : path.substring(0, index);
  }

  static Future<T> _withSftp<T>(
    String? password,
    Future<T> Function(SftpClient sftp) action,
  ) async {
    final settings = await loadSettings(passwordOverride: password);
    return SshService.withClient(
      settings.host,
      settings.password,
      (client) async {
        final sftp = await _withTimeout(client.sftp(), 'SFTP init');
        try {
          return await action(sftp);
        } finally {
          sftp.close();
        }
      },
      username: settings.username,
      port: settings.port,
    );
  }

  static Future<void> restartOpenClash({String? password}) async {
    final settings = await loadSettings(passwordOverride: password);
    await SshService.execute(
      settings.host,
      settings.password,
      '/etc/init.d/openclash restart',
    );
  }

  static String _listCommand() {
    final roots = _searchRoots.map(_shellQuote).join(' ');
    return "for d in $roots; do [ -d \"\$d\" ] && find \"\$d\" -type f \\( -iname '*.yaml' -o -iname '*.yml' \\) -print; done 2>/dev/null | sort -u";
  }

  static String _activeConfigCommand() {
    return r'''
if command -v uci >/dev/null 2>&1; then
  for opt in config_path config_update_path config_file config_name config config_url config_subscribe_url subscribe_url subscription_url; do
    value="$(uci -q get openclash.config.$opt 2>/dev/null || true)"
    [ -n "$value" ] && printf '%s=%s\n' "openclash.config.$opt" "$value"
  done
  uci -q show openclash 2>/dev/null
fi
if [ -f /etc/config/openclash ]; then
  sed -n "s/^[[:space:]]*option[[:space:]][[:space:]]*\([^[:space:]][^[:space:]]*\)[[:space:]][[:space:]]*['\"]\{0,1\}\([^'\"]*\)['\"]\{0,1\}$/openclash.file.\1=\2/p" /etc/config/openclash
fi
''';
  }

  static String _setActiveConfigCommand(String safePath) {
    final quotedPath = _shellQuote(safePath);
    return '''
set -e
[ -f $quotedPath ]
uci set openclash.config.config_path=$quotedPath
if uci -q get openclash.config.config_update_path >/dev/null 2>&1; then
  uci set openclash.config.config_update_path=$quotedPath
fi
for opt in config config_url config_subscribe_url subscribe_url subscription_url; do
  value="\$(uci -q get openclash.config.\$opt 2>/dev/null || true)"
  case "\$value" in
    http://*|https://*) uci -q delete openclash.config.\$opt || true ;;
  esac
done
for opt in config_update config_auto_update config_subscribe_auto_update subscribe_auto_update; do
  if uci -q get openclash.config.\$opt >/dev/null 2>&1; then
    uci set openclash.config.\$opt='0'
  fi
done
uci commit openclash
''';
  }

  static String _renameConfigCommand(
    String sourcePath,
    String targetPath, {
    required bool updateActiveReference,
  }) {
    final source = _shellQuote(sourcePath);
    final target = _shellQuote(targetPath);
    final sourceName = _shellQuote(ClashConfigFile(path: sourcePath).name);
    final targetName = _shellQuote(ClashConfigFile(path: targetPath).name);
    final activeUpdate = updateActiveReference
        ? '''
update_reference() {
  uci set openclash.config.config_path=\$target_path || return 1
  for opt in config_update_path config_file config_name config; do
    current="\$(uci -q get openclash.config.\$opt 2>/dev/null || true)"
    if [ "\$current" = "\$source_path" ]; then
      uci set "openclash.config.\$opt=\$target_path" || return 1
    elif [ "\$current" = "\$source_name" ]; then
      uci set "openclash.config.\$opt=\$target_name" || return 1
    fi
  done
  uci commit openclash
}

restore_reference() {
  uci set openclash.config.config_path=\$source_path || return 1
  for opt in config_update_path config_file config_name config; do
    current="\$(uci -q get openclash.config.\$opt 2>/dev/null || true)"
    if [ "\$current" = "\$target_path" ]; then
      uci set "openclash.config.\$opt=\$source_path" || return 1
    elif [ "\$current" = "\$target_name" ]; then
      uci set "openclash.config.\$opt=\$source_name" || return 1
    fi
  done
  uci commit openclash
}

if ! update_reference; then
  if mv -- "\$target_path" "\$source_path" && restore_reference; then
    printf '%s\n' 'PROXLY_ACTIVE_UPDATE_FAILED' >&2
    exit 43
  fi
  printf '%s\n' 'PROXLY_ROLLBACK_FAILED' >&2
  exit 44
fi
'''
        : '';

    return '''
set -e
source_path=$source
target_path=$target
source_name=$sourceName
target_name=$targetName
[ -f "\$source_path" ] || { printf '%s\n' 'PROXLY_SOURCE_MISSING' >&2; exit 41; }
[ ! -e "\$target_path" ] || { printf '%s\n' 'PROXLY_TARGET_EXISTS' >&2; exit 42; }
mv -- "\$source_path" "\$target_path"
$activeUpdate
''';
  }

  static ({String key, String value})? _parseConfigLine(String raw) {
    final line = raw.trim();
    if (line.isEmpty) return null;
    final equals = line.indexOf('=');
    if (equals < 0) {
      return (key: '', value: _cleanConfigValue(line));
    }
    return (
      key: line.substring(0, equals).trim(),
      value: _cleanConfigValue(line.substring(equals + 1)),
    );
  }

  static bool _isActiveYamlConfigKey(String key) {
    if (key.isEmpty) return true;
    final option = key.split('.').last.toLowerCase();
    return option == 'config_path' ||
        option == 'config_update_path' ||
        option == 'config_file' ||
        option == 'config_name' ||
        option == 'config';
  }

  static bool _isSubscriptionConfigValue(String key, String value) {
    if (!_isHttpUrl(value)) return false;
    if (key.isEmpty) return true;
    final option = key.split('.').last.toLowerCase();
    return option == 'config' ||
        option == 'config_url' ||
        option.contains('subscribe') ||
        option.contains('subscription') ||
        option.contains('sub_url') ||
        (option.contains('config') && option.contains('url'));
  }

  static bool _isHttpUrl(String value) =>
      value.startsWith('http://') || value.startsWith('https://');

  static String _configPathIdentity(String path) {
    final normalized = normalizeRemotePath(path);
    for (final root in const ['/etc/openclash/config/', '/openclash/config/']) {
      if (normalized.startsWith(root)) {
        return 'openclash:${normalized.substring(root.length)}';
      }
    }
    return normalized;
  }

  static String _cleanConfigValue(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    if ((value.startsWith("'") && value.endsWith("'")) ||
        (value.startsWith('"') && value.endsWith('"'))) {
      value = value.substring(1, value.length - 1).trim();
    }
    return value;
  }

  static String? _yamlCandidateFromValue(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (!isYamlPath(normalized)) {
      final match = RegExp(
        r'''((?:/etc)?/openclash/config/[^\s'"]+\.ya?ml)''',
        caseSensitive: false,
      ).firstMatch(normalized);
      return match?.group(1);
    }
    if (normalized.startsWith('/')) return normalized;
    return '$defaultUploadDirectory/$normalized';
  }

  static String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  static Future<T> _withTimeout<T>(Future<T> future, String action) {
    return future.timeout(
      _sftpTimeout,
      onTimeout: () => throw TimeoutException('$action timed out'),
    );
  }

  static String _routerHostFromClashHost(String raw) {
    var host = raw.trim();
    if (host.isEmpty) return '';
    host = host.replaceFirst(RegExp(r'^https?://'), '');
    host = host.split('/').first;
    if (host.startsWith('[')) {
      final end = host.indexOf(']');
      if (end > 0) return host.substring(1, end);
    }
    final portIndex = host.lastIndexOf(':');
    if (portIndex > 0 && host.indexOf(':') == portIndex) {
      return host.substring(0, portIndex);
    }
    return host;
  }
}
