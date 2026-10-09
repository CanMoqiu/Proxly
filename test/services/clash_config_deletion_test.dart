import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/clash_config_file_service.dart';

const target = '/etc/openclash/config/other.yaml';
const active = '/etc/openclash/config/current.yaml';

void main() {
  test('deletes only the resolved inactive YAML after checking the active file',
      () async {
    final calls = <String>[];
    await ClashConfigFileService.deleteInactiveConfigFile(
        path: '/openclash/config/other.yaml',
        loadActiveConfig: () async {
          calls.add('active');
          return const ClashActiveConfig(file: ClashConfigFile(path: active));
        },
        resolvePath: (path) async {
          calls.add('resolve:$path');
          return path == '/openclash/config/other.yaml' ? target : path;
        },
        removeFile: (path) async {
          calls.add('remove:$path');
        });
    expect(calls, [
      'resolve:/openclash/config/other.yaml',
      'active',
      'resolve:$active',
      'remove:$target'
    ]);
  });

  for (final scenario in [
    'active',
    'alias',
    'subscription',
    'unknown',
    'lookup-fails',
    'escaped-target'
  ]) {
    test('deletion is refused for $scenario without removing any file',
        () async {
      var removed = false;
      await expectLater(
          ClashConfigFileService.deleteInactiveConfigFile(
              path: target,
              loadActiveConfig: () async {
                if (scenario == 'lookup-fails') throw Exception('offline');
                if (scenario == 'unknown') {
                  return const ClashActiveConfig(file: null);
                }
                if (scenario == 'subscription') {
                  return const ClashActiveConfig(
                      file: null,
                      source: ClashActiveConfigSource.subscription,
                      subscription: ClashSubscriptionInfo(
                          section: 'openclash.test',
                          address: 'https://example.com/sub',
                          name: 'other',
                          generatedPath: target));
                }
                return ClashActiveConfig(
                    file: ClashConfigFile(
                        path: scenario == 'alias' ? active : target));
              },
              resolvePath: (path) async {
                if (scenario == 'escaped-target') return '/tmp/other.yaml';
                return scenario == 'alias' ? target : path;
              },
              removeFile: (_) async {
                removed = true;
              }),
          scenario == 'escaped-target'
              ? throwsArgumentError
              : scenario == 'lookup-fails'
                  ? throwsA(isA<Exception>().having(
                      (e) => e.toString(), 'message', contains('offline')))
                  : throwsFormatException);
      expect(removed, isFalse);
    });
  }

  test('invalid paths are rejected before any remote operation', () async {
    for (final path in [
      '/tmp/file.yaml',
      '/etc/openclash/config/../../../etc/passwd',
      '/etc/openclash/config/file.txt'
    ]) {
      var accessed = false;
      await expectLater(
          ClashConfigFileService.deleteInactiveConfigFile(
              path: path,
              loadActiveConfig: () async {
                accessed = true;
                return const ClashActiveConfig(file: null);
              },
              resolvePath: (path) async {
                accessed = true;
                return path;
              },
              removeFile: (_) async {
                accessed = true;
              }),
          throwsArgumentError);
      expect(accessed, isFalse);
    }
  });

  test('SFTP removal failures propagate without claiming success', () async {
    await expectLater(
        ClashConfigFileService.deleteInactiveConfigFile(
            path: target,
            loadActiveConfig: () async =>
                const ClashActiveConfig(file: ClashConfigFile(path: active)),
            resolvePath: (path) async => path,
            removeFile: (_) async => throw StateError('permission denied')),
        throwsStateError);
  });
}
