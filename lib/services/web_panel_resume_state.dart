import 'package:flutter/widgets.dart';

/// Decides whether a suspended native page can still be probed and reused.
class WebPanelResumeState {
  WebPanelResumeState({DateTime Function()? now}) : _now = now ?? DateTime.now;

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

  bool consumeLongBackground({required bool isIOS}) {
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    // A suspended WKWebView can retain stale backend errors even when its
    // native process survives. Recreate after a long stay without probing it.
    return isIOS &&
        backgroundedAt != null &&
        _now().difference(backgroundedAt) >= const Duration(seconds: 30);
  }
}
