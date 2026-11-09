import 'dart:io';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/clash_config_file_service.dart';
import 'package:proxly/services/nikki_quick_settings_adapter.dart';
import 'package:proxly/services/openclash_quick_settings_service.dart';
import 'package:proxly/services/openclash_restart_coordinator.dart';
import 'package:proxly/services/router_tool.dart';

const fixture =
    'available=1\nrevision=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
    'core_only=0\ndns_mode=fake-ip\nmode=rule\nsniffer=0\ndns_respect_rules=1\n'
    'tcp_mode=redirect\nudp_mode=tun\nrouter_proxy=1\n';
OpenClashRestartCoordinator coordinator(Future<void> Function() restart) =>
    OpenClashRestartCoordinator(
        restartCommand: (_) => restart(),
        healthProbe: () async {},
        delay: (_) async {},
        initialWait: Duration.zero,
        pollInterval: Duration.zero,
        requiredHealthyChecks: 1,
        verificationAttempts: 1,
        terminalStateDuration: Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'Nikki shell staging preserves source on failure and replaces only a complete candidate',
      () async {
    final restart = coordinator(() async {});
    addTearDown(restart.dispose);
    final original = await NikkiQuickSettingsAdapter(
            run: (command) async => fixture, restartCoordinator: restart)
        .load();
    final root = await Directory.systemTemp.createTemp('proxly-nikki-test-');
    addTearDown(() => root.delete(recursive: true));
    final config = Directory('${root.path}/config')..createSync();
    final bin = Directory('${root.path}/bin')..createSync();
    final source = File('${config.path}/nikki');
    const baseline = 'config config config\noption core_only 0\n';
    final digest = sha256.convert(utf8.encode(baseline)).toString();
    final uci = File('${bin.path}/uci')..writeAsStringSync(r'''#!/bin/sh
stage=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    -q) shift;;
    -c) stage="$2"; shift 2;;
    -t) shift 2;;
    *) break;;
  esac
done
case "$1" in
  get) echo 0;;
  changes) [ "$PENDING" != 1 ] || echo unrelated_pending_option;;
  set) [ "$FAIL_SAVE" != 1 ] || exit 9; printf '%s\n' "$2" >> "$stage/nikki";;
  commit) exit 0;;
esac
''');
    final hash = File('${bin.path}/sha256sum')
      ..writeAsStringSync('#!/bin/sh\nexec /usr/bin/shasum -a 256 "\$@"\n');
    final init = File('${root.path}/nikki-init')
      ..writeAsStringSync('#!/bin/sh\nexit 0\n');
    for (final file in [uci, hash, init]) {
      await Process.run('chmod', ['700', file.path]);
    }
    var command = NikkiQuickSettingsAdapter.buildApplyCommand(
        original,
        original.copyWith(snifferEnabled: true),
        OpenClashQuickSettingKey.sniffer);
    command = command
        .replaceAll('/etc/config', config.path)
        .replaceAll('/etc/init.d/nikki', init.path)
        .replaceAll(original.backendRevision, digest);
    for (final scenario in ['fail', 'pending', 'stale', 'success']) {
      source.writeAsStringSync(
          scenario == 'stale' ? 'changed by someone else\n' : baseline);
      final before = source.readAsStringSync();
      final result = await Process.run('/bin/sh', [
        '-c',
        command
      ], environment: {
        'PATH': '${bin.path}:/usr/bin:/bin',
        'FAIL_SAVE': scenario == 'fail' ? '1' : '0',
        'PENDING': scenario == 'pending' ? '1' : '0',
      });
      if (scenario == 'success') {
        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(result.stdout, contains('PROXLY_NIKKI_PERSISTED=1'));
        expect(source.readAsStringSync(), contains('nikki.mixin.sniffer=1'));
      } else {
        expect(result.exitCode, isNot(0), reason: scenario);
        expect(result.stdout, isNot(contains('PROXLY_NIKKI_PERSISTED=1')));
        expect(source.readAsStringSync(), before);
      }
      expect(config.listSync().map((entry) => entry.path.split('/').last),
          ['nikki']);
    }
  }, skip: !Platform.isMacOS);

  test(
      'Nikki local and subscription references are isolated from generated runtime',
      () {
    expect(
        ClashConfigFileService.parseActiveConfigOutput(
                "nikki.config.profile='file:mine.yaml'")
            .file
            ?.path,
        '/etc/nikki/profiles/mine.yaml');
    final subscription = ClashConfigFileService.parseActiveConfigOutput(
        'nikki.config.profile=subscription:cfg001\nnikki.subscription.name=Plan\nnikki.subscription.url=https://example.com/sub');
    expect(subscription.subscriptionMode, isTrue);
    expect(subscription.subscription!.generatedPath,
        '/etc/nikki/subscriptions/cfg001.yaml');
    for (final value in [
      'file:../run/config.yaml',
      'file:bad:name.yaml',
      'subscription:../../etc'
    ]) {
      expect(
          ClashConfigFileService.parseActiveConfigOutput(
                  'nikki.config.profile=$value')
              .source,
          ClashActiveConfigSource.unknown);
    }
    expect(
        () => ClashConfigFileService.normalizeConfigFilePath(
            '/etc/nikki/run/config.yaml'),
        throwsArgumentError);
    expect(
        ClashConfigFileService.uploadPathForFileName('local.yaml',
            tool: RouterTool.nikki),
        '/etc/nikki/profiles/local.yaml');
    expect(() => RouterTool.generic.restartCommand, throwsUnsupportedError);
  });
  test('runtime values win and unsupported Nikki features stay disabled',
      () async {
    final restart = coordinator(() async {});
    addTearDown(restart.dispose);
    final service = NikkiQuickSettingsAdapter(
        run: (_) async =>
            '${fixture}runtime=1\nruntime_dns_mode=redir-host\nruntime_mode=global\nruntime_sniffer=true\nruntime_dns_respect_rules=false\n',
        restartCoordinator: restart);
    final settings = await service.load();
    expect(settings.routerTool, RouterTool.nikki);
    expect(settings.baseMode, OpenClashBaseMode.redirHost);
    expect(settings.proxyMode, OpenClashProxyMode.global);
    expect(settings.snifferEnabled, isTrue);
    expect(settings.dnsProxyEnabled, isFalse);
    expect(settings.runVariant, OpenClashRunVariant.mix);
    expect(settings.supports(OpenClashQuickSettingKey.areaBypass), isFalse);
    expect(settings.supports(OpenClashQuickSettingKey.streamUnlock), isFalse);
    final coreOnly = NikkiQuickSettingsAdapter(
        run: (_) async => fixture.replaceFirst('core_only=0', 'core_only=1'),
        restartCoordinator: restart);
    expect((await coreOnly.load()).unsupported,
        containsAll(OpenClashQuickSettingKey.values));
  });
  test('save uses private UCI staging and validates the original revision',
      () async {
    var persisted = false;
    var restarts = 0;
    final restart = coordinator(() async {
      expect(persisted, isTrue);
      restarts++;
    });
    addTearDown(restart.dispose);
    final service = NikkiQuickSettingsAdapter(
        run: (command) async {
          if (command == NikkiQuickSettingsAdapter.readCommand) {
            return persisted
                ? fixture.replaceFirst('sniffer=0', 'sniffer=1')
                : fixture;
          }
          expect(command, contains('check_revision\n'));
          expect(
              command,
              contains(
                  r"""uci -c "$tx" -t "$tx/delta" set nikki.mixin.sniffer='1'"""));
          expect(command, contains(r'[ -z "$(uci -q changes nikki)" ]'));
          expect(command, isNot(contains('ruby')));
          expect(command, isNot(contains('set openclash.')));
          persisted = true;
          return 'PROXLY_NIKKI_PERSISTED=1';
        },
        restartCoordinator: restart);
    final original = await service.load();
    final result = await service.applyChange(
        original: original,
        desired: original.copyWith(snifferEnabled: true),
        key: OpenClashQuickSettingKey.sniffer);
    expect(result.success, isTrue);
    expect(restarts, 1);
  });
  test('unconfirmed persistence is never retried or restarted automatically',
      () async {
    var writes = 0;
    var restarts = 0;
    final restart = coordinator(() async {
      restarts++;
    });
    addTearDown(restart.dispose);
    final service = NikkiQuickSettingsAdapter(
        run: (command) async {
          if (command == NikkiQuickSettingsAdapter.readCommand) return fixture;
          writes++;
          throw StateError('connection lost after write');
        },
        restartCoordinator: restart);
    final original = await service.load();
    final result = await service.applyChange(
        original: original,
        desired: original.copyWith(snifferEnabled: true),
        key: OpenClashQuickSettingKey.sniffer);
    expect(result.success, isFalse);
    expect(result.stateUncertain, isTrue);
    expect(result.canRetry, isFalse);
    expect(restart.canRetry, isFalse);
    await restart.retryLast();
    expect(writes, 1);
    expect(restarts, 0);
  });
}
