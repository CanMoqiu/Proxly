import 'dart:async';
import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../services/controller_connection_state.dart';
import 'panel_error_view.dart';

/// Covers a live WebView with the same connection/restart state as the home page.
class PanelConnectionGate extends StatefulWidget {
  const PanelConnectionGate(
      {super.key,
      required this.child,
      required this.isActive,
      required this.onRetry,
      required this.onUnavailable,
      this.connectionState});
  final Widget child;
  final bool Function() isActive;
  final Future<void> Function() onRetry;
  final VoidCallback onUnavailable;
  final ControllerConnectionState? connectionState;

  @override
  State<PanelConnectionGate> createState() => _PanelConnectionGateState();
}

class _PanelConnectionGateState extends State<PanelConnectionGate>
    with WidgetsBindingObserver {
  late final _connection =
      widget.connectionState ?? ControllerConnectionState.instance;
  bool _needsRecovery = false;
  bool _scheduled = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _connection.addListener(_changed);
    _recordUnavailable();
  }

  void _recordUnavailable() {
    if (_connection.message != null) {
      _needsRecovery = true;
      widget.onUnavailable();
    }
  }

  void _changed() {
    _recordUnavailable();
    if (mounted) setState(() {});
  }

  void _recoverIfActive() {
    if (!_needsRecovery ||
        _scheduled ||
        !_foreground ||
        !widget.isActive() ||
        _connection.phase != ControllerConnectionPhase.online ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted ||
            !_foreground ||
            !widget.isActive() ||
            _connection.phase != ControllerConnectionPhase.online) {
          return;
        }
        _needsRecovery = false;
        await widget.onRetry();
      } finally {
        _scheduled = false;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && mounted) setState(() {});
  }

  @override
  void dispose() {
    _connection.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _recoverIfActive();
    if (_connection.phase == ControllerConnectionPhase.restarting) {
      return ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(tr('正在重启 OpenClash...')),
        ])),
      );
    }
    final message = _connection.message;
    if (message != null) {
      return PanelErrorView(
          message: message,
          isActive: widget.isActive,
          onRetry: () async {
            _needsRecovery = false;
            await widget.onRetry();
          });
    }
    return widget.child;
  }
}
