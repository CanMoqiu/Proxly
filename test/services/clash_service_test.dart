import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxly/services/clash_service.dart';
import 'package:proxly/services/connection_settings_store.dart';

void main() {
  group('close individual connection', () {
    for (final code in [204, 401, 500]) {
      test('validates HTTP $code before reporting success', () async {
        final service = ClashService.forTesting(
            config: const ClashConfig(
                host: '192.168.1.1:9090', token: 'test-token'),
            client: MockClient((request) async {
              expect(request.method, 'DELETE');
              expect(request.url.pathSegments.last, 'id/with?characters');
              expect(request.headers['Authorization'], 'Bearer test-token');
              return http.Response('', code);
            }));
        final close = service.closeConnection('id/with?characters');
        if (code == 204) {
          await close;
        } else {
          await expectLater(
              close,
              throwsA(isA<ClashControllerException>()
                  .having((e) => e.statusCode, 'status', code)));
        }
      });
    }
    test('transport failures remain actionable', () async {
      final service = ClashService.forTesting(
          config: const ClashConfig(host: '192.168.1.1:9090', token: ''),
          client:
              MockClient((_) async => throw http.ClientException('offline')));
      await expectLater(
          service.closeConnection('id'),
          throwsA(isA<ClashControllerException>().having(
              (e) => e.kind, 'kind', ClashControllerFailureKind.unreachable)));
    });
  });
  group('ProviderTraffic remaining quota', () {
    test('calculates a shrinking remaining value and percentage', () {
      const traffic = ProviderTraffic(name: 'provider', used: 25, total: 100);

      expect(traffic.remaining, 75);
      expect(traffic.remainingPercentage, 0.75);
      expect(traffic.remainingLevel, ProviderTrafficLevel.healthy);
    });

    test('clamps overused traffic to zero', () {
      const traffic = ProviderTraffic(name: 'provider', used: 120, total: 100);

      expect(traffic.remaining, 0);
      expect(traffic.remainingPercentage, 0);
      expect(traffic.remainingLevel, ProviderTrafficLevel.critical);
    });

    test('uses the selected warning and critical thresholds', () {
      const fiftyPercent =
          ProviderTraffic(name: 'warning', used: 50, total: 100);
      const justAboveTwenty =
          ProviderTraffic(name: 'warning', used: 79, total: 100);
      const twentyPercent =
          ProviderTraffic(name: 'critical', used: 80, total: 100);

      expect(fiftyPercent.remainingLevel, ProviderTrafficLevel.warning);
      expect(justAboveTwenty.remainingLevel, ProviderTrafficLevel.warning);
      expect(twentyPercent.remainingLevel, ProviderTrafficLevel.critical);
    });

    test('treats zero total and zero expire as unlimited quota', () {
      const traffic = ProviderTraffic(
        name: 'provider',
        used: 1024,
        total: 0,
        expire: 0,
      );

      expect(traffic.isUnlimited, isTrue);
      expect(traffic.remaining, 0);
      expect(traffic.remainingPercentage, 1);
      expect(traffic.remainingLevel, ProviderTrafficLevel.healthy);
    });

    test('keeps zero total without zero expire as a zero traffic quota', () {
      const missingExpire =
          ProviderTraffic(name: 'missing', used: 1024, total: 0);
      const timeLimited = ProviderTraffic(
        name: 'time-limited',
        used: 1024,
        total: 0,
        expire: 1893456000,
      );

      expect(missingExpire.isUnlimited, isFalse);
      expect(missingExpire.remainingPercentage, 0);
      expect(missingExpire.remainingLevel, ProviderTrafficLevel.critical);
      expect(timeLimited.isUnlimited, isFalse);
      expect(timeLimited.remainingPercentage, 0);
      expect(timeLimited.remainingLevel, ProviderTrafficLevel.critical);
    });
  });

  group('provider traffic', () {
    test('keeps unlimited providers instead of filtering them out', () async {
      final service = ClashService.forTesting(
        config: const ClashConfig(host: '192.168.1.1:9090', token: ''),
        client: MockClient((request) async {
          expect(request.url.path, '/providers/proxies');
          return http.Response(
            jsonEncode({
              'providers': {
                'unlimited': {
                  'subscriptionInfo': {
                    'Upload': 1024,
                    'Download': '2048',
                    'Total': 0,
                    'Expire': 0,
                  },
                },
                'limited': {
                  'subscriptionInfo': {
                    'Upload': 1,
                    'Download': 2,
                    'Total': 10,
                    'Expire': '1893456000',
                  },
                },
                'zero-quota': {
                  'subscriptionInfo': {
                    'Upload': 0,
                    'Download': 0,
                    'Total': 0,
                    'Expire': 1893456000,
                  },
                },
              },
            }),
            200,
          );
        }),
      );

      final providers = await service.getProviderTraffic();

      expect(providers, hasLength(3));
      expect(providers.first.name, 'unlimited');
      expect(providers.first.used, 3072);
      expect(providers.first.isUnlimited, isTrue);
      expect(providers[1].remaining, 7);
      expect(providers[1].expire, 1893456000);
      expect(providers.last.name, 'zero-quota');
      expect(providers.last.isUnlimited, isFalse);
      expect(providers.last.remainingPercentage, 0);
    });
  });

  group('flushDnsCache', () {
    test('posts to the Mihomo DNS cache endpoint with authorization', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/cache/dns/flush');
        expect(request.headers['Authorization'], 'Bearer secret');
        return http.Response('', 204);
      });
      final service = ClashService.forTesting(
        config: const ClashConfig(host: '192.168.1.1:9090', token: 'secret'),
        client: client,
      );

      await service.flushDnsCache();
    });

    test('reports an unsupported core on HTTP 404', () async {
      final service = ClashService.forTesting(
        config: const ClashConfig(host: '192.168.1.1:9090', token: ''),
        client: MockClient((_) async => http.Response('', 404)),
      );

      expect(
        service.flushDnsCache(),
        throwsA(
          predicate(
            (error) => error
                .toString()
                .contains('does not support clearing the DNS cache'),
          ),
        ),
      );
    });

    test('reports an invalid token on HTTP 401', () async {
      final service = ClashService.forTesting(
        config: const ClashConfig(host: '192.168.1.1:9090', token: 'bad'),
        client: MockClient((_) async => http.Response('', 401)),
      );

      expect(
        service.flushDnsCache(),
        throwsA(predicate((error) => error.toString().contains('token'))),
      );
    });
  });

  group('closeAllConnections', () {
    test('deletes the Mihomo connections endpoint with authorization',
        () async {
      final client = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/connections');
        expect(request.headers['Authorization'], 'Bearer secret');
        return http.Response('', 204);
      });
      final service = ClashService.forTesting(
        config: const ClashConfig(host: '192.168.1.1:9090', token: 'secret'),
        client: client,
      );

      await service.closeAllConnections();
    });

    test('reports an unsupported core on HTTP 404', () async {
      final service = ClashService.forTesting(
        config: const ClashConfig(host: '192.168.1.1:9090', token: ''),
        client: MockClient((_) async => http.Response('', 404)),
      );

      expect(
        service.closeAllConnections(),
        throwsA(
          predicate(
            (error) => error
                .toString()
                .contains('does not support closing all connections'),
          ),
        ),
      );
    });
  });

  group('runtime configuration', () {
    test('controller operations refresh non-injected settings every time',
        () async {
      var loadCount = 0;
      final requests = <http.Request>[];
      final service = ClashService.forTesting(
        config: const ClashConfig(host: '192.168.1.1:9090', token: 'stale'),
        preserveInjectedConfig: false,
        settingsLoader: () async {
          loadCount++;
          return const ConnectionSettings(
            host: '10.0.0.2:9090',
            token: 'fresh',
            sshPassword: '',
          );
        },
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('', 204);
        }),
      );

      await service.setProxyMode('global');
      await service.reloadConfig('/etc/openclash/config.yaml');

      expect(loadCount, 2);
      expect(requests, hasLength(2));
      expect(
        requests.map((request) => request.url.authority),
        everyElement('10.0.0.2:9090'),
      );
      expect(
        requests.map((request) => request.headers['Authorization']),
        everyElement('Bearer fresh'),
      );
    });

    test('ensureConfigLoaded keeps injected testing configuration', () async {
      var loadCount = 0;
      late http.Request captured;
      final service = ClashService.forTesting(
        config: const ClashConfig(host: '192.168.1.1:9090', token: 'secret'),
        settingsLoader: () async {
          loadCount++;
          return const ConnectionSettings(
            host: '10.0.0.2:9090',
            token: 'fresh',
            sshPassword: '',
          );
        },
        client: MockClient((request) async {
          captured = request;
          return http.Response('', 204);
        }),
      );

      await service.ensureConfigLoaded();
      await service.setProxyMode('global');

      expect(loadCount, 0);
      expect(captured.url.authority, '192.168.1.1:9090');
      expect(captured.headers['Authorization'], 'Bearer secret');
    });

    test('reads and updates the validated proxy mode', () async {
      final requests = <http.Request>[];
      final service = ClashService.forTesting(
        config: const ClashConfig(host: '192.168.1.1:9090', token: 'secret'),
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return http.Response('{"mode":"rule"}', 200);
          }
          expect(jsonDecode(request.body), {'mode': 'global'});
          return http.Response('', 204);
        }),
      );

      expect(await service.getProxyMode(), 'rule');
      await service.setProxyMode('global');

      expect(requests.map((request) => request.method), ['GET', 'PATCH']);
      expect(requests.last.url.path, '/configs');
      expect(requests.last.headers['Authorization'], 'Bearer secret');
    });

    test('reloads only an OpenClash runtime configuration path', () async {
      late http.Request captured;
      final service = ClashService.forTesting(
        config: const ClashConfig(host: '192.168.1.1:9090', token: ''),
        client: MockClient((request) async {
          captured = request;
          return http.Response('', 204);
        }),
      );

      await service.reloadConfig('/etc/openclash/config.yaml');

      expect(captured.method, 'PUT');
      expect(captured.url.queryParameters['force'], 'true');
      expect(jsonDecode(captured.body), {
        'path': '/etc/openclash/config.yaml',
      });
      expect(
        () => service.reloadConfig('/tmp/config.yaml'),
        throwsArgumentError,
      );
      expect(
        () => service.setProxyMode('script'),
        throwsArgumentError,
      );
    });

    test('classifies and sanitizes rejected controller responses', () async {
      final service = ClashService.forTesting(
        config: const ClashConfig(
          host: '192.168.1.1:9090',
          token: 'secret-token',
        ),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'message': 'invalid secret-token\nBearer exposed ${'x' * 260}',
            }),
            400,
          ),
        ),
      );

      try {
        await service.setProxyMode('global');
        fail('Expected a controller exception');
      } on ClashControllerException catch (error) {
        expect(error.kind, ClashControllerFailureKind.badRequest);
        expect(error.statusCode, 400);
        expect(error.detail, isNot(contains('secret-token')));
        expect(error.detail, isNot(contains('exposed')));
        expect(error.detail, contains('[redacted]'));
        expect(error.detail, endsWith('...'));
        expect(error.detail!.length, lessThanOrEqualTo(243));
      }
    });

    test('distinguishes authorization and other controller rejection',
        () async {
      var status = 401;
      final service = ClashService.forTesting(
        config: const ClashConfig(host: '192.168.1.1:9090', token: 'bad'),
        client: MockClient((_) async => http.Response('denied', status)),
      );

      await expectLater(
        service.setProxyMode('global'),
        throwsA(
          isA<ClashControllerException>().having(
            (error) => error.kind,
            'kind',
            ClashControllerFailureKind.unauthorized,
          ),
        ),
      );

      status = 503;
      await expectLater(
        service.reloadConfig('/etc/openclash/config.yaml'),
        throwsA(
          isA<ClashControllerException>().having(
            (error) => error.kind,
            'kind',
            ClashControllerFailureKind.rejected,
          ),
        ),
      );
    });

    test('distinguishes controller timeout and network failure', () async {
      var timeout = true;
      final service = ClashService.forTesting(
        config: const ClashConfig(host: '192.168.1.1:9090', token: ''),
        client: MockClient((_) async {
          if (timeout) throw TimeoutException('slow controller');
          throw http.ClientException('network unavailable');
        }),
      );

      await expectLater(
        service.setProxyMode('global'),
        throwsA(
          isA<ClashControllerException>().having(
            (error) => error.kind,
            'kind',
            ClashControllerFailureKind.timeout,
          ),
        ),
      );

      timeout = false;
      await expectLater(
        service.reloadConfig('/etc/openclash/config.yaml'),
        throwsA(
          isA<ClashControllerException>().having(
            (error) => error.kind,
            'kind',
            ClashControllerFailureKind.unreachable,
          ),
        ),
      );
    });
  });
}
