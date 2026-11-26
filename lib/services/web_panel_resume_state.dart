import 'package:flutter/widgets.dart';

import 'app_platform.dart';

/// Decides whether a suspended native page can still be probed and reused.
class WebPanelResumeState {
  WebPanelResumeState({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const longBackgroundThreshold = Duration(minutes: 5);

  final DateTime Function() _now;
  DateTime? _backgroundedAt;
  bool foreground = true;

  void didChangeState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _backgroundedAt ??= _now();
    }
  }

  Duration? consumeBackgroundDuration() {
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    return backgroundedAt == null ? null : _now().difference(backgroundedAt);
  }

  bool consumeLongBackground() {
    final elapsed = consumeBackgroundDuration();
    return AppPlatform.isMobile &&
        elapsed != null &&
        elapsed >= longBackgroundThreshold;
  }
}
