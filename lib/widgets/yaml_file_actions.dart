import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../services/clash_config_file_service.dart';
import 'yaml_file_dialogs.dart';

class YamlFileActions {
  Future<ClashConfigFile?> upload(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
        withReadStream: true,
        dialogTitle: tr('选择 YAML 配置文件'));
    if (!context.mounted || result == null || result.files.isEmpty) return null;
    final picked = result.files.first;
    if (!ClashConfigFileService.isYamlPath(picked.name)) {
      throw const FormatException('请选择 .yaml 或 .yml 文件');
    }
    final bytes = await readPickedFileBytes(picked);
    if (!context.mounted) return null;
    final name = await showDialog<String>(
        context: context,
        builder: (_) => YamlUploadFileNameDialog(initialValue: picked.name));
    if (!context.mounted || name == null) return null;
    final path = ClashConfigFileService.uploadPathForFileName(name);
    final files = await ClashConfigFileService.listFiles();
    if (!context.mounted) return null;
    if (files.any((file) => file.path == path)) {
      final overwrite = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: Text(tr('覆盖已有配置？')),
                  content: Text(name),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(tr('取消'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(tr('覆盖'))),
                  ]));
      if (!context.mounted || overwrite != true) return null;
    }
    await ClashConfigFileService.writeFileBytes(path, bytes);
    return ClashConfigFile(path: path);
  }

  static Future<Uint8List> readPickedFileBytes(PlatformFile picked) async {
    const limit = ClashConfigFileService.maxConfigBytes;
    if (picked.size > limit) throw const FormatException('文件超过 5 MB 限制');
    final bytes = picked.bytes;
    if (bytes != null) {
      if (bytes.length > limit) throw const FormatException('文件超过 5 MB 限制');
      return bytes;
    }
    final stream = picked.readStream;
    if (stream != null) {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        if (builder.length + chunk.length > limit) {
          throw const FormatException('文件超过 5 MB 限制');
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    }
    final path = picked.path;
    if (path == null) throw const FormatException('读取本地文件失败');
    // Stream fallback paths too: a file can grow after the picker reports its size.
    return readPickedFileBytes(PlatformFile(
        name: picked.name,
        size: picked.size,
        readStream: File(path).openRead()));
  }

  Future<ClashConfigFile?> rename(
      BuildContext context, ClashConfigFile file) async {
    final name = await showDialog<String>(
        context: context,
        builder: (_) => YamlFileNameDialog(
            title: '重命名',
            confirmText: '确认',
            description: '所在目录：${file.directory}',
            initialValue: file.name,
            fieldKey: const ValueKey('yaml_rename_file_name'),
            showFieldTitle: false));
    if (!context.mounted || name == null || name == file.name) return null;
    final active = await ClashConfigFileService.getActiveConfig();
    final activePath =
        ClashConfigFileService.matchActiveConfigPath([file], active);
    return ClashConfigFileService.renameFile(file.path, name,
        updateActiveReference: activePath == file.path);
  }

  Future<bool> export(
      BuildContext context, ClashConfigFile file, String content) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    if (bytes.length > ClashConfigFileService.maxConfigBytes) {
      throw const FormatException('文件超过 5 MB 限制');
    }
    final path = await FilePicker.platform.saveFile(
        dialogTitle: tr('导出配置'),
        fileName: file.name,
        type: FileType.custom,
        allowedExtensions: const ['yaml', 'yml'],
        bytes: bytes);
    return path != null;
  }
}
