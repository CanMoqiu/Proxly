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
  final Set<DashboardCardId> unavailable;
  final Widget? sshTrustNotice;
  final VoidCallback onEditPressed;
  final void Function(Future<void>) onSave;
  const DashboardCardList(
      {super.key,
      required this.layout,
      required this.cards,
      required this.editing,
      this.unavailable = const {},
      this.sshTrustNotice,
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
    const sshCards = {
      DashboardCardId.currentYaml,
      DashboardCardId.operations,
      DashboardCardId.quickSettings
    };
    final unavailable = {
      ...widget.unavailable,
      if (widget.sshTrustNotice != null) ...sshCards,
    };
    final hidden = DashboardCardId.values.where((id) => !layout.isVisible(id));
    final excluded = {...unavailable, ...hidden};
    final ids = layout.availableOrder(unavailable: excluded);
    final addable = hidden.where((id) => !unavailable.contains(id));
    final palette = AppPalette.of(context);
    return AdaptiveContent(
        maxWidth: 1152,
        child: DashboardReorderableList(
          editing: editing,
          controller: _scrollController,
          padding: AdaptiveScrollPadding.page(context, top: 24),
          onReorder: (oldIndex, newIndex) {
            if (editing) {
              widget.onSave(
                  layout.reorder(oldIndex, newIndex, unavailable: excluded));
            }
          },
          footer: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              if (widget.sshTrustNotice != null) ...[
                widget.sshTrustNotice!,
                const SizedBox(height: 12),
              ],
              if (editing) ...[
                if (addable.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(tr('可添加功能'),
                          style: Theme.of(context).textTheme.titleSmall),
                      for (final id in addable)
                        TextButton.icon(
                          key: ValueKey('add_${id.name}'),
                          style: TextButton.styleFrom(
                              alignment: Alignment.centerLeft),
                          icon: const Icon(Icons.add_rounded),
                          label: Text(dashboardCardTitle(id)),
                          onPressed: () =>
                              widget.onSave(layout.setVisible(id, true)),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                if (ids.length > 1)
                  Text(tr('长按卡片拖动排序'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: palette.textSecondary)),
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
              if (!editing && ids.isEmpty)
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
            for (final id in ids)
              Padding(
                  key: ValueKey('dashboard_${id.name}'),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: editing
                      ? Stack(fit: StackFit.passthrough, children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: AbsorbPointer(child: widget.cards[id]!),
                          ),
                          Positioned(
                              top: 0,
                              right: 0,
                              child: IconButton(
                                key: ValueKey('visible_${id.name}'),
                                tooltip:
                                    '${tr('隐藏')} ${dashboardCardTitle(id)}',
                                onPressed: () =>
                                    widget.onSave(layout.setVisible(id, false)),
                                icon: CircleAvatar(
                                  radius: 12,
                                  backgroundColor: palette.error,
                                  child: const Icon(Icons.remove_rounded,
                                      size: 20, color: Colors.white),
                                ),
                              )),
                        ])
                      : widget.cards[id]!),
          ],
        ));
  }
}
