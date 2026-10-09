import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_locale.dart';
import '../../services/dashboard_layout_store.dart';
import '../../theme/app_theme.dart';
import '../adaptive_ui.dart';
import 'dashboard_card_titles.dart';

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
      onReorderStart: (_) => HapticFeedback.mediumImpact(),
      proxyDecorator: (child, index, animation) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final progress = Curves.easeOut.transform(animation.value);
          return Transform.scale(
            key: const ValueKey('dashboard_drag_feedback'),
            scale: 1 + 0.02 * progress,
            child: Material(
              color: palette.surface,
              elevation: 8 * progress,
              shadowColor: Colors.black.withValues(alpha: 0.25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: progress)),
              ),
              child: child,
            ),
          );
        },
      ),
      onReorderItem: (oldIndex, newIndex) {
        if (editing) onSave(layout.reorder(oldIndex, newIndex));
      },
      header: editing
          ? Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Expanded(
                    child: Text(tr('长按卡片拖动排序，关闭开关隐藏卡片'),
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
          ReorderableDelayedDragStartListener(
              key: ValueKey('dashboard_${ids[index].name}'),
              index: index,
              enabled: editing,
              child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (editing)
                          Row(children: [
                            Expanded(
                                child: Text(dashboardCardTitle(ids[index]),
                                    style: const TextStyle(fontSize: 13))),
                            Switch(
                                key: ValueKey('visible_${ids[index].name}'),
                                value: layout.isVisible(ids[index]),
                                onChanged: (value) => onSave(
                                    layout.setVisible(ids[index], value))),
                          ]),
                        if (layout.isVisible(ids[index])) cards[ids[index]]!,
                      ]))),
      ],
    );
  }
}
