import 'dart:async';

/// Network authentication has a deadline; a human fingerprint decision does not.
class SshAuthenticationDeadline {
  SshAuthenticationDeadline(this.timeout);

  final Duration timeout;
  final _expired = Completer<void>();
  Timer? _timer;
  bool _started = false;
  bool _verifying = false;
  bool _finished = false;

  void _arm() {
    _timer?.cancel();
    if (!_started || _verifying || _finished) return;
    _timer = Timer(timeout, () {
      _expired.completeError(TimeoutException('SSH authentication timed out'));
    });
  }

  Future<void> waitFor(Future<void> authenticated) async {
    _started = true;
    _arm();
    try {
      await Future.any([authenticated, _expired.future]);
    } finally {
      _finished = true;
      _timer?.cancel();
    }
  }

  Future<bool> verify(FutureOr<bool> Function() decision) async {
    _verifying = true;
    _timer?.cancel();
    try {
      return await decision();
    } finally {
      _verifying = false;
      _arm();
    }
  }
}
