import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/clash_config_file_service.dart';
import 'package:proxly/widgets/yaml_file_actions.dart';

void main() {
  test('uploads bound actual bytes even when picker size metadata is incorrect',
      () async {
    const limit = ClashConfigFileService.maxConfigBytes;
    final oversized = Uint8List(limit + 1);
    await expectLater(
        YamlFileActions.readPickedFileBytes(
            PlatformFile(name: 'a.yaml', size: 1, bytes: oversized)),
        throwsFormatException);
    await expectLater(
        YamlFileActions.readPickedFileBytes(PlatformFile(
            name: 'a.yaml',
            size: 1,
            readStream: Stream.fromIterable([Uint8List(limit), Uint8List(1)]))),
        throwsFormatException);
    expect(
        await YamlFileActions.readPickedFileBytes(PlatformFile(
            name: 'a.yaml', size: 2, readStream: Stream.value([65, 66]))),
        [65, 66]);
  });
}
