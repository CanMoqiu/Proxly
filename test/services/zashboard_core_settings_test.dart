import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxly/services/zashboard_core_settings.dart';
import 'package:proxly/services/zashboard_config_validator.dart';

void main() {
  final endpoint = Uri.parse('http://127.0.0.1:1234/bridge/storage/zashboard');
  test('uses the core storage API without following redirects', () async {
    final raw = await ZashboardCoreSettings.read(endpoint,
        client: MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url, endpoint);
      expect(request.followRedirects, isFalse);
      return http.Response('{"config/proxy-sort":"name"}', 200);
    }));
    expect(raw, contains('proxy-sort'));
  });
  for (final code in [302, 401, 404, 405, 500]) {
    test('reports unsupported or failed core API $code', () async {
      await expectLater(
          ZashboardCoreSettings.read(endpoint,
              client: MockClient((_) async => http.Response('error', code))),
          throwsFormatException);
    });
  }
  test('rejects non-object or oversized settings', () async {
    for (final raw in [
      '[]',
      'not JSON',
      '{"x":"${'a' * ZashboardConfigValidator.maxBytes}"}'
    ]) {
      await expectLater(
          ZashboardCoreSettings.read(endpoint,
              client: MockClient((_) async => http.Response(raw, 200))),
          throwsFormatException);
    }
  });
}
