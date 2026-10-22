import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// Reorders the small dashboard without limiting the height of its cards.
class DashboardReorderableList extends StatefulWidget {
  final bool editing;
  final ScrollController controller;
  final EdgeInsetsGeometry padding;
  final List<Widget> children;
  final Widget footer;
  final void Function(int oldIndex, int newIndex) onReorder;

  const DashboardReorderableList({
    super.key,
    required this.editing,
    required this.controller,
    required this.padding,
    required this.children,
    required this.footer,
    required this.onReorder,
  });

  @override
  State<DashboardReorderableList> createState() =>
      _DashboardReorderableListState();
}

class _DashboardReorderableListState extends State<DashboardReorderableList>
    with SingleTickerProviderStateMixin {
  final _viewportKey = GlobalKey();
  final _itemKeys = <Key, GlobalKey>{};
  late final Ticker _ticker = createTicker(_scrollDuringDrag);
  Duration _lastTick = Duration.zero;
  int? _dragIndex;
  int _dropIndex = 0;
  Offset _pointer = Offset.zero;
  Offset _dragOrigin = Offset.zero;
  bool _hasMoved = false;
  Offset _anchor = Offset.zero;
  Size _dragSize = Size.zero;
  bool _animateReorder = false;

  @override
  void didUpdateWidget(covariant DashboardReorderableList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editing != widget.editing) _animateReorder = false;
    final index = _dragIndex;
    if (index != null &&
        (!widget.editing ||
            index >= widget.children.length ||
            oldWidget.children[index].key != widget.children[index].key)) {
      _stopDrag();
    }
  }

  Rect _rect(GlobalKey key) {
    final box = key.currentContext!.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _startDrag(int index, LongPressStartDetails details) {
    if (_dragIndex != null) return;
    final rect = _rect(_itemKeys[widget.children[index].key]!);
    setState(() {
      _dragIndex = index;
      _animateReorder = true;
      _dropIndex = index;
      _pointer = details.globalPosition;
      _dragOrigin = _pointer;
      _hasMoved = false;
      _anchor = _pointer - rect.topLeft;
      _dragSize = rect.size;
    });
    HapticFeedback.mediumImpact();
    _lastTick = Duration.zero;
    _ticker.start();
  }

  void _updateTarget() {
    if (_dragIndex == null) return;
    var target = 0;
    for (var index = 0; index < widget.children.length; index++) {
      if (index == _dragIndex) continue;
      final rect = _rect(_itemKeys[widget.children[index].key]!);
      if (_pointer.dy > rect.center.dy) target++;
    }
    _dropIndex = target;
  }

  void _moveDrag(LongPressMoveUpdateDetails details) {
    if (_dragIndex == null) return;
    setState(() {
      _pointer = details.globalPosition;
      _hasMoved = _hasMoved || (_pointer - _dragOrigin).distance > 8;
      _updateTarget();
    });
  }

  void _scrollDuringDrag(Duration elapsed) {
    final seconds = (elapsed - _lastTick).inMicroseconds / 1000000;
    _lastTick = elapsed;
    if (_dragIndex == null || !_hasMoved || !widget.controller.hasClients) {
      return;
    }
    final viewport = _rect(_viewportKey);
    final edge = (viewport.height * 0.08).clamp(24.0, 40.0);
    if (_pointer.dx < viewport.left || _pointer.dx > viewport.right) return;
    final y = _pointer.dy - viewport.top;
    final double direction;
    if (y < edge) {
      direction = -((edge - y) / edge).clamp(0.0, 1.0);
    } else if (y > viewport.height - edge) {
      direction = ((y - viewport.height + edge) / edge).clamp(0.0, 1.0);
    } else {
      return;
    }
    final position = widget.controller.position;
    final offset =
        (position.pixels + direction * 600 * seconds.clamp(0.0, 0.05))
            .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (offset == position.pixels) return;
    widget.controller.jumpTo(offset);
    // Refresh the drop target after the scroll is laid out, even for a still finger.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _dragIndex != null) setState(_updateTarget);
    });
  }

  void _stopDrag() {
    _ticker.stop();
    _dragIndex = null;
  }

  void _finishDrag({required bool commit}) {
    final from = _dragIndex;
    if (from == null) return;
    if (_hasMoved) _updateTarget();
    final to = _dropIndex;
    final inside = _rect(_viewportKey).contains(_pointer);
    setState(_stopDrag);
    if (commit && _hasMoved && inside && from != to) widget.onReorder(from, to);
  }

  Widget _content(BuildContext context, int index) {
    final localizations = WidgetsLocalizations.of(context);
    final actions = <CustomSemanticsAction, VoidCallback>{};
    if (widget.editing && _dragIndex == null) {
      if (index > 0) {
        actions[CustomSemanticsAction(label: localizations.reorderItemUp)] =
            () => widget.onReorder(index, index - 1);
        actions[CustomSemanticsAction(
                label: localizations.reorderItemToStart)] =
            () => widget.onReorder(index, 0);
      }
      if (index < widget.children.length - 1) {
        actions[CustomSemanticsAction(label: localizations.reorderItemDown)] =
            () => widget.onReorder(index, index + 1);
        actions[CustomSemanticsAction(label: localizations.reorderItemToEnd)] =
            () => widget.onReorder(index, widget.children.length - 1);
      }
    }
    return Semantics(
      container: widget.editing,
      customSemanticsActions: actions,
      child: _animateReorder
          ? AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              onEnd: () {
                if (_dragIndex == null && _animateReorder) {
                  setState(() => _animateReorder = false);
                }
              },
              child: _dragIndex == index
                  ? const SizedBox(
                      key: ValueKey('dashboard_drag_gap'),
                      height: 12,
                      width: double.infinity)
                  : widget.children[index],
            )
          : widget.children[index],
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final dragged = _dragIndex;
    final boundary = dragged == null
        ? -1
        : _dropIndex > dragged
            ? _dropIndex + 1
            : _dropIndex;
    return LayoutBuilder(builder: (context, constraints) {
      final scale = dragged == null
          ? 1.0
          : (constraints.maxHeight * 0.6 / _dragSize.height).clamp(0.01, 0.88);
      final pointer = dragged == null
          ? Offset.zero
          : _pointer - _rect(_viewportKey).topLeft;
      return Listener(
        onPointerCancel: (_) => _finishDrag(commit: false),
        child: Stack(
          key: _viewportKey,
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            SingleChildScrollView(
              key: const PageStorageKey('home_dashboard_scroll'),
              controller: widget.controller,
              physics: const ClampingScrollPhysics(),
              padding: widget.padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < widget.children.length; index++)
                    GestureDetector(
                      key: ValueKey(widget.children[index].key),
                      behavior: HitTestBehavior.opaque,
                      onLongPressStart: widget.editing
                          ? (details) => _startDrag(index, details)
                          : null,
                      onLongPressMoveUpdate: widget.editing ? _moveDrag : null,
                      onLongPressEnd: widget.editing
                          ? (_) => _finishDrag(commit: true)
                          : null,
                      child: Container(
                        key: _itemKeys.putIfAbsent(
                            widget.children[index].key!, GlobalKey.new),
                        foregroundDecoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                                color:
                                    boundary == index && _dropIndex != dragged
                                        ? primary
                                        : Colors.transparent,
                                width: 2),
                            bottom: BorderSide(
                                color: boundary == widget.children.length &&
                                        index == widget.children.length - 1 &&
                                        _dropIndex != dragged
                                    ? primary
                                    : Colors.transparent,
                                width: 2),
                          ),
                        ),
                        child: _content(context, index),
                      ),
                    ),
                  widget.footer,
                ],
              ),
            ),
            if (dragged != null)
              Positioned(
                left: pointer.dx - _anchor.dx * scale,
                top: pointer.dy - _anchor.dy * scale,
                width: _dragSize.width,
                height: _dragSize.height,
                child: IgnorePointer(
                  child: Transform.scale(
                    key: const ValueKey('dashboard_drag_feedback'),
                    alignment: Alignment.topLeft,
                    scale: scale,
                    child: Material(
                      color: palette.surface,
                      elevation: 8,
                      shadowColor: Colors.black.withValues(alpha: 0.25),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: primary),
                      ),
                      child: widget.children[dragged],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}
