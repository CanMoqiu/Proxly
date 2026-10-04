import 'dart:convert';
import 'dart:typed_data';

class ZashboardConfigValidator {
  ZashboardConfigValidator._();

  static const maxBytes = 5 * 1024 * 1024;
  static const maxKeys = 2000;
  static const maxValueBytes = 1024 * 1024;

  static Future<Uint8List> readBounded(
    Stream<List<int>> stream, {
    int? reportedSize,
  }) async {
    if (reportedSize != null && reportedSize > maxBytes) {
      throw const FormatException('配置文件超过 5 MB，无法导入');
    }

    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in stream) {
      received += chunk.length;
      if (received > maxBytes) {
        throw const FormatException('配置文件超过 5 MB，无法导入');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static void validateStructure(Map<dynamic, dynamic> decoded) {
    if (decoded.length > maxKeys) {
      throw const FormatException('配置项超过 2000 个，无法导入');
    }
    for (final entry in decoded.entries) {
      final valueBytes = utf8.encode(jsonEncode(entry.value)).length;
      if (valueBytes > maxValueBytes) {
        throw FormatException('配置项 ${entry.key} 超过 1 MB，无法导入');
      }
    }
  }
}
