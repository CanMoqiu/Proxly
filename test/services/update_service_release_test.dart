import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:proxly/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'Proxly',
        packageName: 'top.canmoqiu.proxly',
        version: '27.3.2',
        buildNumber: '35',
        buildSignature: '');
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    UpdateService.instance.availableUpdate.value = null;
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    test('$platform shares metadata checks, throttling, skip and opt-out',
        () async {
      debugDefaultTargetPlatformOverride = platform;
      var requests = 0;
      await http.runWithClient(() async {
        final service = UpdateService.instance;
        final update = await service.checkForUpdate(silent: true);
        expect(update, isNotNull);
        expect(update!.tag, 'v27.4.0');
        expect(
            update.releasePage.path, '/CanMoqiu/proxly/releases/tag/v27.4.0');
        expect(update.apkUrl.isEmpty, platform == TargetPlatform.iOS);
        expect(service.availableUpdate.value, same(update));
        expect(await service.checkForUpdate(silent: true), isNull);
        expect(requests, 1);
        await service.skipVersion(update.tag);
        expect(await service.checkForUpdate(silent: false), isNull);
        expect(requests, 2);
        await service.setAutomaticCheckEnabled(false);
        expect(await service.checkForUpdate(silent: true), isNull);
        expect(requests, 2);
      },
          () => MockClient((request) async {
                requests++;
                expect(request.url.host, 'api.github.com');
                expect(
                    request.url.path, '/repos/CanMoqiu/proxly/releases/latest');
                // An iOS-only release must still be detectable without an APK asset.
                final ext = platform == TargetPlatform.iOS ? 'ipa' : 'apk';
                return http.Response(
                    jsonEncode({
                      'tag_name': 'v27.4.0',
                      'body': 'Updates',
                      'assets': [
                        {
                          'name': 'Proxly-mobile-27.4.$ext',
                          'browser_download_url':
                              'https://github.com/CanMoqiu/proxly/releases/download/v27.4.0/app.$ext'
                        }
                      ],
                    }),
                    200);
              }));
    });
  }
}
