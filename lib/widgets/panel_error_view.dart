import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_locale.dart';
import '../services/app_platform.dart';
import '../services/clash_service.dart';
import '../services/connection_feedback.dart';
import '../services/controller_connection_state.dart';

class PanelErrorView extends StatefulWidget {
  const PanelErrorView(
      {super.key,
      required this.message,
      required this.onRetry,
      this.isActive,
      this.probeConnection});

  final String message;
  final Future<void> Function() onRetry;
  final bool Function()? isActive;
  final Future<void> Function()? probeConnection;

  @override
  State<PanelErrorView> createState() => _PanelErrorViewState();
}

class _PanelErrorViewState extends State<PanelErrorView>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;
  bool _checking = false;
  bool _retrying = false;

  bool get _offline => widget.message == ConnectionFeedback.routerUnavailable;
  bool get _active =>
      mounted &&
      _foreground &&
      (widget.isActive?.call() ?? true) &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _timer =
        Timer.periodic(const Duration(seconds: 10), (_) => _checkConnection());
  }

  Future<void> _checkConnection() async {
    if (!_active || !_offline || _checking || _retrying) return;
    _checking = true;
    try {
      // Preserve the offline message until the controller answers, avoiding
      // repeated WebView rebuilds and loading flashes while disconnected.
      if (widget.probeConnection != null) {
        await widget.probeConnection!();
      } else {
        await ControllerConnectionState.instance.probe(() async {
          await ClashService.instance.getVersionInfo();
        });
      }
      if (_active && _offline) await _retry();
    } catch (_) {
      // Automatic recovery stays quiet; explicit retries retain page feedback.
    } finally {
      _checking = false;
    }
  }

  Future<void> _retry() async {
    if (!mounted || _retrying) return;
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_checkConnection());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_offline ? Icons.wifi_off_rounded : Icons.info_outline,
                    size: 32,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(tr(widget.message), textAlign: TextAlign.center),
                if (AppPlatform.isIOS && _offline) ...[
                  const SizedBox(height: 12),
                  Text(
                    tr('若已连接正确网络，请检查系统设置中的 Proxly 局域网权限。'),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: _retrying ? null : _retry,
                    child: Text(tr('重试'))),
              ],
            ),
          ),
        ),
      );
}
