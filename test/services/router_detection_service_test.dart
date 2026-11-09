import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxly/services/router_detection_service.dart';
import 'package:proxly/services/router_tool.dart';

void main() {
  test('Mihomo API alone does not imply OpenClash', () async {
    final service = RouterDetectionService(
        client: MockClient((request) async {
          expect(request.followRedirects, isFalse);
          expect(request.headers['Authorization'], 'Bearer test');
          return http.Response(
              jsonEncode({'meta': true, 'version': 'v1'}), 200);
        }),
        ssh: (host, password, port, command) async =>
            throw StateError('Must not use SSH'));
    final result = await service.detect(
        host: 'router.local:9090', token: 'test', sshPassword: '', sshPort: 22);
    expect(result.tool, RouterTool.generic);
    expect(result.core, ProxyCore.mihomo);
    expect(result.sshChecked, isFalse);
  });
  test('running service on selected API and custom SSH port selects Nikki',
      () async {
    final service = RouterDetectionService(
        client: MockClient(
            (_) async => http.Response('{"meta":true,"version":"v1"}', 200)),
        ssh: (host, password, port, command) async {
          expect(host, '192.168.1.1');
          expect(port, 2222);
          expect(command, contains('requested_port=9095'));
          expect(command, contains('running >/dev/null'));
          expect(command, contains('nikki.mixin.api_listen'));
          expect(command, isNot(contains('api_secret')));
          return 'nikki=running\n';
        });
    final result = await service.detect(
        host: '192.168.1.1:9095',
        token: '',
        sshPassword: 'secret',
        sshPort: 2222);
    expect(result.tool, RouterTool.nikki);
  });
  test('ambiguous services and SSH errors fall back to API-only', () async {
    for (final output in [
      'openclash=running\nnikki=running',
      'openclash=installed'
    ]) {
      final service = RouterDetectionService(
          client:
              MockClient((_) async => http.Response('{"version":"v1"}', 200)),
          ssh: (host, password, port, command) async => output);
      final result = await service.detect(
          host: 'router.local:9090', token: '', sshPassword: 'p', sshPort: 22);
      expect(result.tool, RouterTool.generic);
      expect(result.ambiguous, output.contains('nikki=running'));
    }
    final result = await RouterDetectionService(
        client: MockClient((_) async => http.Response('{"version":"v1"}', 200)),
        ssh: (host, password, port, command) async =>
            throw StateError('denied')).detect(
        host: 'router.local:9090', token: '', sshPassword: 'p', sshPort: 22);
    expect(result.tool, RouterTool.generic);
  });
  test('invalid or unauthorized controller cannot select a router adapter',
      () async {
    for (final response in [
      http.Response('bad', 200),
      http.Response('{}', 200),
      http.Response('', 401),
      http.Response('', 302, headers: {'location': 'http://example.com'})
    ]) {
      var sshCalled = false;
      final service = RouterDetectionService(
          client: MockClient((_) async => response),
          ssh: (host, password, port, command) async {
            sshCalled = true;
            return 'nikki=running';
          });
      await expectLater(
          service.detect(
              host: 'router.local:9090',
              token: 's',
              sshPassword: 'p',
              sshPort: 22),
          throwsA(anything));
      expect(sshCalled, isFalse);
    }
  });
}
