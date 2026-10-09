import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/clash_config_file_service.dart';

void main() {
  const activePath = '/etc/openclash/config/main.yaml';
  const local = ClashActiveConfig(file: ClashConfigFile(path: activePath));

  test('same filenames in different directories are not active aliases', () {
    expect(
        ClashConfigFileService.matchActiveConfigPath(
            [const ClashConfigFile(path: '/etc/clash/config/main.yaml')],
            local),
        isNull);
    expect(
        ClashConfigFileService.matchActiveConfigPath(
            [const ClashConfigFile(path: '/etc/openclash/config/Main.yaml')],
            local),
        isNull);
  });

  for (final source in [
    activePath,
    '/openclash/config/main.yaml',
    '/etc/clash/config/main.yaml',
    '/etc/openclash/config/Main.yaml'
  ]) {
    test('rename updates only the actual active reference: $source', () async {
      final calls = <(String, String, bool)>[];
      final canonical =
          source == '/openclash/config/main.yaml' ? activePath : source;
      final result = await ClashConfigFileService.renameWithActiveConfig(
          sourcePath: source,
          fileName: 'renamed.yaml',
          resolvePath: (path) async => path == source ? canonical : path,
          loadActiveConfig: () async => local,
          rename: (source, target, active) async =>
              calls.add((source, target, active)));
      final expectedTarget =
          canonical.replaceFirst(RegExp(r'[^/]+$'), 'renamed.yaml');
      expect(calls, [(canonical, expectedTarget, canonical == activePath)]);
      expect(result.path, expectedTarget);
    });
  }

  final subscription = ClashConfigFileService.parseActiveConfigOutput('''
openclash.config.config_path='$activePath'
openclash.sub=config_subscribe
openclash.sub.enabled='1'
openclash.sub.name='main'
openclash.sub.address='https://example.com/sub'
''');
  for (final scenario in [
    'subscription',
    'subscription-alias',
    'unknown',
    'lookup-failure',
    'escaped-path'
  ]) {
    test('unsafe rename does not mutate remote files: $scenario', () async {
      var renamed = false;
      await expectLater(
          ClashConfigFileService.renameWithActiveConfig(
              sourcePath: scenario == 'subscription-alias'
                  ? '/openclash/config/main.yaml'
                  : activePath,
              fileName: 'renamed.yaml',
              resolvePath: (path) async =>
                  scenario == 'escaped-path' ? '/tmp/main.yaml' : activePath,
              loadActiveConfig: () async {
                if (scenario == 'lookup-failure') throw StateError('offline');
                return scenario == 'unknown'
                    ? const ClashActiveConfig(file: null)
                    : subscription;
              },
              rename: (_, __, ___) async {
                renamed = true;
              }),
          scenario == 'lookup-failure'
              ? throwsStateError
              : scenario == 'escaped-path'
                  ? throwsArgumentError
                  : throwsFormatException);
      expect(renamed, isFalse);
    });
  }

  test('an inactive YAML can be renamed while a subscription is active',
      () async {
    var updatedActive = true;
    await ClashConfigFileService.renameWithActiveConfig(
        sourcePath: '/etc/openclash/config/other.yaml',
        fileName: 'renamed.yaml',
        resolvePath: (path) async => path,
        loadActiveConfig: () async => subscription,
        rename: (_, __, active) async {
          updatedActive = active;
        });
    expect(updatedActive, isFalse);
  });
}
