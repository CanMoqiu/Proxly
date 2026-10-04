import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/zashboard_config_validator.dart';

void main() {
  test('bounded reader accepts data at the size limit', () async {
    final bytes = List<int>.filled(ZashboardConfigValidator.maxBytes, 1);
    final result = await ZashboardConfigValidator.readBounded(
      Stream.value(bytes),
      reportedSize: bytes.length,
    );
    expect(result.length, ZashboardConfigValidator.maxBytes);
  });

  test('bounded reader rejects reported and streamed overflow', () async {
    expect(
      () => ZashboardConfigValidator.readBounded(
        const Stream.empty(),
        reportedSize: ZashboardConfigValidator.maxBytes + 1,
      ),
      throwsFormatException,
    );
    expect(
      () => ZashboardConfigValidator.readBounded(
        Stream.fromIterable([
          List<int>.filled(ZashboardConfigValidator.maxBytes, 1),
          const [1],
        ]),
      ),
      throwsFormatException,
    );
  });

  test('structure validator enforces key and value limits', () {
    final tooManyKeys = {
      for (var i = 0; i <= ZashboardConfigValidator.maxKeys; i++) '$i': i,
    };
    expect(
      () => ZashboardConfigValidator.validateStructure(tooManyKeys),
      throwsFormatException,
    );

    final oversizedValue = 'a' * (ZashboardConfigValidator.maxValueBytes + 1);
    expect(utf8.encode(jsonEncode(oversizedValue)).length,
        greaterThan(ZashboardConfigValidator.maxValueBytes));
    expect(
      () => ZashboardConfigValidator.validateStructure(
        {'oversized': oversizedValue},
      ),
      throwsFormatException,
    );
  });
}
