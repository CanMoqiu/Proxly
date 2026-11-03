import 'dart:async';
import 'package:flutter/material.dart';

/// Rechecks the caret after the keyboard and viewport finish moving.
class KeyboardFocusReveal extends StatefulWidget {
  const KeyboardFocusReveal({super.key, required this.child});
  final Widget child;

  @override
  State<KeyboardFocusReveal> createState() => _KeyboardFocusRevealState();
}

class _KeyboardFocusRevealState extends State<KeyboardFocusReveal>
    with WidgetsBindingObserver {
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_schedule);
  }

  @override
  void didChangeMetrics() => _schedule();

  void _schedule() {
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 220), () {
      if (!mounted || MediaQuery.viewInsetsOf(context).bottom == 0) return;
      final focus = FocusManager.instance.primaryFocus;
      final focusContext = focus?.context;
      if (focusContext == null || !focusContext.mounted) return;
      final editor = focusContext.findAncestorStateOfType<EditableTextState>();
      if (editor == null || !editor.widget.controller.selection.isValid) return;
      editor.bringIntoView(editor.widget.controller.selection.extent);
      // Caret visibility alone can leave the field's border and label covered.
      // Keep multiline editors focused on the caret instead of scrolling the
      // entire editor surface into view.
      if (editor.widget.maxLines == 1) {
        focusContext.visitAncestorElements((element) {
          if (element.widget is! TextField) return true;
          unawaited(Scrollable.ensureVisible(element,
              alignment: 1,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
              duration: const Duration(milliseconds: 160)));
          return false;
        });
      }
    });
  }

  @override
  void dispose() {
    _settle?.cancel();
    FocusManager.instance.removeListener(_schedule);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
