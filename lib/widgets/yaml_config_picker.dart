import 'package:flutter/material.dart';
import '../l10n/app_locale.dart';
import '../theme/app_theme.dart';
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintColor = AppPalette.of(context).textSecondary;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('选择 YAML 配置'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr(activate
                  ? '选择后会写入 OpenClash 当前配置，并在确认后重启。'
                  : '选择要编辑的文件，不改变当前运行配置。'),
              style: TextStyle(fontSize: 12, color: hintColor),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.55,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: files.length,
                separatorBuilder: (_, __) => Divider(
                  height: 0,
                  color: theme.dividerColor.withValues(alpha: 0.5),
                ),
                itemBuilder: (context, index) {
                  final file = files[index];
                  final selected = file.path == activePath;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected ? theme.colorScheme.primary : hintColor,
                    ),
                    title: Text(
                      file.name,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      file.displayPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: hintColor),
                    ),
                    onTap: () => Navigator.of(context).pop(file),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
