import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/sftp_support_service.dart';
import 'package:proxly/services/ssh_service.dart';

const target = SftpTarget('192.168.1.1', 22, 'root');
const consent = SftpSupportIssue(
    target: target,
    openWrt: true,
    installed: false,
    root: true,
    manager: SftpPackageManager.opkg);

SshCommandResult result(String stdout, {int? exitCode = 0}) => SshCommandResult(
    stdout: stdout, stderr: '', exitCode: exitCode, exitSignal: null);

void main() {
  for (final pm in SftpPackageManager.values) {
    test('detects missing SFTP and installs with ${pm.name} only after consent',
        () async {
      var ready = false;
      final commands = <String>[];
      final service = SftpSupportService(
          target: target,
          check: () async {
            if (!ready) throw StateError('No subsystem');
          },
          run: (command, timeout) async {
            commands.add(command);
            if (command == SftpSupportService.probeCommand) {
              return result('PROXLY_SFTP_V1|1|1|${pm.name}|0\n');
            }
            ready = true;
            return result('\nPROXLY_SFTP_INSTALLED\n');
          });
      final issue = (await service.diagnose())!;
      expect(issue.canInstall, isTrue);
      expect(commands, [SftpSupportService.probeCommand]);
      await service.install(issue);
      expect(commands.length, 3);
      expect(
          commands.last,
          startsWith(pm == SftpPackageManager.opkg
              ? 'opkg update && opkg install openssh-sftp-server'
              : 'apk update && apk add openssh-sftp-server'));
      expect(ready, isTrue);
    });
  }

  for (final output in [
    'PROXLY_SFTP_V1|1|1|opkg|1',
    'PROXLY_SFTP_V1|1|0|opkg|0',
    'PROXLY_SFTP_V1|0|1|opkg|0',
    'PROXLY_SFTP_V1|1|1|none|0'
  ]) {
    test('does not offer install for $output', () async {
      final service = SftpSupportService(
          target: target,
          check: () async => throw StateError('unavailable'),
          run: (_, __) async => result(output));
      final issue = (await service.diagnose())!;
      expect(issue.canInstall, isFalse);
      await expectLater(service.install(issue), throwsStateError);
    });
  }

  test('unknown, failed and incomplete probes do not claim missing SFTP',
      () async {
    for (final output in [
      result(''),
      result('PROXLY_SFTP_V1|1|1|opkg|0', exitCode: null),
      result('PROXLY_SFTP_V1|1|1|opkg|0', exitCode: 1),
      result('PROXLY_SFTP_V1|1|1|opkg|0\nPROXLY_SFTP_V1|1|1|apk|0')
    ]) {
      final service = SftpSupportService(
          target: target, check: () async {}, run: (_, __) async => output);
      expect(await service.diagnose(), isNull);
    }
    final disconnected = SftpSupportService(
        target: target,
        check: () async {},
        run: (_, __) async => throw TimeoutException('Disconnected'));
    expect(await disconnected.diagnose(), isNull);
  });

  test('working SFTP skips installation and a changed target is refused',
      () async {
    var commands = 0;
    final service = SftpSupportService(
        target: target,
        check: () async {},
        run: (_, __) async {
          commands++;
          return result('');
        });
    await service.install(consent);
    expect(commands, 0);
    final other = SftpSupportService(
        target: const SftpTarget('192.168.1.2', 22, 'root'),
        check: () async {},
        run: service.run);
    await expectLater(other.install(consent), throwsStateError);
    expect(commands, 0);
  });

  test('changed package manager refuses the stale install confirmation',
      () async {
    var commands = 0;
    final service = SftpSupportService(
        target: target,
        check: () async => throw StateError('missing'),
        run: (_, __) async {
          commands++;
          return result('PROXLY_SFTP_V1|1|1|apk|0');
        });
    await expectLater(service.install(consent), throwsStateError);
    expect(commands, 1);
  });

  test(
      'success requires an exit status, completion marker and working handshake',
      () async {
    for (final output in [
      result('PROXLY_SFTP_INSTALLED\n', exitCode: null),
      result('PROXLY_SFTP_INSTALLED\n', exitCode: 1),
      result(''),
      result('PROXLY_SFTP_INSTALLED\n')
    ]) {
      var mutations = 0;
      final service = SftpSupportService(
          target: target,
          check: () async => throw StateError('still unavailable'),
          run: (command, _) async {
            if (command == SftpSupportService.probeCommand) {
              return result('PROXLY_SFTP_V1|1|1|opkg|0');
            }
            mutations++;
            return output;
          });
      await expectLater(service.install(consent), throwsStateError);
      expect(mutations, 1);
    }
  });
}
