import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AdaptiveScrollPadding {
  AdaptiveScrollPadding._();

  static EdgeInsets page(
    BuildContext context, {
    double left = 16,
    double top = 16,
    double right = 16,
    double bottom = 24,
  }) {
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    return EdgeInsets.fromLTRB(left, top, right, bottom + safeBottom);
  }
}

class AdaptiveSingleLineText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final AlignmentGeometry alignment;

  const AdaptiveSingleLineText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.center,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
}

class AdaptiveMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final double gap;
  final double velocity;
  final Duration startDelay;

  const AdaptiveMarqueeText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.left,
    this.gap = 28,
    this.velocity = 32,
    this.startDelay = Duration.zero,
  });

  @override
  State<AdaptiveMarqueeText> createState() => _AdaptiveMarqueeTextState();
}

class _AdaptiveMarqueeTextState extends State<AdaptiveMarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
  );

  @override
  void didUpdateWidget(covariant AdaptiveMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.gap != widget.gap ||
        oldWidget.velocity != widget.velocity ||
        oldWidget.startDelay != widget.startDelay) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Duration _travelDuration(double distance) {
    final speed = widget.velocity <= 0 ? 32.0 : widget.velocity;
    final milliseconds =
        ((distance / speed) * 1000).round().clamp(2400, 16000).toInt();
    return Duration(milliseconds: milliseconds);
  }

  void _syncAnimation(bool shouldScroll, Duration duration) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!shouldScroll || !TickerMode.valuesOf(context).enabled) {
        _controller.stop();
        _controller.value = 0;
        return;
      }

      if (_controller.duration != duration) {
        _controller.duration = duration;
        _controller.value = 0;
      }
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final defaultStyle = DefaultTextStyle.of(context).style;
    final style = defaultStyle.merge(widget.style);
    final direction = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: direction,
          textScaler: textScaler,
        )..layout();
        final textWidth = painter.width;
        final maxWidth = constraints.maxWidth;
        final shouldScroll = maxWidth.isFinite && textWidth > maxWidth + 0.5;

        if (!shouldScroll) {
          _syncAnimation(false, Duration.zero);
          return Text(
            widget.text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            textAlign: widget.textAlign,
            style: style,
          );
        }

        final distance = textWidth + widget.gap;
        final fullWidth = textWidth * 2 + widget.gap;
        final travelDuration = _travelDuration(distance);
        final totalDuration = travelDuration + widget.startDelay;
        final delayFraction = totalDuration.inMicroseconds == 0
            ? 0.0
            : widget.startDelay.inMicroseconds / totalDuration.inMicroseconds;
        _syncAnimation(true, totalDuration);

        return ClipRect(
          child: SizedBox(
            height: painter.height,
            child: AnimatedBuilder(
              animation: _controller,
              child: SizedBox(
                width: fullWidth,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: textWidth,
                      child: Text(
                        widget.text,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        textAlign: widget.textAlign,
                        style: style,
                      ),
                    ),
                    SizedBox(width: widget.gap),
                    SizedBox(
                      width: textWidth,
                      child: Text(
                        widget.text,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        textAlign: widget.textAlign,
                        style: style,
                      ),
                    ),
                  ],
                ),
              ),
              builder: (context, child) {
                final progress = _controller.value <= delayFraction
                    ? 0.0
                    : (_controller.value - delayFraction) / (1 - delayFraction);
                return Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: -distance * progress,
                      top: 0,
                      width: fullWidth,
                      child: child!,
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class AdaptiveOptionGroup extends StatelessWidget {
  final List<String> labels;
  final List<Widget> children;
  final double spacing;
  final double minimumFontSize;
  final double reservedItemWidth;

  const AdaptiveOptionGroup({
    super.key,
    required this.labels,
    required this.children,
    this.spacing = 8,
    this.minimumFontSize = 10.5,
    this.reservedItemWidth = 54,
  }) : assert(labels.length == children.length);

  bool _fitsHorizontally(BuildContext context, double maxWidth) {
    if (!maxWidth.isFinite || children.length < 2) return true;
    final itemWidth =
        (maxWidth - spacing * (children.length - 1)) / children.length;
    final scaler = MediaQuery.textScalerOf(context);
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(fontSize: minimumFontSize),
        ),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      if (painter.width + reservedItemWidth > itemWidth) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_fitsHorizontally(context, constraints.maxWidth)) {
          return Row(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(width: spacing),
                Expanded(child: children[i]),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(height: spacing),
              children[i],
            ],
          ],
        );
      },
    );
  }
}

class AdaptiveSelectionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;

  const AdaptiveSelectionButton({
    super.key,
    required this.label,
    this.icon,
    required this.selected,
    this.enabled = true,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final palette = AppPalette.of(context);
    final foreground = selected
        ? primary
        : enabled
            ? palette.textSecondary
            : palette.textDisabled;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: padding,
            decoration: BoxDecoration(
              color: selected
                  ? primary.withValues(
                      alpha: Theme.of(context).brightness == Brightness.dark
                          ? 0.08
                          : 0.12,
                    )
                  : enabled
                      ? Colors.transparent
                      : palette.inputBackground,
              border: Border.all(
                color: selected ? primary : palette.border,
                width: selected ? 1.2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: foreground),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: AdaptiveSingleLineText(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ThemeModeSelector extends StatelessWidget {
  final ThemeMode mode;
  final bool isDark;
  final String lightLabel;
  final String darkLabel;
  final String followSystemLabel;
  final ValueChanged<ThemeMode> onChanged;

  const ThemeModeSelector({
    super.key,
    required this.mode,
    required this.isDark,
    required this.lightLabel,
    required this.darkLabel,
    required this.followSystemLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final followsSystem = mode == ThemeMode.system;
    final textColor = AppPalette.of(context).textPrimary;

    return Column(
      children: [
        AdaptiveOptionGroup(
          labels: [lightLabel, darkLabel],
          spacing: 10,
          children: [
            _ThemeModeButton(
              key: const ValueKey('theme_mode_light'),
              label: lightLabel,
              icon: Icons.light_mode_rounded,
              selected: mode == ThemeMode.light,
              enabled: !followsSystem,
              onTap: () => onChanged(ThemeMode.light),
            ),
            _ThemeModeButton(
              key: const ValueKey('theme_mode_dark'),
              label: darkLabel,
              icon: Icons.dark_mode_rounded,
              selected: mode == ThemeMode.dark,
              enabled: !followsSystem,
              onTap: () => onChanged(ThemeMode.dark),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              followSystemLabel,
              style: TextStyle(fontSize: 13, color: textColor),
            ),
            const Spacer(),
            Switch(
              key: const ValueKey('theme_mode_system_switch'),
              value: followsSystem,
              onChanged: (value) =>
                  onChanged(value ? ThemeMode.system : ThemeMode.light),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ],
    );
  }
}

class _ThemeModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ThemeModeButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AdaptiveSelectionButton(
      label: label,
      icon: icon,
      selected: selected,
      enabled: enabled,
      onTap: onTap,
    );
  }
}

class LabeledInputField extends StatelessWidget {
  final String title;
  final String description;
  final Color titleColor;
  final Color descriptionColor;
  final Widget child;

  const LabeledInputField({
    super.key,
    required this.title,
    required this.description,
    required this.titleColor,
    required this.descriptionColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: titleColor,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          description,
          style: TextStyle(fontSize: 11, height: 1.35, color: descriptionColor),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
