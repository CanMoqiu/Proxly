import 'package:flutter/material.dart';
import '../l10n/app_locale.dart';
import 'app_popup.dart';
import '../services/clash_config_file_service.dart';

class YamlConfigPickerSheet extends StatelessWidget {
  final List<ClashConfigFile> files;
  final String? activePath;
  final bool activate;

  const YamlConfigPickerSheet(
      {super.key,
      required this.files,
      required this.activePath,
      this.activate = true});

  @override
  Widget build(BuildContext context) => AppOptionsSheet<ClashConfigFile>(
        title: tr('选择 YAML 配置'),
        description: tr(activate
            ? '选择后会写入 OpenClash 当前配置，并在确认后重启。'
            : '选择要编辑的文件，不改变当前运行配置。'),
        selectedValue:
            files.where((file) => file.path == activePath).firstOrNull,
        options: [
          for (final file in files)
            AppSheetOption(
                value: file,
                label: file.name,
                subtitle: file.displayPath,
                icon: Icons.description_outlined),
        ],
      );
}
