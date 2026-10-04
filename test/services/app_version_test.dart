import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/app_version.dart';
import 'package:proxly/services/version_comparator.dart';

void main() {
  test('release labels omit the test zero and internal build number', () {
    expect(displayAppVersion('27.3.0+35'), '27.3');
    expect(displayAppVersion('v27.3.0'), '27.3');
    expect(displayAppVersion('27.3.2+35'), '27.3.2');
    expect(isTestAppVersion('27.3.2+35'), isTrue);
    expect(isTestAppVersion('27.3.0+35'), isFalse);
  });

  test('next formal release supersedes tests and the year resets the counter',
      () {
    expect(compareNumericVersions('27.4.0', '27.3.99'), greaterThan(0));
    expect(compareNumericVersions('27.1.0', '26.99.9'), greaterThan(0));
    expect(compareNumericVersions('27.3', '27.3.0'), 0);
  });
}
