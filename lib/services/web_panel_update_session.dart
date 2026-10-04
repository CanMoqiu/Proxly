import 'dart:async';
import 'package:flutter/foundation.dart';
import '../l10n/app_locale.dart';
import 'app_platform.dart';
import 'app_restart_service.dart';
import 'version_comparator.dart';
import 'web_panel_service.dart';

enum WebPanelUpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  installing,
  activating,
  updated,
  failed,
}

class WebPanelUpdateSession extends ChangeNotifier {
  WebPanelUpdateSession({
    this.getActiveVersion = WebPanelService.getActiveVersion,
    this.checkLatest = WebPanelService.checkLatest,
    this.downloadAndInstall = WebPanelService.downloadAndInstall,
    Future<void> Function()? save,
    Future<WebPanelReloadResult> Function()? restartPanels,
    this.restartApp = AppRestartService.restartApp,
    this.usesProcessRestart = _usesProcessRestart,
  })  : save = save ?? WebPanelSync.instance.save,
        restartPanels =
            restartPanels ?? WebPanelSync.instance.restartAllWebViews;

  static final instance = WebPanelUpdateSession();
  static bool _usesProcessRestart() => AppPlatform.supportsApkUpdates;

  final Future<String> Function() getActiveVersion;
  final Future<WebPanelVersionInfo> Function() checkLatest;
  final Future<void> Function(WebPanelVersionInfo, void Function(double))
      downloadAndInstall;
  final Future<void> Function() save;
  final Future<WebPanelReloadResult> Function() restartPanels;
  final Future<void> Function() restartApp;
  final bool Function() usesProcessRestart;

  WebPanelUpdatePhase phase = WebPanelUpdatePhase.idle;
  WebPanelVersionInfo? availableInfo;
  String? installedVersion;
  double progress = 0;
  String? message;
  Timer? _resetTimer;
  bool _pendingActivation = false;

  bool get hasUpdate => availableInfo != null;
  bool get activationPending => _pendingActivation;
  bool get busy => const {
        WebPanelUpdatePhase.checking,
        WebPanelUpdatePhase.downloading,
        WebPanelUpdatePhase.installing,
        WebPanelUpdatePhase.activating,
      }.contains(phase);

  Future<WebPanelVersionInfo?> check() async {
    if (busy || availableInfo != null) return availableInfo;
    _resetTimer?.cancel();
    phase = WebPanelUpdatePhase.checking;
    message = '正在检查最新版本…';
    progress = 0;
    notifyListeners();
    try {
      final current = await getActiveVersion();
      final latest = await checkLatest();
      final comparison = compareNumericVersions(latest.tag, current);
      if (comparison == null) throw FormatException(tr('版本格式异常'));
      if (comparison <= 0) {
        phase = WebPanelUpdatePhase.upToDate;
        message = '当前已是最新版本 $current';
        notifyListeners();
        _resetTimer = Timer(const Duration(seconds: 3), () {
          if (availableInfo != null || phase != WebPanelUpdatePhase.upToDate) {
            return;
          }
          phase = WebPanelUpdatePhase.idle;
          message = null;
          notifyListeners();
        });
        return null;
      }
      availableInfo = latest;
      phase = WebPanelUpdatePhase.available;
      message = '发现新版本 ${latest.tag}';
      notifyListeners();
      return latest;
    } catch (error) {
      phase = WebPanelUpdatePhase.failed;
      message = '检查失败：$error';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> install() async {
    final info = availableInfo;
    if (info == null || busy) return;
    _resetTimer?.cancel();
    // Acquire the busy state before awaiting persistence.
    phase = _pendingActivation
        ? WebPanelUpdatePhase.activating
        : WebPanelUpdatePhase.downloading;
    notifyListeners();
    try {
      if (!_pendingActivation) {
        await save().timeout(const Duration(seconds: 5));
        progress = 0;
        message = '正在下载 ${info.tag}…';
        notifyListeners();
        await downloadAndInstall(info, (value) {
          progress = value;
          phase = value < 0.8
              ? WebPanelUpdatePhase.downloading
              : WebPanelUpdatePhase.installing;
          message = value < 0.8
              ? '正在下载 ${info.tag}… ${(value * 100).toInt()}%'
              : '正在解压面板文件…';
          notifyListeners();
        });
        installedVersion = info.tag;
        _pendingActivation = true;
      }
      phase = WebPanelUpdatePhase.activating;
      progress = 1;
      message = usesProcessRestart() ? '更新完成，正在重启 Proxly…' : '正在加载新面板…';
      notifyListeners();
      if (usesProcessRestart()) {
        await restartApp();
      } else {
        final result = await restartPanels();
        if (!result.succeeded) throw StateError(tr('新面板加载失败，请重试激活'));
      }
      _pendingActivation = false;
      availableInfo = null;
      phase = WebPanelUpdatePhase.updated;
      message = '面板更新完成';
      notifyListeners();
    } catch (error) {
      phase = WebPanelUpdatePhase.failed;
      message = _pendingActivation ? '新面板加载失败，请重试激活' : '更新失败：$error';
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }
}
