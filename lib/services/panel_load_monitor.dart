import 'dart:async';
import 'package:flutter/foundation.dart';

/// Tracks an actual WebView load, including timeouts, without unhandled errors
/// when the page is loaded independently of a panel update.
class PanelLoadMonitor extends ChangeNotifier {
  PanelLoadMonitor({this.timeout = const Duration(seconds: 30)});

  final Duration timeout;
  Timer? _timer;
  Completer<bool>? _loaded;
  String? error;
  bool ready = false;

  void begin() {
    _finish(false);
    _loaded = Completer<bool>();
    error = null;
    ready = false;
    _timer = Timer(timeout, () => fail('面板加载超时，请重试'));
    notifyListeners();
  }

  /// A server restart starts tracking before the native navigation callback.
  /// Keep its pending completion so activation waits for that same page load.
  void navigationStarted() {
    if (_loaded == null || ready || error != null) begin();
  }

  void succeed() {
    ready = true;
    error = null;
    _finish(true);
    notifyListeners();
  }

  void fail(String message) {
    ready = false;
    error = message;
    _finish(false);
    notifyListeners();
  }

  void _finish(bool success) {
    _timer?.cancel();
    if (_loaded != null && !_loaded!.isCompleted) _loaded!.complete(success);
  }

  Future<void> waitUntilReady() async {
    final load = _loaded;
    if (load == null || !await load.future) {
      throw StateError(error ?? 'Panel was closed before loading');
    }
  }

  @override
  void dispose() {
    _finish(false);
    super.dispose();
  }
}
