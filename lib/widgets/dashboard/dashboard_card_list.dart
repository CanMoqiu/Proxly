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
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 10),
                        child: Text(tr('可添加功能'),
                            style: Theme.of(context).textTheme.titleSmall),
                      ),
                      for (final id in addable) ...[
                        _AddDashboardCard(
                          key: ValueKey('add_${id.name}'),
                          id: id,
                          onAdd: () =>
                              widget.onSave(layout.setVisible(id, true)),
                        ),
                        const SizedBox(height: DashboardButtonStyle.spacing),
                      ],
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
                                style: DashboardButtonStyle.icon,
                                alignment: Alignment.topRight,
                                padding: const EdgeInsets.only(right: 2),
                                tooltip:
                                    '${tr('隐藏')} ${dashboardCardTitle(id)}',
                                onPressed: () =>
                                    widget.onSave(layout.setVisible(id, false)),
                                icon: CircleAvatar(
                                  radius: 14,
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

class _AddDashboardCard extends StatelessWidget {
  const _AddDashboardCard({super.key, required this.id, required this.onAdd});

  final DashboardCardId id;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final title = dashboardCardTitle(id);
    final icon = switch (id) {
      DashboardCardId.status => Icons.monitor_heart_outlined,
      DashboardCardId.traffic => Icons.swap_vert_rounded,
      DashboardCardId.overview => Icons.bar_chart_rounded,
      DashboardCardId.currentYaml => Icons.description_outlined,
      DashboardCardId.operations => Icons.bolt_rounded,
      DashboardCardId.quickSettings => Icons.tune_rounded,
    };
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        child: Row(
          children: [
            IconButton(
              style: DashboardButtonStyle.icon,
              tooltip: '${tr('添加')} $title',
              onPressed: onAdd,
              icon: CircleAvatar(
                radius: 15,
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                child: const Icon(Icons.add_rounded, size: 20),
              ),
            ),
            const SizedBox(width: 2),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: palette.inputBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: palette.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
