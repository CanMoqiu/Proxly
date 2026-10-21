import 'package:flutter/material.dart';
import '../../l10n/app_locale.dart';
import '../../services/dashboard_layout_store.dart';
import '../../theme/app_theme.dart';
import '../adaptive_ui.dart';
import 'dashboard_card_titles.dart';
import 'dashboard_button_style.dart';
import 'dashboard_reorderable_list.dart';

class DashboardCardList extends StatefulWidget {
  final DashboardLayoutStore layout;
  final Map<DashboardCardId, Widget> cards;
  final bool editing;
  final VoidCallback onEditPressed;
  final void Function(Future<void>) onSave;
  const DashboardCardList(
      {super.key,
      required this.layout,
      required this.cards,
      required this.editing,
      required this.onEditPressed,
      required this.onSave});

  @override
  State<DashboardCardList> createState() => _DashboardCardListState();
}

class _DashboardCardListState extends State<DashboardCardList> {
  final _scrollController = ScrollController();
  int _footerRevealGeneration = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DashboardCardList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editing != widget.editing) _revealFooter();
  }

  void _revealFooter() {
    final generation = ++_footerRevealGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _footerRevealGeneration ||
          !_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final editing = widget.editing;
    final ids = editing ? layout.order : layout.visible;
    final palette = AppPalette.of(context);
    return DashboardReorderableList(
      editing: editing,
      controller: _scrollController,
      padding: AdaptiveScrollPadding.page(context, top: 16),
      onReorder: (oldIndex, newIndex) {
        if (editing) widget.onSave(layout.reorder(oldIndex, newIndex));
      },
      footer: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          if (editing) ...[
            Text(tr('长按卡片拖动排序，关闭开关隐藏卡片'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: palette.textSecondary)),
            const SizedBox(height: DashboardButtonStyle.spacing),
            TextButton(
                style: DashboardButtonStyle.action,
                onPressed: () {
                  widget.onSave(layout.reset());
                  _revealFooter();
                },
                child: Text(tr('恢复默认'))),
            const SizedBox(height: DashboardButtonStyle.spacing),
          ],
          if (ids.isEmpty)
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(tr('卡片已隐藏，点击下方自定义首页以恢复。'),
                    textAlign: TextAlign.center)),
          TextButton.icon(
            key: const ValueKey('home_customize_button'),
            onPressed: widget.onEditPressed,
            style: DashboardButtonStyle.action,
            icon: Icon(
                editing
                    ? Icons.check_rounded
                    : Icons.dashboard_customize_outlined,
                size: DashboardButtonStyle.iconSize),
            label: Text(tr(editing ? '完成' : '自定义首页')),
          ),
        ]),
      ),
      children: [
        for (var index = 0; index < ids.length; index++)
          Padding(
              key: ValueKey('dashboard_${ids[index].name}'),
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (editing)
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(children: [
                            Expanded(
                                child: Text(dashboardCardTitle(ids[index]),
                                    style: const TextStyle(fontSize: 13))),
                            Switch(
                                key: ValueKey('visible_${ids[index].name}'),
                                value: layout.isVisible(ids[index]),
                                onChanged: (value) => widget.onSave(
                                    layout.setVisible(ids[index], value))),
                          ])),
                    if (layout.isVisible(ids[index]))
                      if (!editing)
                        widget.cards[ids[index]]!
                      else
                        AbsorbPointer(child: widget.cards[ids[index]]!),
                  ])),
      ],
    );
  }
}
