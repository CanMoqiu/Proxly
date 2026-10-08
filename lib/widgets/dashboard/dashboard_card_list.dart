import 'package:flutter/material.dart';
import '../../l10n/app_locale.dart';
import '../../services/dashboard_layout_store.dart';
import '../../theme/app_theme.dart';
import '../adaptive_ui.dart';

String dashboardCardTitle(DashboardCardId id) => tr(switch (id) {
      DashboardCardId.status => 'Clash 状态',
      DashboardCardId.currentYaml => '当前 YAML',
      DashboardCardId.operations => 'Clash 操作',
      DashboardCardId.quickSettings => '快捷设置',
      DashboardCardId.traffic => '流量信息',
      DashboardCardId.overview => '运行概览',
    });

class DashboardCardList extends StatelessWidget {
  final DashboardLayoutStore layout;
  final Map<DashboardCardId, Widget> cards;
  final bool editing;
  final void Function(Future<void>) onSave;
  const DashboardCardList(
      {super.key,
      required this.layout,
      required this.cards,
      required this.editing,
      required this.onSave});

  @override
  Widget build(BuildContext context) {
    final ids = editing ? layout.order : layout.visible;
    final palette = AppPalette.of(context);
    return ReorderableListView(
      key: const PageStorageKey('home_dashboard_scroll'),
      physics: const ClampingScrollPhysics(),
      padding: AdaptiveScrollPadding.page(context, top: 16),
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) {
        if (editing) onSave(layout.reorder(oldIndex, newIndex));
      },
      header: editing
          ? Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Expanded(
                    child: Text(tr('拖动手柄排序，关闭开关隐藏卡片'),
                        style: TextStyle(
                            fontSize: 12, color: palette.textSecondary))),
                TextButton(
                    onPressed: () => onSave(layout.reset()),
                    child: Text(tr('恢复默认'))),
              ]))
          : null,
      footer: ids.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child:
                  Text(tr('卡片已隐藏，点击右上角自定义首页以恢复。'), textAlign: TextAlign.center))
          : null,
      children: [
        for (var index = 0; index < ids.length; index++)
          Padding(
              key: ValueKey('dashboard_${ids[index].name}'),
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (editing)
                      Row(children: [
                        ReorderableDragStartListener(
                            index: index,
                            child: Semantics(
                                label: tr('拖动排序'),
                                button: true,
                                child: SizedBox(
                                    key: ValueKey('drag_${ids[index].name}'),
                                    width: 48,
                                    height: 48,
                                    child: Icon(Icons.drag_handle_rounded,
                                        color: palette.textSecondary)))),
                        Expanded(
                            child: Text(dashboardCardTitle(ids[index]),
                                style: const TextStyle(fontSize: 13))),
                        Switch(
                            key: ValueKey('visible_${ids[index].name}'),
                            value: layout.isVisible(ids[index]),
                            onChanged: (value) =>
                                onSave(layout.setVisible(ids[index], value))),
                      ]),
                    if (layout.isVisible(ids[index])) cards[ids[index]]!,
                  ])),
      ],
    );
  }
}
