import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/utils/traffic_formatter.dart';

void main() {
  group('TrafficFormatter', () {
    test('formats byte units from B through TB', () {
      expect(TrafficFormatter.formatBytes(0), '0B');
      expect(TrafficFormatter.formatBytes(1), '1B');
      expect(TrafficFormatter.formatBytes(1023), '1023B');
      expect(TrafficFormatter.formatBytes(1024), '1.0KB');
      expect(TrafficFormatter.formatBytes(1024 * 1024), '1.0MB');
      expect(TrafficFormatter.formatBytes(1024 * 1024 * 1024), '1.00GB');
      expect(
        TrafficFormatter.formatBytes(1024 * 1024 * 1024 * 1024),
        '1.00TB',
      );
    });

    test('formats speeds with the same unit ladder', () {
      expect(TrafficFormatter.formatSpeed(512), '512B/s');
      expect(TrafficFormatter.formatSpeed(1536), '1.5KB/s');
      expect(
        TrafficFormatter.formatSpeed(1024 * 1024 * 1024 * 1024),
        '1.00TB/s',
      );
    });
  });
}
