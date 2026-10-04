import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('automatic update checks default to enabled and persist changes',
      () async {
    SharedPreferences.setMockInitialValues({});

    expect(await UpdateService.instance.isAutomaticCheckEnabled(), isTrue);

    await UpdateService.instance.setAutomaticCheckEnabled(false);

    expect(await UpdateService.instance.isAutomaticCheckEnabled(), isFalse);
    expect(
      await UpdateService.instance.checkForUpdate(silent: true),
      isNull,
    );
  });
}
