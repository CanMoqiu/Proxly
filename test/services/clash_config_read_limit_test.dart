import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/clash_config_file_service.dart';

void main() {
  test('YAML reads accept the exact byte limit', () async {
    final bytes = Uint8List(ClashConfigFileService.maxConfigBytes);
    final result =
        await ClashConfigFileService.readBoundedConfig(Stream.value(bytes));
    expect(result.length, bytes.length);
  });

  test(
      'YAML reads stop at the first oversized chunk without consuming the rest',
      () async {
    var consumedTail = false;
    var closed = false;
    Stream<Uint8List> growingFile() async* {
      try {
        yield Uint8List(ClashConfigFileService.maxConfigBytes);
        yield Uint8List(1);
        consumedTail = true;
        yield Uint8List(1024);
      } finally {
        closed = true;
      }
    }

    await expectLater(ClashConfigFileService.readBoundedConfig(growingFile()),
        throwsException);
    expect(consumedTail, isFalse);
    expect(closed, isTrue);
  });

  test('a single oversized response is rejected before it is copied', () async {
    await expectLater(
        ClashConfigFileService.readBoundedConfig(
            Stream.value(Uint8List(ClashConfigFileService.maxConfigBytes + 1))),
        throwsException);
  });
}
