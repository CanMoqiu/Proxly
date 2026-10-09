import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum AppFeedbackTone { info, success, error }

abstract final class AppFeedback {
  static const normalDuration = Duration(seconds: 3);
  static const errorDuration = Duration(seconds: 6);

  static int _generation = 0;
  static Timer? _activeTimer;
  static OverlayEntry? _activeEntry;
  static VoidCallback? _activeEntryListener;
  static GlobalKey<_AppFeedbackBannerState>? _activeBannerKey;
  static Animation<double>? _activeRouteAnimation;
  static AnimationStatusListener? _activeRouteListener;

  static void _detachRouteListener() {
    final animation = _activeRouteAnimation;
    final listener = _activeRouteListener;
    if (animation != null && listener != null) {
      animation.removeStatusListener(listener);
    }
    _activeRouteAnimation = null;
    _activeRouteListener = null;
  }

  static void _detachEntryListener() {
    final entry = _activeEntry;
    final listener = _activeEntryListener;
    if (entry != null && listener != null) entry.removeListener(listener);
    _activeEntryListener = null;
  }

  static void _removeActive(int generation, {bool animate = false}) {
    if (generation != _generation) return;
    _activeTimer?.cancel();
    _activeTimer = null;
    _detachRouteListener();
    final entry = _activeEntry;
    final banner = _activeBannerKey?.currentState;
    if (animate && banner != null) {
      banner.hide().whenComplete(() {
        if (generation != _generation || _activeEntry != entry) return;
        _detachEntryListener();
        entry?.remove();
        _activeEntry = null;
        _activeBannerKey = null;
      });
      return;
    }
    _detachEntryListener();
    entry?.remove();
    _activeEntry = null;
    _activeBannerKey = null;
  }

  static void showSnackBar(
    BuildContext context,
    String message, {
    AppFeedbackTone tone = AppFeedbackTone.info,
    bool dismissOnRouteChange = true,
  }) {
    final palette = AppPalette.of(context);
    final accent = switch (tone) {
      AppFeedbackTone.info => Theme.of(context).colorScheme.primary,
      AppFeedbackTone.success => palette.success,
      AppFeedbackTone.error => palette.error,
    };
    _removeActive(_generation);
    final generation = ++_generation;
    final overlay = Overlay.of(context);
    final bannerKey = GlobalKey<_AppFeedbackBannerState>();
    final entry = OverlayEntry(
      builder: (overlayContext) => _AppFeedbackBanner(
        key: bannerKey,
        message: message,
        tone: tone,
        accent: accent,
        backgroundColor: palette.surface,
        textColor: palette.textPrimary,
        borderColor: accent.withValues(alpha: 0.7),
      ),
    );
    overlay.insert(entry);
    _activeEntry = entry;
    _activeBannerKey = bannerKey;
    void handleEntryMount() {
      if (entry.mounted || _activeEntry != entry) return;
      _activeTimer?.cancel();
      _activeTimer = null;
      _detachRouteListener();
      _detachEntryListener();
      _activeEntry = null;
      _activeBannerKey = null;
    }

    _activeEntryListener = handleEntryMount;
    entry.addListener(handleEntryMount);
    _activeTimer = Timer(
      tone == AppFeedbackTone.error ? errorDuration : normalDuration,
      () => _removeActive(generation, animate: true),
    );

    final route = ModalRoute.of(context);
    if (dismissOnRouteChange && route is PageRoute<dynamic>) {
      final animation = route.animation;
      void handleRouteStatus(AnimationStatus status) {
        if (status == AnimationStatus.reverse ||
            status == AnimationStatus.dismissed) {
          _removeActive(generation);
        }
      }

      animation?.addStatusListener(handleRouteStatus);
      _activeRouteAnimation = animation;
      _activeRouteListener = handleRouteStatus;
    }
  }
}

class _AppFeedbackBanner extends StatefulWidget {
  final String message;
  final AppFeedbackTone tone;
  final Color accent;
  final Color backgroundColor;
  final Color textColor;
  final Color borderColor;

  const _AppFeedbackBanner({
    super.key,
    required this.message,
    required this.tone,
    required this.accent,
    required this.backgroundColor,
    required this.textColor,
    required this.borderColor,
  });

  @override
  State<_AppFeedbackBanner> createState() => _AppFeedbackBannerState();
}

class _AppFeedbackBannerState extends State<_AppFeedbackBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 160),
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(1.15, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  Future<void> hide() => _controller.reverse();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;
    final restingBottom =
        keyboardInset > 0 ? keyboardInset + 12 : media.viewPadding.bottom + 56;
    final lowerHalfHeight =
        media.size.height - restingBottom - media.size.height * 0.5 - 16;
    final maxBannerHeight = math.max(40.0, lowerHalfHeight);

    return Positioned(
      left: media.size.width * 0.25,
      right: 16,
      bottom: restingBottom,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Material(
            key: const ValueKey('app_feedback_banner'),
            color: widget.backgroundColor,
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: 0.24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: widget.borderColor),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxBannerHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        widget.tone == AppFeedbackTone.error
                            ? Icons.error_outline_rounded
                            : widget.tone == AppFeedbackTone.success
                                ? Icons.check_circle_outline_rounded
                                : Icons.info_outline_rounded,
                        color: widget.accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          widget.message,
                          style: TextStyle(color: widget.textColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

mixin TransientFeedbackStateMixin<T extends StatefulWidget> on State<T> {
  final Map<Object, Timer> _feedbackTimers = <Object, Timer>{};

  void scheduleFeedbackClear(
    Object channel, {
    required bool isError,
    required VoidCallback clear,
  }) {
    _feedbackTimers.remove(channel)?.cancel();
    _feedbackTimers[channel] = Timer(
      isError ? AppFeedback.errorDuration : AppFeedback.normalDuration,
      () {
        _feedbackTimers.remove(channel);
        if (mounted) clear();
      },
    );
  }

  void cancelFeedbackClear(Object channel) {
    _feedbackTimers.remove(channel)?.cancel();
  }

  @mustCallSuper
  void disposeTransientFeedback() {
    for (final timer in _feedbackTimers.values) {
      timer.cancel();
    }
    _feedbackTimers.clear();
  }
}
