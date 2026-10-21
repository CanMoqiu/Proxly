import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../l10n/app_locale.dart';
import 'ssh_service.dart';

enum SftpPackageManager { opkg, apk }

class SftpTarget {
  final String host;
  final int port;
  final String username;

  const SftpTarget(this.host, this.port, this.username);

  bool matches(SftpTarget other) =>
      host == other.host && port == other.port && username == other.username;

  String get label => '$username@$host:$port';
}

class SftpSupportIssue implements Exception {
  final SftpTarget target;
  final bool openWrt;
  final bool installed;
  final bool root;
  final SftpPackageManager? manager;

  const SftpSupportIssue({
    required this.target,
    required this.openWrt,
    required this.installed,
    required this.root,
    required this.manager,
  });

  bool get canInstall => openWrt && !installed && root && manager != null;

  String get message => installed
      ? '已检测到 SFTP 组件，但服务不可用，请检查路由器 SSH 的 SFTP 配置。'
      : openWrt
          ? '路由器缺少 SFTP 组件，无法读写 YAML 文件。'
          : 'SFTP 服务不可用，请在路由器上启用 SFTP。';

  String? get installCommand => switch (manager) {
        SftpPackageManager.opkg =>
          'opkg update && opkg install openssh-sftp-server',
        SftpPackageManager.apk => 'apk update && apk add openssh-sftp-server',
        null => null,
      };

  @override
  String toString() => tr(message);
}

/// Uses an authenticated, host-verified connection. A failed handshake alone
/// never proves that a package is missing; the read-only probe must also succeed.
class SftpSupportService {
  final SftpTarget target;
  final Future<void> Function() check;
  final Future<SshCommandResult> Function(String, Duration) run;

  const SftpSupportService({
    required this.target,
    required this.check,
    required this.run,
  });

  factory SftpSupportService.forClient(SSHClient client, SftpTarget target) =>
      SftpSupportService(
        target: target,
        check: () async => (await _handshake(client)).close(),
        run: (command, timeout) => _runBounded(client, command, timeout),
      );

  static Future<SftpClient> _handshake(SSHClient client) async {
    SftpClient? sftp;
    var expired = false;
    try {
      return await (() async {
        final opened = await client.sftp();
        sftp = opened;
        if (expired) {
          opened.close();
          throw TimeoutException('SFTP init');
        }
        await opened.handshake;
        return opened;
      })()
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      expired = true;
      sftp?.close();
      rethrow;
    }
  }

  static Future<SftpClient> open(SSHClient client, SftpTarget target) async {
    try {
      return await _handshake(client);
    } catch (_) {
      final issue =
          await SftpSupportService.forClient(client, target).diagnose();
      if (issue != null) throw issue;
      rethrow;
    }
  }

  Future<SftpSupportIssue?> diagnose() async {
    try {
      final result = await run(probeCommand, const Duration(seconds: 8));
      if (result.exitCode != 0 || result.exitSignal != null) return null;
      final match = RegExp(
        r'^PROXLY_SFTP_V1\|(0|1)\|(0|1)\|(opkg|apk|none)\|(0|1)$',
        multiLine: true,
      ).allMatches(result.stdout.trim()).toList();
      if (match.length != 1) return null;
      final fields = match.single;
      return SftpSupportIssue(
        target: target,
        openWrt: fields[1] == '1',
        root: fields[2] == '1',
        manager: switch (fields[3]) {
          'apk' => SftpPackageManager.apk,
          'opkg' => SftpPackageManager.opkg,
          _ => null,
        },
        installed: fields[4] == '1',
      );
    } catch (_) {
      return null;
    }
  }

  /// Called only after the UI confirms the target and package. Recheck first:
  /// another client may have installed it, or the router may have changed.
  Future<void> install(SftpSupportIssue consent) async {
    if (!consent.canInstall || !target.matches(consent.target)) {
      throw StateError(tr('连接设置已改变，请重新检测 SFTP 后再安装。'));
    }
    try {
      await check();
      return;
    } catch (_) {
      // Only a fresh, complete probe can authorize the package command.
    }
    final issue = await diagnose();
    if (issue == null ||
        !issue.canInstall ||
        issue.manager != consent.manager) {
      throw StateError(tr('SFTP 状态已改变，请重新检测后再操作。'));
    }
    try {
      final result = await run(
        '${issue.installCommand} && printf "\\nPROXLY_SFTP_INSTALLED\\n"',
        const Duration(minutes: 3),
      );
      if (result.exitCode != 0 ||
          result.exitSignal != null ||
          !result.stdout.split('\n').contains('PROXLY_SFTP_INSTALLED')) {
        throw StateError('Package command did not complete');
      }
      await check();
    } catch (_) {
      // A lost connection cannot establish whether the remote install finished.
      // Do not retry mutations automatically or claim that they were rolled back.
      throw StateError(tr('未能确认安装完成。请检查路由器联网、软件源和剩余空间，重新检测 SFTP 后再试。'));
    }
  }

  static const probeCommand = r'''
wrt=0; root=0; pm=none; installed=0
[ ! -r /etc/openwrt_release ] || wrt=1
uid=$(id -u) || exit 1
[ "$uid" != 0 ] || root=1
if command -v apk >/dev/null 2>&1; then pm=apk
elif command -v opkg >/dev/null 2>&1; then pm=opkg
fi
for file in /usr/libexec/sftp-server /usr/lib/openssh/sftp-server /usr/lib/sftp-server; do
  [ ! -x "$file" ] || installed=1
done
if command -v sftp-server >/dev/null 2>&1; then installed=1; fi
if [ "$pm" = apk ]; then
  if apk info -e openssh-sftp-server >/dev/null 2>&1; then installed=1; fi
elif [ "$pm" = opkg ]; then
  status=$(opkg status openssh-sftp-server) || exit 1
  case "$status" in *"Status: install ok installed"*) installed=1;; esac
fi
printf 'PROXLY_SFTP_V1|%s|%s|%s|%s\n' "$wrt" "$root" "$pm" "$installed"
''';

  static Future<SshCommandResult> _runBounded(
      SSHClient client, String command, Duration timeout) async {
    SSHSession? session;
    var expired = false;
    Future<String> collect(Stream<Uint8List> stream) async {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        final remaining = 64 * 1024 - bytes.length;
        if (remaining > 0) {
          bytes.add(
              chunk.length <= remaining ? chunk : chunk.sublist(0, remaining));
        }
      }
      return utf8.decode(bytes.takeBytes(), allowMalformed: true);
    }

    try {
      return await (() async {
        final opened = await client.execute(command);
        session = opened;
        if (expired) {
          opened.close();
          throw TimeoutException('SFTP support command');
        }
        final output = await Future.wait([
          collect(opened.stdout),
          collect(opened.stderr),
          opened.done.then((_) => ''),
        ]);
        return SshCommandResult(
            stdout: output[0],
            stderr: output[1],
            exitCode: opened.exitCode,
            exitSignal: opened.exitSignal?.signalName);
      })()
          .timeout(timeout);
    } finally {
      expired = true;
      session?.close();
    }
  }
}
