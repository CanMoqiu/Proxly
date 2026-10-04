import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/version_comparator.dart';

void main() {
  test('compares numeric segments instead of lexical text', () {
    expect(compareNumericVersions('26.10', '26.9'), greaterThan(0));
    expect(compareNumericVersions('v26.3.11', '26.3.2'), greaterThan(0));
    expect(compareNumericVersions('26.3.2', 'v26.3.11'), lessThan(0));
  });

  test('treats missing segments as zero', () {
    expect(compareNumericVersions('26.3', '26.3.0'), 0);
    expect(compareNumericVersions('v26', '26.0.0'), 0);
    expect(compareNumericVersions('26.3.0.1', '26.3'), greaterThan(0));
  });

  test('rejects malformed version tags', () {
    for (final value in [
      '',
      'release-26.3',
      '26.3-beta',
      '26..3',
      '999999999999999999999999999999',
    ]) {
      expect(compareNumericVersions(value, '26.3'), isNull);
    }
  });
}
