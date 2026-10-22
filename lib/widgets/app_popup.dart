import 'package:flutter/material.dart';

/// Owns presentation only; callers retain operation and authentication state.
abstract final class AppPopup {
  static final Set<Object> _presenting = {};
  static const _animation = AnimationStyle(
    duration: Duration(milliseconds: 220),
    reverseDuration: Duration(milliseconds: 160),
    curve: Curves.easeOutCubic,
  );

  static void close<T>(BuildContext context, [T? result]) {
    // A second tap during exit must not pop the page beneath the popup.
    if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) return;
    Navigator.of(context).pop<T>(result);
  }

  static Future<T?> dialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) =>
      _present(
          context,
          (navigator) => DialogRoute<T>(
                context: context,
                builder: builder,
                themes: InheritedTheme.capture(
                    from: context, to: navigator.context),
                barrierDismissible: barrierDismissible,
                animationStyle: _animation,
              ));

  static Future<T?> sheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) =>
      _present(
          context,
          (navigator) => ModalBottomSheetRoute<T>(
                builder: (context) =>
                    SafeArea(top: false, child: builder(context)),
                capturedThemes: InheritedTheme.capture(
                    from: context, to: navigator.context),
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                barrierLabel:
                    MaterialLocalizations.of(context).modalBarrierDismissLabel,
                backgroundColor: Theme.of(context).colorScheme.surface,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                clipBehavior: Clip.antiAlias,
                constraints: BoxConstraints(
                  maxWidth: 560,
                  maxHeight: MediaQuery.sizeOf(context).height * .85,
                ),
                sheetAnimationStyle: _animation,
              ));

  static Future<T?> _present<T>(BuildContext context,
      TransitionRoute<T> Function(NavigatorState) createRoute) async {
    final Object owner = context;
    if (!context.mounted || !_presenting.add(owner)) return null;
    try {
      final navigator = Navigator.of(context, rootNavigator: true);
      final route = createRoute(navigator);
      final result = await navigator.push<T>(route);
      // Wait for the overlay to leave before opening a picker or confirmation.
      await route.completed;
      return result;
    } finally {
      _presenting.remove(owner);
    }
  }
}

class AppDialog extends StatelessWidget {
  final Widget title;
  final Widget content;
  final List<Widget> actions;

  const AppDialog(
      {super.key,
      required this.title,
      required this.content,
      required this.actions});

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: title,
        content: content,
        scrollable: true,
        constraints: const BoxConstraints(maxWidth: 400),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: actions.length > 2
            ? [
                Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final action in actions)
                        Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: action),
                    ])
              ]
            : actions,
      );
}

class AppSheetOption<T> {
  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final bool enabled;
  final bool destructive;

  const AppSheetOption(
      {required this.value,
      required this.label,
      this.subtitle,
      this.icon,
      this.enabled = true,
      this.destructive = false});
}

class AppOptionsSheet<T> extends StatelessWidget {
  final String title;
  final String? description;
  final List<AppSheetOption<T>> options;
  final T? selectedValue;

  const AppOptionsSheet(
      {super.key,
      required this.title,
      required this.options,
      this.description,
      this.selectedValue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
        top: false,
        child: Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          if (description != null) ...[
                            const SizedBox(height: 4),
                            Text(description!,
                                style: theme.textTheme.bodySmall),
                          ],
                        ])),
                Flexible(
                    child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    for (final option in options) ...[
                      if (option.destructive)
                        const Divider(indent: 20, endIndent: 20),
                      ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        enabled: option.enabled,
                        selected: selectedValue == option.value,
                        textColor:
                            option.destructive ? theme.colorScheme.error : null,
                        iconColor:
                            option.destructive ? theme.colorScheme.error : null,
                        leading: option.icon == null ? null : Icon(option.icon),
                        title: Text(option.label),
                        subtitle: option.subtitle == null
                            ? null
                            : Text(option.subtitle!),
                        trailing: selectedValue == option.value
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: option.enabled
                            ? () => AppPopup.close(context, option.value)
                            : null,
                      ),
                    ]
                  ],
                )),
              ]),
        ));
  }
}
