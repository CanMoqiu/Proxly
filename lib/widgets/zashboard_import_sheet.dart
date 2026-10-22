import 'package:flutter/material.dart';
import '../l10n/app_locale.dart';
import 'app_popup.dart';

enum ZashboardImportSource { core, file }

class ZashboardImportSheet extends StatelessWidget {
  const ZashboardImportSheet({super.key});

  @override
  Widget build(BuildContext context) => AppOptionsSheet<ZashboardImportSource>(
        title: tr('导入配置'),
        options: [
          AppSheetOption(
              value: ZashboardImportSource.core,
              label: tr('从内核导入'),
              icon: Icons.router_outlined),
          AppSheetOption(
              value: ZashboardImportSource.file,
              label: tr('从本地导入 JS 文件'),
              icon: Icons.upload_file_outlined,
              subtitle: tr('支持 Zashboard 导出的 JSON 配置（.json / .js）')),
        ],
      );
}
