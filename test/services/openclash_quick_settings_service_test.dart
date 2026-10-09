import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxly/services/clash_service.dart';
import 'package:proxly/services/connection_settings_store.dart';
import 'package:proxly/services/openclash_quick_settings_service.dart';
import 'package:proxly/services/openclash_restart_coordinator.dart';
import 'package:proxly/services/ssh_service.dart';

void main() {
  const original = OpenClashQuickSettings(
    baseMode: OpenClashBaseMode.fakeIp,
    runVariant: OpenClashRunVariant.compatibility,
    proxyMode: OpenClashProxyMode.rule,
    areaBypass: OpenClashAreaBypass.disabled,
    snifferEnabled: false,
    dnsProxyEnabled: false,
    streamUnlockEnabled: false,
    routerSelfProxyEnabled: true,
    streamUnlockSupported: true,
    rawRunMode: 'fake-ip',
  );

  for (final scenario in [
    'timeout',
    'socket',
    'incomplete',
    'busy',
    'unreachable'
  ]) {
    test('reconciles uncertain remote changes: $scenario', () async {
      final commands = <String>[];
      final requests = <http.Request>[];
      var current = original;
      final service = OpenClashQuickSettingsService(
          clashService: ClashService.forTesting(
              config: const ClashConfig(host: '192.168.1.1:9090', token: ''),
              client: MockClient((request) async {
                requests.add(request);
                return http.Response('{"mode":"rule"}', 200);
              })),
          delay: (_) async {},
          transactionIdFactory: () => 'uncertain-$scenario',
          commandRunner: (command) async {
            commands.add(command);
            if (_isApplyCommand(command)) {
              current = original.copyWith(snifferEnabled: true);
              expect(command, contains(r'"$$" > "$tx.owner"'));
              expect(command, contains(r'> "$tx.ready"'));
              if (scenario == 'incomplete') return '';
              if (scenario == 'socket') {
                throw const SocketException('lost');
              }
              throw TimeoutException('SSH operation timed out');
            }
            if (_isRollbackCommand(command)) {
              expect(command.indexOf('kill -0'),
                  lessThan(command.indexOf('uci import')));
              expect(command.indexOf(r'[ ! -f "$tx.ready" ]'),
                  lessThan(command.indexOf('uci import')));
              if (scenario == 'busy') return 'PROXLY_ROLLBACK=busy\n';
              if (scenario == 'unreachable') {
                throw const SocketException('offline');
              }
              current = original;
              return 'PROXLY_RUNTIME_PATH=/etc/openclash/config.yaml\nPROXLY_ROLLBACK=success\n';
            }
            if (_isLoadCommand(command)) return _settingsOutput(current);
            return '';
          });
      final result = await service.applyChange(
          original: original,
          desired: original.copyWith(snifferEnabled: true),
          key: OpenClashQuickSettingKey.sniffer);
      final uncertain = ['busy', 'unreachable'].contains(scenario);
      expect(result.success, isFalse);
      expect(result.rollbackAttempted, isTrue);
      expect(result.rollbackSucceeded, !uncertain);
      expect(result.stateUncertain, uncertain);
      expect(commands.where(_isRollbackCommand), hasLength(1));
      expect(requests.where((request) => request.method == 'PUT'),
          hasLength(uncertain ? 0 : 1));
      expect(current.snifferEnabled, uncertain);
    });
  }

  test('remote recovery refuses a live writer and preserves failed backups',
      () async {
    final shell = Platform.environment['PROXLY_TEST_SHELL'] ?? 'sh';
    late String rollback;
    final service = OpenClashQuickSettingsService(
        clashService: _clashService(() => original.proxyMode),
        transactionIdFactory: () => 'shell-recovery',
        commandRunner: (command) async {
          if (_isApplyCommand(command)) throw TimeoutException('lost reply');
          if (_isRollbackCommand(command)) {
            rollback = command.replaceFirst(
                "tx='/tmp/proxly_quick_shell-recovery/state'",
                r'tx="$1/transaction/state"');
            return 'PROXLY_ROLLBACK=busy\n';
          }
          if (_isLoadCommand(command)) return _settingsOutput(original);
          return '';
        });
    await service.applyChange(
        original: original,
        desired: original.copyWith(proxyMode: OpenClashProxyMode.global),
        key: OpenClashQuickSettingKey.proxyMode);
    for (final scenario in ['busy', 'partial', 'stopped', 'restore-failed']) {
      final root =
          await Directory.systemTemp.createTemp('proxly-recovery-test-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final result = await Process.run(shell, [
        '-c',
        r'''
set -eu
fixture="$1"
scenario="$2"
mkdir "$fixture/transaction"
printf 'backup\n' > "$fixture/transaction/state.uci"
printf '42\n' > "$fixture/transaction/state.pid"
if [ "$scenario" = busy ]; then
  printf '%s\n' "$$" > "$fixture/transaction/state.owner"
else
  printf '2147483647\n' > "$fixture/transaction/state.owner"
fi
if [ "$scenario" != partial ]; then
  printf 'ready\n' > "$fixture/transaction/state.ready"
fi
uci() {
  printf 'mutation\n' >> "$fixture/mutations"
  [ "$scenario" != restore-failed ]
}
pidof() { printf '42\n'; }
''' +
            rollback,
        'sh',
        root.path.replaceAll('\\', '/'),
        scenario
      ]);
      final mutated = await File('${root.path}/mutations').exists();
      expect(mutated, ['stopped', 'restore-failed'].contains(scenario),
          reason: '${result.stdout}\n${result.stderr}');
      if (scenario == 'stopped') {
        expect(result.exitCode, 0);
        expect(result.stdout, contains('PROXLY_ROLLBACK=success'));
        expect(
            await File('${root.path}/transaction/state.uci').exists(), isFalse);
      } else {
        expect(
            await File('${root.path}/transaction/state.uci').exists(), isTrue);
        expect(
            '${result.stdout}${result.stderr}',
            contains(
                'PROXLY_ROLLBACK=${scenario == 'restore-failed' ? 'failed' : scenario == 'partial' ? 'unconfirmed' : 'busy'}'));
      }
    }
  },
      skip: Platform.isWindows &&
              !Platform.environment.containsKey('PROXLY_TEST_SHELL')
          ? 'POSIX shell test runs in CI or with PROXLY_TEST_SHELL'
          : false);

  test('loads persisted values and prefers live runtime values', () async {
    final service = OpenClashQuickSettingsService(
      clashService: _clashService(() => OpenClashProxyMode.global),
      commandRunner: (_) async => '''
en_mode=fake-ip-tun
proxy_mode=rule
china_ip_route=2
enable_meta_sniffer=0
enable_respect_rules=0
stream_auto_select=1
router_self_proxy=1
stream_unlock_supported=1
runtime_config_available=1
runtime_sniffer=1
runtime_dns_proxy=1
''',
    );

    final settings = await service.load();

    expect(settings.runVariant, OpenClashRunVariant.tun);
    expect(settings.proxyMode, OpenClashProxyMode.global);
    expect(settings.areaBypass, OpenClashAreaBypass.overseas);
    expect(settings.snifferEnabled, isTrue);
    expect(settings.dnsProxyEnabled, isTrue);
    expect(settings.streamUnlockEnabled, isTrue);
  });

  test('keeps unknown run modes visible but not selectable', () async {
    final service = OpenClashQuickSettingsService(
      clashService: _clashService(() => OpenClashProxyMode.direct),
      commandRunner: (_) async => 'en_mode=smart\nproxy_mode=direct\n',
    );

    final settings = await service.load();

    expect(settings.baseMode, OpenClashBaseMode.unknown);
    expect(settings.runVariant, isNull);
    expect(settings.rawRunMode, 'smart');
  });

  test('treats a UCI and runtime TUN mismatch as unapplied', () async {
    final service = OpenClashQuickSettingsService(
      clashService: _clashService(() => OpenClashProxyMode.rule),
      commandRunner: (_) async => '''
en_mode=fake-ip-tun
proxy_mode=rule
runtime_config_available=1
runtime_tun_enabled=0
''',
    );

    final settings = await service.load();

    expect(settings.baseMode, OpenClashBaseMode.fakeIp);
    expect(settings.runVariant, isNull);
  });

  test('resolves the effective runtime path from process then OpenClash UCI',
      () async {
    late String readCommand;
    final service = OpenClashQuickSettingsService(
      clashService: _clashService(() => original.proxyMode),
      commandRunner: (command) async {
        readCommand = command;
        return _settingsOutput(original);
      },
    );

    await service.load();

    expect(readCommand, contains(r'/proc/$clash_pid/cmdline'));
    expect(readCommand, contains(r'previous == "-f"'));
    expect(readCommand, contains('openclash.@overwrite[0].\$option'));
    expect(readCommand, contains('openclash.config.\$option'));
    expect(readCommand, contains('effective_uci_get config_path'));
    expect(readCommand, contains('/etc/openclash/'));
    expect(readCommand, contains('validate_runtime_path'));
  });

  final cases = <({
    String name,
    OpenClashQuickSettingKey key,
    OpenClashQuickSettings desired,
    List<String> fragments,
  })>[
    (
      name: 'proxy mode',
      key: OpenClashQuickSettingKey.proxyMode,
      desired: original.copyWith(proxyMode: OpenClashProxyMode.global),
      fragments: [
        "proxy_mode='global'",
      ],
    ),
    (
      name: 'area bypass',
      key: OpenClashQuickSettingKey.areaBypass,
      desired: original.copyWith(
        areaBypass: OpenClashAreaBypass.overseas,
      ),
      fragments: [
        "china_ip_route='2'",
        "china_ip6_route='2'",
        '/etc/init.d/openclash reload revert',
        '/etc/init.d/openclash reload restore',
        'fw4 reload',
        '/etc/init.d/firewall reload',
      ],
    ),
    (
      name: 'domain sniffer',
      key: OpenClashQuickSettingKey.sniffer,
      desired: original.copyWith(snifferEnabled: true),
      fragments: [
        'ruby -ryaml -rYAML -I /usr/share/openclash',
        'openclash_custom_sniffer.yaml',
        '"parse-pure-ip" => true',
        'PROXLY_RUNTIME_PATH=%s',
      ],
    ),
    (
      name: 'DNS proxy',
      key: OpenClashQuickSettingKey.dnsProxy,
      desired: original.copyWith(dnsProxyEnabled: true),
      fragments: [
        'ruby -ryaml -rYAML -I /usr/share/openclash',
        'config["dns"]["respect-rules"] = enabled',
        'proxy-server-nameserver',
        '114.114.114.114',
        'PROXLY_RUNTIME_PATH=%s',
      ],
    ),
    (
      name: 'stream unlock',
      key: OpenClashQuickSettingKey.streamUnlock,
      desired: original.copyWith(streamUnlockEnabled: true),
      fragments: [
        "stream_auto_select='1'",
        'Netflix|奈飞',
        'Disney|迪士尼',
      ],
    ),
  ];

  for (final testCase in cases) {
    test('${testCase.name} applies immediately without restarting the core',
        () async {
      var current = original;
      final commands = <String>[];
      final service = OpenClashQuickSettingsService(
        clashService: _clashService(() => current.proxyMode),
        transactionIdFactory: () => '123',
        commandRunner: (command) async {
          commands.add(command);
          if (_isApplyCommand(command)) {
            if (!_isRuntimeKey(testCase.key)) {
              current = testCase.desired;
            }
            return _applyReadyOutput(testCase.key);
          }
          if (_isRuntimePersistCommand(command)) {
            current = testCase.desired;
            return 'PROXLY_PERSISTED=1\n';
          }
          if (_isLoadCommand(command)) return _settingsOutput(current);
          if (_isPidCommand(command)) return 'PROXLY_PID=42\n';
          return '';
        },
        delay: (_) async {},
      );

      final result = await service.applyChange(
        original: original,
        desired: testCase.desired,
        key: testCase.key,
      );

      expect(result.success, isTrue);
      final applyCommand = commands.firstWhere(_isApplyCommand);
      for (final fragment in testCase.fragments) {
        expect(applyCommand, contains(fragment));
      }
      expect(
        applyCommand,
        isNot(contains('/etc/init.d/openclash restart')),
      );
      expect(applyCommand, isNot(contains('api_request')));
      expect(applyCommand, isNot(contains('reload manual')));
      if (testCase.key == OpenClashQuickSettingKey.areaBypass) {
        expect(applyCommand, contains("uses_firewall='1'"));
        final revertIndex = applyCommand.indexOf('reload revert');
        final restoreIndex = applyCommand.indexOf('reload restore');
        expect(revertIndex, greaterThanOrEqualTo(0));
        expect(restoreIndex, greaterThan(revertIndex));
      }
      if (testCase.key == OpenClashQuickSettingKey.sniffer) {
        final persist = commands.firstWhere(_isRuntimePersistCommand);
        expect(persist, contains("enable_meta_sniffer='1'"));
        expect(persist, contains("enable_meta_sniffer_pure_ip='1'"));
      }
      if (testCase.key == OpenClashQuickSettingKey.dnsProxy) {
        final persist = commands.firstWhere(_isRuntimePersistCommand);
        expect(persist, contains("enable_respect_rules='1'"));
      }
      expect(applyCommand, contains('PROXLY_PID_BEFORE'));
      expect(commands.any(_isPidCommand), isTrue);
    });
  }

  test('proxy mode uses the configured app Clash API before SSH persistence',
      () async {
    var current = original;
    final desired = original.copyWith(proxyMode: OpenClashProxyMode.global);
    final requests = <http.Request>[];
    final commands = <String>[];
    final clashService = ClashService.forTesting(
      config: const ClashConfig(host: '192.168.1.1:9090', token: 'secret'),
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'PATCH') {
          if (request.body.contains('"global"')) current = desired;
          if (request.body.contains('"rule"')) current = original;
          return http.Response('{}', 200);
        }
        return http.Response('{"mode":"${current.proxyMode.name}"}', 200);
      }),
    );
    final service = OpenClashQuickSettingsService(
      clashService: clashService,
      transactionIdFactory: () => 'proxy-api',
      commandRunner: (command) async {
        commands.add(command);
        if (_isApplyCommand(command)) {
          current = desired;
          return _applyReadyOutput(OpenClashQuickSettingKey.proxyMode);
        }
        if (_isLoadCommand(command)) return _settingsOutput(current);
        if (_isPidCommand(command)) return 'PROXLY_PID=42\n';
        return '';
      },
      delay: (_) async {},
    );

    final result = await service.applyChange(
      original: original,
      desired: desired,
      key: OpenClashQuickSettingKey.proxyMode,
    );

    expect(result.success, isTrue);
    final modeRequests = requests
        .where((request) =>
            request.method == 'PATCH' &&
            request.url.path == '/configs' &&
            request.url.query.isEmpty)
        .toList();
    expect(modeRequests, hasLength(1));
    expect(modeRequests.single.body, contains('"mode":"global"'));
    final applyCommand = commands.firstWhere(_isApplyCommand);
    expect(applyCommand, contains("proxy_mode='global'"));
    expect(applyCommand, isNot(contains('api_request')));
  });

  test('runtime quick settings reload through the configured app Clash API',
      () async {
    var current = original;
    final desired = original.copyWith(snifferEnabled: true);
    final requests = <http.Request>[];
    final commands = <String>[];
    final clashService = ClashService.forTesting(
      config: const ClashConfig(host: '192.168.1.1:9090', token: 'secret'),
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{"mode":"${current.proxyMode.name}"}', 200);
      }),
    );
    final service = OpenClashQuickSettingsService(
      clashService: clashService,
      transactionIdFactory: () => 'runtime-api',
      commandRunner: (command) async {
        commands.add(command);
        if (_isApplyCommand(command)) {
          return _applyReadyOutput(OpenClashQuickSettingKey.sniffer);
        }
        if (_isRuntimePersistCommand(command)) {
          current = desired;
          return 'PROXLY_PERSISTED=1\n';
        }
        if (_isLoadCommand(command)) return _settingsOutput(current);
        if (_isPidCommand(command)) return 'PROXLY_PID=42\n';
        return '';
      },
      delay: (_) async {},
    );

    final result = await service.applyChange(
      original: original,
      desired: desired,
      key: OpenClashQuickSettingKey.sniffer,
    );

    expect(result.success, isTrue);
    final reloadRequests = requests
        .where((request) =>
            request.method == 'PUT' &&
            request.url.path == '/configs' &&
            request.url.queryParameters['force'] == 'true')
        .toList();
    expect(reloadRequests, hasLength(1));
    expect(reloadRequests.single.body, contains('/etc/openclash/config.yaml'));
    expect(reloadRequests.single.body, isNot(contains('payload')));
    expect(
        commands.firstWhere(_isApplyCommand), isNot(contains('api_request')));
  });

  test('running mode persists UCI then restarts through the coordinator',
      () async {
    var current = original;
    final desired = original.copyWith(runVariant: OpenClashRunVariant.tun);
    final events = <String>[];
    final coordinator = OpenClashRestartCoordinator(
      restartCommand: (_) async => events.add('restart'),
      healthProbe: () async => events.add('health'),
      delay: (_) async {},
      initialWait: Duration.zero,
      requiredHealthyChecks: 1,
      verificationAttempts: 1,
      terminalStateDuration: Duration.zero,
    );
    addTearDown(coordinator.dispose);
    final service = OpenClashQuickSettingsService(
      clashService: _clashService(() => current.proxyMode),
      restartCoordinator: coordinator,
      transactionIdFactory: () => 'ordered-run-mode',
      commandRunner: (command) async {
        if (_isRunModePersistCommand(command)) {
          events.add('persist');
          current = desired;
          return 'PROXLY_PERSISTED=1\n';
        }
        if (_isLoadCommand(command)) return _settingsOutput(current);
        return '';
      },
      delay: (_) async {},
    );

    final result = await service.applyChange(
      original: original,
      desired: desired,
      key: OpenClashQuickSettingKey.runVariant,
    );

    expect(result.success, isTrue);
    expect(events.indexOf('persist'), lessThan(events.indexOf('restart')));
    expect(events.indexOf('restart'), lessThan(events.indexOf('health')));
    expect(coordinator.reason, OpenClashRestartReason.quickSetting);
    expect(events, isNot(contains('mihomo-put')));
  });

  test('running mode reports saved changes when restart fails', () async {
    var current = original;
    final desired = original.copyWith(runVariant: OpenClashRunVariant.tun);
    final commands = <String>[];
    final coordinator = OpenClashRestartCoordinator(
      restartCommand: (_) async => throw StateError('restart unavailable'),
      healthProbe: () async {},
      delay: (_) async {},
      initialWait: Duration.zero,
      requiredHealthyChecks: 1,
      verificationAttempts: 1,
      terminalStateDuration: Duration.zero,
    );
    addTearDown(coordinator.dispose);
    final service = OpenClashQuickSettingsService(
      clashService: _clashService(() => current.proxyMode),
      restartCoordinator: coordinator,
      transactionIdFactory: () => 'failed-run-mode',
      commandRunner: (command) async {
        commands.add(command);
        if (_isRunModePersistCommand(command)) {
          current = desired;
          return 'PROXLY_PERSISTED=1\n';
        }
        if (_isLoadCommand(command)) return _settingsOutput(current);
        return '';
      },
      delay: (_) async {},
    );

    final result = await service.applyChange(
      original: original,
      desired: desired,
      key: OpenClashQuickSettingKey.runVariant,
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'restart_failed');
    expect(result.failureStage, '重启或等待 OpenClash 上线');
    expect(result.changesPersisted, isTrue);
    expect(result.canRetry, isTrue);
    expect(result.settings.runVariant, OpenClashRunVariant.tun);
    final persistCommand = commands.firstWhere(_isRunModePersistCommand);
    expect(persistCommand, isNot(contains('PROXLY_RUNTIME')));
    expect(persistCommand, isNot(contains('ruby -ryaml')));
    expect(commands.where(_isApplyCommand), isEmpty);
  });

  test('runtime settings require Ruby before any mutation', () async {
    final commands = <String>[];
    final service = OpenClashQuickSettingsService(
      clashService: _clashService(() => original.proxyMode),
      commandRunner: (command) async {
        commands.add(command);
        if (_isCapabilityCommand(command)) {
          return '''
PROXLY_CAPS=1
cap_uci=1
cap_core=1
cap_init=1
cap_ruby=0
cap_yaml_compat=0
cap_runtime=1
openclash_version=v0.46.000
''';
        }
        if (_isLoadCommand(command)) return _settingsOutput(original);
        return '';
      },
    );

    final result = await service.applyChange(
      original: original,
      desired: original.copyWith(snifferEnabled: true),
      key: OpenClashQuickSettingKey.sniffer,
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'ruby_missing');
    expect(result.failureStage, '检查 OpenClash 环境');
    expect(commands.where(_isApplyCommand), isEmpty);
    expect(commands.where(_isRuntimePersistCommand), isEmpty);
  });

  test('runtime YAML errors keep useful detail and redact secrets', () async {
    final commands = <String>[];
    final service = OpenClashQuickSettingsService(
      clashService: _clashService(() => original.proxyMode),
      transactionIdFactory: () => 'yaml-error',
      commandRunner: (command) async {
        commands.add(command);
        if (_isRollbackCommand(command)) {
          return 'PROXLY_ROLLBACK=success\n';
        }
        if (_isLoadCommand(command)) return _settingsOutput(original);
        if (_isApplyCommand(command)) {
          throw SshCommandException(
            command: command,
            exitCode: 1,
            exitSignal: null,
            stdout: '',
            stderr: '''
PROXLY_ERROR=runtime_modify_failed
PROXLY_DETAIL=Psych::BadAlias: Unknown alias at /etc/openclash/config.yaml token=secret-value http://192.168.1.1:9090
''',
          );
        }
        return '';
      },
      delay: (_) async {},
    );

    final result = await service.applyChange(
      original: original,
      desired: original.copyWith(snifferEnabled: true),
      key: OpenClashQuickSettingKey.sniffer,
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'runtime_modify_failed');
    expect(result.errorDetail, contains('Psych::BadAlias'));
    expect(result.errorDetail, contains('[openclash-path]'));
    expect(result.errorDetail, contains('token=[redacted]'));
    expect(result.errorDetail, contains('[url]'));
    expect(result.errorDetail, isNot(contains('secret-value')));
    expect(result.errorDetail, isNot(contains('192.168.1.1')));
    expect(result.rollbackAttempted, isTrue);
    expect(result.rollbackSucceeded, isTrue);
  });

  test('live proxy mode loads controller settings before app API calls',
      () async {
    var current = original;
    var settingsLoadCount = 0;
    final desired = original.copyWith(proxyMode: OpenClashProxyMode.global);
    final requests = <http.Request>[];
    final clashService = ClashService.forTesting(
      config: const ClashConfig(host: '192.168.1.1:9090', token: 'stale'),
      preserveInjectedConfig: false,
      settingsLoader: () async {
        settingsLoadCount++;
        return const ConnectionSettings(
          host: '10.0.0.2:9090',
          token: 'fresh',
          sshPassword: '',
        );
      },
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'PATCH') {
          current = desired;
          return http.Response('{}', 200);
        }
        return http.Response('{"mode":"${current.proxyMode.name}"}', 200);
      }),
    );
    final service = OpenClashQuickSettingsService(
      clashService: clashService,
      transactionIdFactory: () => 'autoload-proxy',
      commandRunner: (command) async {
        if (_isApplyCommand(command)) {
          current = desired;
          return _applyReadyOutput(OpenClashQuickSettingKey.proxyMode);
        }
        if (_isLoadCommand(command)) return _settingsOutput(current);
        if (_isPidCommand(command)) return 'PROXLY_PID=42\n';
        return '';
      },
      delay: (_) async {},
    );

    final result = await service.applyChange(
      original: original,
      desired: desired,
      key: OpenClashQuickSettingKey.proxyMode,
    );

    expect(result.success, isTrue);
    expect(settingsLoadCount, greaterThan(0));
    final liveModeRequest = requests.firstWhere(
      (request) => request.method == 'PATCH' && request.url.query.isEmpty,
    );
    expect(liveModeRequest.url.authority, '10.0.0.2:9090');
    expect(liveModeRequest.headers['Authorization'], 'Bearer fresh');
  });

  test('runtime reload loads controller settings before app API calls',
      () async {
    var current = original;
    var settingsLoadCount = 0;
    final desired = original.copyWith(dnsProxyEnabled: true);
    final requests = <http.Request>[];
    final clashService = ClashService.forTesting(
      config: const ClashConfig(host: '192.168.1.1:9090', token: 'stale'),
      preserveInjectedConfig: false,
      settingsLoader: () async {
        settingsLoadCount++;
        return const ConnectionSettings(
          host: '10.0.0.3:9090',
          token: 'fresh-dns',
          sshPassword: '',
        );
      },
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{"mode":"${current.proxyMode.name}"}', 200);
      }),
    );
    final service = OpenClashQuickSettingsService(
      clashService: clashService,
      transactionIdFactory: () => 'autoload-runtime',
      commandRunner: (command) async {
        if (_isApplyCommand(command)) {
          return _applyReadyOutput(OpenClashQuickSettingKey.dnsProxy);
        }
        if (_isRuntimePersistCommand(command)) {
          current = desired;
          return 'PROXLY_PERSISTED=1\n';
        }
        if (_isLoadCommand(command)) return _settingsOutput(current);
        if (_isPidCommand(command)) return 'PROXLY_PID=42\n';
        return '';
      },
      delay: (_) async {},
    );

    final result = await service.applyChange(
      original: original,
      desired: desired,
      key: OpenClashQuickSettingKey.dnsProxy,
    );

    expect(result.success, isTrue);
    expect(settingsLoadCount, greaterThan(0));
    final reloadRequest = requests.firstWhere(
      (request) =>
          request.method == 'PUT' &&
          request.url.queryParameters['force'] == 'true',
    );
    expect(reloadRequest.url.authority, '10.0.0.3:9090');
    expect(reloadRequest.headers['Authorization'], 'Bearer fresh-dns');
  });

  test('controller API failure reports a clear error and rolls back', () async {
    var current = original;
    var reloadAttempts = 0;
    final desired = original.copyWith(snifferEnabled: true);
    final commands = <String>[];
    final clashService = ClashService.forTesting(
      config: const ClashConfig(host: '192.168.1.1:9090', token: 'secret'),
      client: MockClient((request) async {
        if (request.method == 'PUT' &&
            request.url.queryParameters['force'] == 'true') {
          reloadAttempts++;
          return http.Response('', reloadAttempts == 1 ? 500 : 204);
        }
        return http.Response('{"mode":"${current.proxyMode.name}"}', 200);
      }),
    );
    final service = OpenClashQuickSettingsService(
      clashService: clashService,
      transactionIdFactory: () => 'controller-fail',
      commandRunner: (command) async {
        commands.add(command);
        if (_isApplyCommand(command)) {
          current = desired;
          return _applyReadyOutput(OpenClashQuickSettingKey.sniffer);
        }
        if (_isRollbackCommand(command)) {
          current = original;
          return 'PROXLY_ROLLBACK=success\n';
        }
        if (_isLoadCommand(command)) return _settingsOutput(current);
        if (_isPidCommand(command)) return 'PROXLY_PID=42\n';
        return '';
      },
      delay: (_) async {},
    );

    final result = await service.applyChange(
      original: original,
      desired: desired,
      key: OpenClashQuickSettingKey.sniffer,
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'controller_rejected');
    expect(result.errorDetail, '热重载 Mihomo 配置：HTTP 500');
    expect(result.rollbackAttempted, isTrue);
    expect(result.rollbackSucceeded, isTrue);
    expect(commands.where(_isRollbackCommand), hasLength(1));
  });

  final controllerPreflightCases = <({
    OpenClashQuickSettingKey key,
    OpenClashQuickSettings desired,
  })>[
    (
      key: OpenClashQuickSettingKey.proxyMode,
      desired: original.copyWith(proxyMode: OpenClashProxyMode.global),
    ),
    (
      key: OpenClashQuickSettingKey.sniffer,
      desired: original.copyWith(snifferEnabled: true),
    ),
    (
      key: OpenClashQuickSettingKey.dnsProxy,
      desired: original.copyWith(dnsProxyEnabled: true),
    ),
  ];

  for (final testCase in controllerPreflightCases) {
    test('${testCase.key.name} checks the controller before SSH mutation',
        () async {
      final commands = <String>[];
      final service = OpenClashQuickSettingsService(
        clashService: ClashService.forTesting(
          config: const ClashConfig(
            host: '192.168.1.1:9090',
            token: 'bad-token',
          ),
          client: MockClient(
            (_) async => http.Response('{"message":"invalid token"}', 401),
          ),
        ),
        commandRunner: (command) async {
          commands.add(command);
          if (_isLoadCommand(command)) return _settingsOutput(original);
          return '';
        },
      );

      final result = await service.applyChange(
        original: original,
        desired: testCase.desired,
        key: testCase.key,
      );

      expect(result.success, isFalse);
      expect(result.errorCode, 'controller_unauthorized');
      expect(result.errorDetail, '检查 Clash 控制器：HTTP 401: invalid token');
      expect(commands.where(_isApplyCommand), isEmpty);
      expect(commands.where(_isRollbackCommand), isEmpty);
      expect(result.rollbackAttempted, isFalse);
    });
  }

  test('SSH-only quick settings do not depend on app-side config writes',
      () async {
    var current = original;
    final desired = original.copyWith(areaBypass: OpenClashAreaBypass.mainland);
    final requests = <http.Request>[];
    final service = OpenClashQuickSettingsService(
      clashService: ClashService.forTesting(
        config: const ClashConfig(host: '192.168.1.1:9090', token: 'secret'),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('{"mode":"${current.proxyMode.name}"}', 200);
        }),
      ),
      transactionIdFactory: () => 'ssh-only',
      commandRunner: (command) async {
        if (_isApplyCommand(command)) {
          current = desired;
          return _applyReadyOutput(OpenClashQuickSettingKey.areaBypass);
        }
        if (_isLoadCommand(command)) return _settingsOutput(current);
        if (_isPidCommand(command)) return 'PROXLY_PID=42\n';
        return '';
      },
      delay: (_) async {},
    );

    final result = await service.applyChange(
      original: original,
      desired: desired,
      key: OpenClashQuickSettingKey.areaBypass,
    );

    expect(result.success, isTrue);
    expect(
      requests.where(
        (request) => request.method == 'PUT' || request.method == 'PATCH',
      ),
      isEmpty,
    );
  });

  test('verification failure restores the saved UCI and runtime state',
      () async {
    final commands = <String>[];
    final desired = original.copyWith(snifferEnabled: true);
    final service = OpenClashQuickSettingsService(
      clashService: _clashService(() => original.proxyMode),
      transactionIdFactory: () => 'rollback',
      commandRunner: (command) async {
        commands.add(command);
        if (_isApplyCommand(command)) {
          return _applyReadyOutput(OpenClashQuickSettingKey.sniffer);
        }
        if (_isRuntimePersistCommand(command)) {
          return 'PROXLY_PERSISTED=1\n';
        }
        if (_isLoadCommand(command)) return _settingsOutput(original);
        if (_isRollbackCommand(command)) return 'PROXLY_ROLLBACK=success\n';
        return '';
      },
    );

    final result = await service.applyChange(
      original: original,
      desired: desired,
      key: OpenClashQuickSettingKey.sniffer,
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'verification_failed');
    expect(result.rollbackAttempted, isTrue);
    expect(result.rollbackSucceeded, isTrue);
    final rollback = commands.firstWhere(_isRollbackCommand);
    expect(rollback, contains('uci import openclash'));
    expect(rollback, isNot(contains('api_request')));
    expect(rollback, isNot(contains('/etc/init.d/openclash restart')));
  });

  test('failed consecutive health probing rolls the transaction back',
      () async {
    var current = original;
    var proxyModeGets = 0;
    final desired = original.copyWith(proxyMode: OpenClashProxyMode.global);
    final clashService = ClashService.forTesting(
      config: const ClashConfig(
        host: '192.168.1.1:9090',
        token: 'secret',
      ),
      client: MockClient((request) async {
        if (request.method == 'PATCH') {
          if (request.body.contains('"global"')) {
            current = desired;
          } else if (request.body.contains('"rule"')) {
            current = original;
          }
          return http.Response('{}', 200);
        }
        proxyModeGets++;
        if (proxyModeGets == 3) {
          throw StateError('temporarily offline');
        }
        return http.Response('{"mode":"${current.proxyMode.name}"}', 200);
      }),
    );
    final service = OpenClashQuickSettingsService(
      clashService: clashService,
      transactionIdFactory: () => 'health-check',
      delay: (_) async {},
      commandRunner: (command) async {
        if (_isApplyCommand(command)) {
          current = desired;
          return _applyReadyOutput(OpenClashQuickSettingKey.proxyMode);
        }
        if (_isRollbackCommand(command)) {
          current = original;
          return 'PROXLY_ROLLBACK=success\n';
        }
        if (_isLoadCommand(command)) return _settingsOutput(current);
        if (_isPidCommand(command)) return 'PROXLY_PID=42\n';
        return '';
      },
    );

    final result = await service.applyChange(
      original: original,
      desired: desired,
      key: OpenClashQuickSettingKey.proxyMode,
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'core_health_failed');
    expect(result.rollbackAttempted, isTrue);
    expect(result.rollbackSucceeded, isTrue);
    expect(current, original);
  });

  test('an interrupted remote transaction attempts recovery from its backup',
      () async {
    final commands = <String>[];
    final service = OpenClashQuickSettingsService(
      clashService: _clashService(() => original.proxyMode),
      transactionIdFactory: () => 'interrupted',
      commandRunner: (command) async {
        commands.add(command);
        if (_isApplyCommand(command)) {
          throw SshCommandException(
            command: command,
            exitCode: null,
            exitSignal: 'connection-lost',
            stdout: '',
            stderr: '',
          );
        }
        if (_isRollbackCommand(command)) {
          return 'PROXLY_ROLLBACK=success\n';
        }
        if (_isLoadCommand(command)) return _settingsOutput(original);
        return '';
      },
    );

    final result = await service.applyChange(
      original: original,
      desired: original.copyWith(proxyMode: OpenClashProxyMode.global),
      key: OpenClashQuickSettingKey.proxyMode,
    );

    expect(result.success, isFalse);
    expect(result.rollbackAttempted, isTrue);
    expect(result.rollbackSucceeded, isTrue);
    expect(commands.where(_isRollbackCommand), hasLength(1));
  });

  test('rejects multiple changes in one transaction', () async {
    final service = OpenClashQuickSettingsService(
      clashService: _clashService(() => original.proxyMode),
      commandRunner: (_) async => '',
    );

    expect(
      () => service.applyChange(
        original: original,
        desired: original.copyWith(
          proxyMode: OpenClashProxyMode.global,
          dnsProxyEnabled: true,
        ),
        key: OpenClashQuickSettingKey.proxyMode,
      ),
      throwsArgumentError,
    );
  });

  test('rejects stream unlock outside rule mode before SSH', () async {
    var commandCount = 0;
    final starting = original.copyWith(proxyMode: OpenClashProxyMode.global);
    final service = OpenClashQuickSettingsService(
      clashService: _clashService(() => starting.proxyMode),
      commandRunner: (_) async {
        commandCount++;
        return '';
      },
    );

    await expectLater(
      service.applyChange(
        original: starting,
        desired: starting.copyWith(streamUnlockEnabled: true),
        key: OpenClashQuickSettingKey.streamUnlock,
      ),
      throwsA(isA<Object>()),
    );
    expect(commandCount, 0);
  });
}

ClashService _clashService(OpenClashProxyMode Function() currentMode) {
  return ClashService.forTesting(
    config: const ClashConfig(host: '192.168.1.1:9090', token: 'secret'),
    client: MockClient(
      (_) async => http.Response('{"mode":"${currentMode().name}"}', 200),
    ),
  );
}

bool _isApplyCommand(String command) =>
    command.contains('armed=1') && command.contains('PROXLY_TX_READY=1');

bool _isLoadCommand(String command) =>
    command.contains('for option in en_mode');

bool _isCapabilityCommand(String command) =>
    command.contains("printf 'PROXLY_CAPS=1");

bool _isPidCommand(String command) =>
    command.contains("printf 'PROXLY_PID=%s") &&
    !command.contains('PROXLY_PID_BEFORE');

bool _isRollbackCommand(String command) =>
    command.contains(r'[ -f "$tx.uci" ] || ok=0');

bool _isRuntimePersistCommand(String command) =>
    command.contains('Only runtime settings') == false &&
    command.contains('PROXLY_PERSISTED=1') &&
    command.contains('backup_missing');

bool _isRunModePersistCommand(String command) =>
    command.contains('PROXLY_PERSISTED=1') &&
    command.contains('openclash.config.en_mode=');

String _applyReadyOutput(OpenClashQuickSettingKey key) {
  final runtimePath = _isRuntimeKey(key)
      ? 'PROXLY_RUNTIME_PATH=/etc/openclash/config.yaml\n'
      : '';
  return '${runtimePath}PROXLY_TX_READY=1\nPROXLY_PID_BEFORE=42\n';
}

bool _isRuntimeKey(OpenClashQuickSettingKey key) =>
    key == OpenClashQuickSettingKey.sniffer ||
    key == OpenClashQuickSettingKey.dnsProxy;

String _settingsOutput(OpenClashQuickSettings settings) {
  final runBase =
      settings.baseMode == OpenClashBaseMode.fakeIp ? 'fake-ip' : 'redir-host';
  final runSuffix = switch (settings.runVariant) {
    OpenClashRunVariant.tun => '-tun',
    OpenClashRunVariant.mix => '-mix',
    _ => '',
  };
  final area = switch (settings.areaBypass) {
    OpenClashAreaBypass.mainland => '1',
    OpenClashAreaBypass.overseas => '2',
    OpenClashAreaBypass.disabled => '0',
  };
  return '''
en_mode=$runBase$runSuffix
proxy_mode=${settings.proxyMode.name}
china_ip_route=$area
enable_meta_sniffer=${settings.snifferEnabled ? 1 : 0}
enable_respect_rules=${settings.dnsProxyEnabled ? 1 : 0}
stream_auto_select=${settings.streamUnlockEnabled ? 1 : 0}
router_self_proxy=${settings.routerSelfProxyEnabled ? 1 : 0}
stream_unlock_supported=${settings.streamUnlockSupported ? 1 : 0}
runtime_config_available=1
runtime_tun_enabled=${settings.runVariant == OpenClashRunVariant.compatibility ? 0 : 1}
runtime_sniffer=${settings.snifferEnabled ? 1 : 0}
runtime_dns_proxy=${settings.dnsProxyEnabled ? 1 : 0}
''';
}
