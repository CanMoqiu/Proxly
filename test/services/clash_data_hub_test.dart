import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxly/services/clash_data_hub.dart';
import 'package:proxly/services/clash_service.dart';

void main() {
  late ClashDataHub hub;
  late DateTime now;
  var trafficCalls = 0;
  var providerCalls = 0;
  Completer<http.Response>? providers;
  Completer<http.Response>? traffic;
  final providerResponse = http.Response(
      jsonEncode({
        'providers': {
          'subscription': {
            'subscriptionInfo': {'Upload': 1, 'Download': 2, 'Total': 10}
          }
        }
      }),
      200);
  setUp(() {
    now = DateTime(2026);
    trafficCalls = providerCalls = 0;
    providers = traffic = null;
    hub = ClashDataHub.forTesting(
        now: () => now,
        service: ClashService.forTesting(
          config: const ClashConfig(host: '192.168.1.1:9090', token: ''),
          client: MockClient((request) async {
            if (request.url.path == '/providers/proxies') {
              providerCalls++;
              return providers?.future ?? Future.value(providerResponse);
            }
            trafficCalls++;
            return traffic?.future ??
                Future.value(http.Response(
                    jsonEncode({
                      'connections': [],
                      'downloadTotal': trafficCalls * 100,
                      'uploadTotal': 0
                    }),
                    200));
          }),
        ));
  });
  tearDown(() => hub.dispose());

  test(
      '60 seconds of polling preserves traffic cadence with two provider reads',
      () async {
    for (var second = 0; second < 60; second++) {
      now = DateTime(2026).add(Duration(seconds: second));
      await hub.refresh();
      await Future<void>.delayed(Duration.zero);
    }
    expect(trafficCalls, 60);
    expect(providerCalls, 2);
    expect(hub.snapshot!.downloadSpeed, 100);
  });

  test(
      'slow subscription endpoint cannot block live traffic or advance samples',
      () async {
    providers = Completer<http.Response>();
    final first = await hub.refresh().timeout(const Duration(seconds: 1));
    now = now.add(const Duration(seconds: 1));
    final next = await hub.refresh();
    expect(providerCalls, 1);
    expect(next.downloadSpeed, 100);
    providers!.complete(providerResponse);
    await Future<void>.delayed(Duration.zero);
    expect(hub.snapshot!.sequence, next.sequence);
    expect(hub.snapshot!.updatedAt, next.updatedAt);
    expect(hub.snapshot!.providers.single.name, 'subscription');
    expect(first.providers, isEmpty);
  });

  test('native list can skip providers and explicit refresh bypasses interval',
      () async {
    await hub.refresh(includeProviders: false);
    expect(providerCalls, 0);
    await hub.refresh(force: true);
    await Future<void>.delayed(Duration.zero);
    await hub.refresh(force: true);
    expect(providerCalls, 2);
  });

  test('summary polling preserves totals without caching connection rows',
      () async {
    traffic = Completer<http.Response>()
      ..complete(http.Response(
          '{"connections":[{"id":"one"}],"downloadTotal":100,"uploadTotal":20}',
          200));
    final summary =
        await hub.refresh(includeConnections: false, includeProviders: false);
    expect(summary.hasConnectionDetails, isFalse);
    expect(summary.connections, isEmpty);
    expect(summary.activeConnections, 1);
    expect(summary.downloadTotal, 100);
    expect(summary.uploadTotal, 20);

    final detail = await hub.refresh(includeProviders: false);
    expect(detail.hasConnectionDetails, isTrue);
    expect(detail.connections.single.id, 'one');
    expect(trafficCalls, 2);
    expect(
        await hub.refresh(includeConnections: false, includeProviders: false),
        same(detail));
    expect(trafficCalls, 2);
  });

  test('a list opened during a summary poll shares one follow-up detail read',
      () async {
    traffic = Completer<http.Response>();
    final summary =
        hub.refresh(includeConnections: false, includeProviders: false);
    final detail = hub.refresh(includeProviders: false);
    final secondDetail = hub.refresh(includeProviders: false);
    await Future<void>.delayed(Duration.zero);
    expect(trafficCalls, 1);
    traffic!.complete(http.Response('{"connections":[{"id":"one"}]}', 200));

    expect((await summary).hasConnectionDetails, isFalse);
    final detailed = await detail;
    expect(detailed.hasConnectionDetails, isTrue);
    expect(detailed.connections.single.id, 'one');
    expect(await secondDetail, same(detailed));
    expect(trafficCalls, 2);
  });

  test('reset rejects in-flight traffic and subscription replies', () async {
    providers = Completer<http.Response>();
    traffic = Completer<http.Response>();
    final old = hub.refresh();
    final failure = expectLater(old, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    hub.resetBaseline(clearSnapshot: true);
    providers!.complete(providerResponse);
    traffic!.complete(http.Response('{"connections":[]}', 200));
    await failure;
    await Future<void>.delayed(Duration.zero);
    expect(hub.snapshot, isNull);
    providers = traffic = null;
    await hub.refresh();
    expect(hub.snapshot!.downloadSpeed, 0);
    expect(providerCalls, 2);
  });
}
