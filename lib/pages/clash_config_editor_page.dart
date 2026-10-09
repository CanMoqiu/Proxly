import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

import '../l10n/app_locale.dart';
import '../services/app_platform.dart';
import '../services/clash_config_file_service.dart';
import '../services/openclash_restart_coordinator.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/app_feedback.dart';
import '../widgets/yaml_file_dialogs.dart';
import '../widgets/yaml_file_actions.dart';
import '../widgets/yaml_config_picker.dart';

enum _ExitChoice { cancel, discard, save }

class ClashConfigEditorPage extends StatefulWidget {
  final ClashConfigFile? file;
  final Future<List<ClashConfigFile>> Function()? listFiles;
  final Future<ClashActiveConfig> Function()? loadActiveConfig;
  final YamlFileActions? fileActions;
  final OpenClashRestartCoordinator? restartCoordinator;
  final Future<String> Function(String path)? readFile;
  final Future<void> Function(String path, String content)? writeFile;

  const ClashConfigEditorPage({
    super.key,
    this.file,
    this.listFiles,
    this.loadActiveConfig,
    this.fileActions,
    this.restartCoordinator,
    this.readFile,
    this.writeFile,
  });

  @override
  State<ClashConfigEditorPage> createState() => _ClashConfigEditorPageState();
}

({int line, int column}) yamlCursorPosition(CodeLineSelection selection) {
  return (
    line: selection.extentIndex + 1,
    column: selection.extentOffset + 1,
  );
}

class _ClashConfigEditorPageState extends State<ClashConfigEditorPage>
    with TransientFeedbackStateMixin<ClashConfigEditorPage> {
  final _editorController = CodeLineEditingController.fromText(
    '',
    const CodeLineOptions(indentSize: 1),
  );
  late final YamlDocumentHorizontalScrollController
      _editorHorizontalScrollController;
  late final ScrollController _editorVerticalScrollController;
  late final CodeScrollController _editorScrollController;
  final _editorFocusNode = FocusNode();
  late final SelectionToolbarController _selectionToolbarController;

  ClashConfigFile? _file;
  bool _managing = false;
  late final YamlFileActions _fileActions;
  late final OpenClashRestartCoordinator _restartCoordinator;
  bool _loading = true;
  bool _fileLoaded = false;
  bool _saving = false;
  bool _dirty = false;
  bool _savedDuringSession = false;
  final Set<String> _modifiedPaths = {};
  bool _updatingEditorText = false;
  int _lineCount = 1;
  int _cursorLine = 1;
  int _cursorColumn = 1;
  String _savedText = '';
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _file = widget.file;
    _fileActions = widget.fileActions ?? YamlFileActions();
    _restartCoordinator =
        widget.restartCoordinator ?? OpenClashRestartCoordinator.instance;
    _editorHorizontalScrollController =
        YamlDocumentHorizontalScrollController();
    _editorVerticalScrollController = ScrollController();
    _editorScrollController = CodeScrollController(
      horizontalScroller: _editorHorizontalScrollController,
      verticalScroller: _editorVerticalScrollController,
    );
    _selectionToolbarController = MobileSelectionToolbarController(
      builder: (
          {required context,
          required anchors,
          required controller,
          required onDismiss,
          required onRefresh}) {
        return YamlEditorSelectionToolbar(
          anchors: anchors,
          controller: controller,
          editable: _fileLoaded && !_loading && !_saving && !_managing,
          focusNode: _editorFocusNode,
          onDismiss: onDismiss,
        );
      },
    );
    _editorController.addListener(_handleEditorChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dismissKeyboard();
      _loadFile();
    });
  }

  @override
  void dispose() {
    _selectionToolbarController.hide(context);
    disposeTransientFeedback();
    _editorController.dispose();
    _editorScrollController.dispose();
    _editorHorizontalScrollController.dispose();
    _editorVerticalScrollController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  void _clearEditorFeedback() {
    cancelFeedbackClear('editor_operation');
    _error = null;
    _message = null;
  }

  void _scheduleEditorFeedback({required bool isError}) {
    scheduleFeedbackClear(
      'editor_operation',
      isError: isError,
      clear: () => setState(() {
        _error = null;
        _message = null;
      }),
    );
  }

  void _handleEditorChanged() {
    if (_updatingEditorText) return;
    final text = _editorController.text;
    final nextLineCount = _editorController.lineCount;
    final cursor = yamlCursorPosition(_editorController.selection);
    final nextDirty = text != _savedText;

    if (nextLineCount == _lineCount &&
        cursor.line == _cursorLine &&
        cursor.column == _cursorColumn &&
        nextDirty == _dirty) {
      return;
    }

    setState(() {
      _lineCount = nextLineCount;
      _cursorLine = cursor.line;
      _cursorColumn = cursor.column;
      _dirty = nextDirty;
    });
  }

  void _setEditorText(String value) {
    _updatingEditorText = true;
    _editorController.text = value;
    _editorController.clearHistory();
    // re_editor normalizes CRLF/CR to its configured line break. Compare
    // future edits with that loaded representation, not the raw file bytes.
    _savedText = _editorController.text;
    _lineCount = _editorController.lineCount;
    final cursor = yamlCursorPosition(_editorController.selection);
    _cursorLine = cursor.line;
    _cursorColumn = cursor.column;
    _updatingEditorText = false;
  }

  void _dismissKeyboard() {
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  Future<void> _loadFile() async {
    if (!mounted) return;
    final file = _file;
    if (file == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _fileLoaded = false;
      _dirty = false;
      _setEditorText('');
      _loading = true;
      _clearEditorFeedback();
    });
    try {
      final content =
          await (widget.readFile ?? ClashConfigFileService.readFile)(
        _file!.path,
      );
      if (!mounted) return;
      setState(() {
        _setEditorText(content);
        _dirty = false;
        _fileLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _formatError('读取文件', e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) => _dismissKeyboard());
      }
    }
  }

  Future<bool> _saveFile() async {
    if (_saving || _loading || !_fileLoaded) return false;
    setState(() {
      _saving = true;
      _clearEditorFeedback();
    });
    try {
      await (widget.writeFile ?? ClashConfigFileService.writeTextFile)(
        _file!.path,
        _editorController.text,
      );
      if (!mounted) return true;
      setState(() {
        _savedText = _editorController.text;
        _dirty = false;
        _savedDuringSession = true;
        _modifiedPaths.add(_file!.path);
        _message = '已保存 ${_file!.name}';
      });
      _scheduleEditorFeedback(isError: false);
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _error = _formatError('保存', e));
      _scheduleEditorFeedback(isError: true);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmPendingChanges() async {
    if (!_dirty) return true;

    final choice = await showDialog<_ExitChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('保存修改？')),
        content: Text(tr('当前 YAML 配置有未保存修改，继续前要保存吗？')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_ExitChoice.cancel),
            child: AdaptiveSingleLineText(tr('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_ExitChoice.discard),
            child: AdaptiveSingleLineText(tr('不保存')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_ExitChoice.save),
            child: AdaptiveSingleLineText(tr('保存')),
          ),
        ],
      ),
    );

    if (!mounted || choice == null || choice == _ExitChoice.cancel) {
      return false;
    }
    if (choice == _ExitChoice.discard) return true;
    return _saveFile();
  }

  Future<void> _handleExit() async {
    if (_saving || _managing) return;
    setState(() => _managing = true);
    try {
      if (!await _confirmPendingChanges() || !mounted) return;
      if (await _needsRestartReminder()) {
        if (!mounted) return;
        final restart = await showDialog<bool>(
            context: context,
            builder: (_) => const YamlRestartAfterSaveDialog());
        if (!mounted || restart == null) return;
        if (restart) {
          setState(() => _message = '正在重启 OpenClash...');
          final result = await _restartCoordinator.restart(
              reason: OpenClashRestartReason.yamlEditor);
          if (!mounted) return;
          if (!result.success) {
            setState(() {
              _message = null;
              _error = _formatError('重启 OpenClash', result.error ?? '未知错误');
            });
            return;
          }
        }
      }
      if (mounted) Navigator.of(context).pop(_savedDuringSession);
    } finally {
      if (mounted) setState(() => _managing = false);
    }
  }

  Future<bool> _needsRestartReminder() async {
    if (_modifiedPaths.isEmpty) return false;
    setState(() => _message = '正在检查当前配置...');
    try {
      // The edited file can change during a session. Resolve the running
      // configuration at exit instead of treating every saved file as active.
      final active = await (widget.loadActiveConfig ??
          ClashConfigFileService.getActiveConfig)();
      if (active.subscriptionMode || active.file == null) return false;
      final activePath =
          ClashConfigFileService.normalizeConfigFilePath(active.file!.path);
      return _modifiedPaths.any((path) =>
          ClashConfigFileService.normalizeConfigFilePath(path) == activePath);
    } catch (_) {
      if (mounted) {
        AppFeedback.showSnackBar(
            context, tr('无法确认当前配置；若修改了运行配置，请稍后手动重启 OpenClash'),
            tone: AppFeedbackTone.error, dismissOnRouteChange: false);
      }
      return false;
    } finally {
      if (mounted && _message == '正在检查当前配置...') {
        setState(() => _message = null);
      }
    }
  }

  Future<void> _manage(Future<void> Function() action) async {
    if (_loading || _saving || _managing) return;
    _dismissKeyboard();
    setState(() {
      _managing = true;
      _clearEditorFeedback();
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _error = _formatError('文件操作', error));
        _scheduleEditorFeedback(isError: true);
      }
    } finally {
      if (mounted) setState(() => _managing = false);
    }
  }

  Future<void> _chooseFile() => _manage(() async {
        final files =
            await (widget.listFiles ?? ClashConfigFileService.listFiles)();
        if (!mounted) return;
        if (files.isEmpty) {
          setState(() => _message = '没有找到 YAML 配置文件，可上传新配置。');
          return;
        }
        final selected = await showModalBottomSheet<ClashConfigFile>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (_) => YamlConfigPickerSheet(
                files: files, activePath: _file?.path, activate: false));
        if (!mounted || selected == null || selected.path == _file?.path) {
          return;
        }
        if (!await _confirmPendingChanges() || !mounted) return;
        _file = selected;
        await _loadFile();
      });

  Future<void> _uploadFile() => _manage(() async {
        if (!await _confirmPendingChanges() || !mounted) return;
        final uploaded = await _fileActions.upload(context);
        if (!mounted || uploaded == null) return;
        _file = uploaded;
        _savedDuringSession = true;
        _modifiedPaths.add(uploaded.path);
        await _loadFile();
      });

  Future<void> _renameFile() => _manage(() async {
        final file = _file;
        if (file == null) return;
        final renamed = await _fileActions.rename(context, file);
        if (!mounted || renamed == null) return;
        setState(() {
          if (_modifiedPaths.remove(file.path)) {
            _modifiedPaths.add(renamed.path);
          }
          _file = renamed;
          _message = '已重命名为 ${renamed.name}';
        });
        _scheduleEditorFeedback(isError: false);
      });

  Future<void> _exportFile() => _manage(() async {
        final file = _file;
        if (file == null || !_fileLoaded) return;
        if (await _fileActions.export(context, file, _editorController.text) &&
            mounted) {
          setState(() => _message = '已导出 ${file.name}');
          _scheduleEditorFeedback(isError: false);
        }
      });

  Future<void> _deleteFile() => _manage(() async {
        final file = _file;
        if (file == null) return;
        if (!await _fileActions.delete(context, file,
                hasUnsavedChanges: _dirty) ||
            !mounted) {
          return;
        }
        setState(() {
          _modifiedPaths.remove(file.path);
          _savedDuringSession = true;
          _file = null;
          _fileLoaded = false;
          _dirty = false;
          _setEditorText('');
          _message = '已删除 ${file.name}';
        });
        _scheduleEditorFeedback(isError: false);
      });

  String _formatError(String action, Object error) {
    if (error is SshPasswordRequiredException) {
      return '请先在设置页填写 SSH 密码';
    }
    final detail = error is FormatException ? error.message : error;
    return '$action失败：$detail';
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final systemBottomInset = MediaQuery.paddingOf(context).bottom;
    final editorBottomInset =
        keyboardInset > 0 ? keyboardInset : systemBottomInset;

    return PopScope(
      // Dirty or saved sessions use the explicit back action so neither the
      // save/discard choice nor the restart reminder can be bypassed on iOS.
      canPop: AppPlatform.isIOS &&
          !_dirty &&
          !_saving &&
          !_managing &&
          !_savedDuringSession,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleExit();
      },
      child: Scaffold(
        backgroundColor: _YamlEditorSurface._editorBg,
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: _YamlEditorSurface._titleBg,
          foregroundColor: _YamlEditorSurface._text,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: _YamlEditorSurface._titleBg,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: _YamlEditorSurface._text,
            ),
            onPressed: _handleExit,
          ),
          title: TextButton(
            key: const ValueKey('yaml_editor_file_picker'),
            onPressed: _loading || _saving || _managing ? null : _chooseFile,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                  child: Text(_file?.name ?? tr('选择 YAML 配置'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _YamlEditorSurface._text))),
              const Icon(Icons.expand_more_rounded,
                  size: 18, color: _YamlEditorSurface._text),
            ]),
          ),
          centerTitle: true,
          actions: [
            YamlEditorSaveButton(
              dirty: _dirty,
              loading: _loading,
              saving: _saving,
              enabled: _fileLoaded && !_managing,
              onSave: _saveFile,
            ),
            PopupMenuButton<String>(
              key: const ValueKey('yaml_editor_file_actions'),
              tooltip: tr('文件管理'),
              enabled: !_saving && !_loading && !_managing,
              onSelected: (action) {
                switch (action) {
                  case 'upload':
                    unawaited(_uploadFile());
                  case 'rename':
                    unawaited(_renameFile());
                  case 'export':
                    unawaited(_exportFile());
                  case 'delete':
                    unawaited(_deleteFile());
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'upload', child: Text(tr('上传新配置'))),
                PopupMenuItem(
                    value: 'rename',
                    enabled: _file != null,
                    child: Text(tr('重命名'))),
                PopupMenuItem(
                    value: 'export',
                    enabled: _fileLoaded,
                    child: Text(tr('导出当前内容'))),
                PopupMenuItem(
                    value: 'delete',
                    enabled: _file != null,
                    child: Text(tr('删除配置'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(31),
            child: YamlEditorHeaderInfo(
              lineCount: _lineCount,
              cursorLine: _cursorLine,
              cursorColumn: _cursorColumn,
            ),
          ),
        ),
        body: ColoredBox(
          color: _YamlEditorSurface._sideBg,
          child: AnimatedPadding(
            key: const ValueKey('yaml_editor_keyboard_inset'),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: editorBottomInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_file == null && !_loading)
                  _InfoBanner(
                      message: '选择 YAML 或上传新配置开始编辑',
                      color: AppPalette.dark.textSecondary,
                      actionLabel: '上传',
                      onAction: _managing ? null : _uploadFile,
                      compact: true),
                if (_error != null)
                  _InfoBanner(
                    message: _error!,
                    color: AppPalette.dark.error,
                    actionLabel: !_fileLoaded && !_loading ? '重试' : null,
                    onAction: !_fileLoaded && !_loading ? _loadFile : null,
                    compact: true,
                  ),
                if (_message != null)
                  _InfoBanner(
                    message: _message!,
                    color: AppPalette.dark.success,
                    compact: true,
                  ),
                Expanded(
                  child: _YamlEditorSurface(
                    controller: _editorController,
                    scrollController: _editorScrollController,
                    horizontalScrollController:
                        _editorHorizontalScrollController,
                    focusNode: _editorFocusNode,
                    toolbarController: _selectionToolbarController,
                    loading: _loading,
                    enabled: _fileLoaded && !_saving && !_managing,
                    cursorLine: _cursorLine,
                  ),
                ),
                YamlEditorShortcutBar(
                  controller: _editorController,
                  focusNode: _editorFocusNode,
                  enabled: _fileLoaded && !_loading && !_saving,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class YamlEditorHeaderInfo extends StatelessWidget {
  final int lineCount;
  final int cursorLine;
  final int cursorColumn;

  const YamlEditorHeaderInfo({
    super.key,
    required this.lineCount,
    required this.cursorLine,
    required this.cursorColumn,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('yaml_editor_header_info'),
      height: 31,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: _YamlEditorSurface._titleBg,
        border: Border(
          top: BorderSide(color: _YamlEditorSurface._border, width: 0.5),
          bottom: BorderSide(color: _YamlEditorSurface._border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: AdaptiveSingleLineText(
              tr('总行数：$lineCount'),
              alignment: Alignment.centerLeft,
              style: const TextStyle(
                fontSize: 11,
                color: _YamlEditorSurface._muted,
              ),
            ),
          ),
          Expanded(
            child: AdaptiveSingleLineText(
              tr('行 $cursorLine，列 $cursorColumn'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: _YamlEditorSurface._text,
              ),
            ),
          ),
          Expanded(
            child: AdaptiveSingleLineText(
              tr('编码：UTF-8'),
              textAlign: TextAlign.right,
              alignment: Alignment.centerRight,
              style: const TextStyle(
                fontSize: 11,
                color: _YamlEditorSurface._muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class YamlEditorSaveButton extends StatelessWidget {
  final bool dirty;
  final bool loading;
  final bool saving;
  final bool enabled;
  final VoidCallback onSave;

  const YamlEditorSaveButton({
    super.key,
    required this.dirty,
    required this.loading,
    required this.saving,
    required this.enabled,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final canSave = dirty && !loading && !saving && enabled;
    return IconButton(
      key: const ValueKey('yaml_editor_save'),
      tooltip: tr('保存'),
      icon: saving
          ? const SizedBox(
              key: ValueKey('yaml_editor_saving'),
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(
              Icons.save_rounded,
              key: const ValueKey('yaml_editor_save_icon'),
              color: dirty ? Colors.white : _YamlEditorSurface._muted,
            ),
      onPressed: canSave ? onSave : null,
    );
  }
}

@immutable
class YamlEditorLayoutMetrics {
  static const lineNumberFontSize = 12.0;
  static const lineNumberHorizontalPadding = 8.0;
  static const dividerWidth = 1.0;
  static const codeGap = 12.0;
  static const codeFontSize = 13.0;
  static const codeFontHeight = 1.46;

  final double gutterWidth;
  final double codeLeftPadding;
  final double characterWidth;

  const YamlEditorLayoutMetrics({
    required this.gutterWidth,
    required this.codeLeftPadding,
    required this.characterWidth,
  });

  factory YamlEditorLayoutMetrics.forLineCount(int lineCount) {
    final labelPainter = TextPainter(
      text: TextSpan(
        text: '${lineCount < 1 ? 1 : lineCount}',
        style: const TextStyle(
          fontSize: lineNumberFontSize,
          fontFamily: 'ProxlyMono',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final characterPainter = TextPainter(
      text: const TextSpan(
        text: ' ',
        style: TextStyle(
          fontSize: codeFontSize,
          fontFamily: 'ProxlyMono',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final gutter =
        labelPainter.width + lineNumberHorizontalPadding * 2 + dividerWidth;
    return YamlEditorLayoutMetrics(
      gutterWidth: gutter,
      codeLeftPadding: gutter + codeGap,
      characterWidth: characterPainter.width,
    );
  }
}

@immutable
class YamlDocumentLineChange {
  final int startLine;
  final int removedLineCount;
  final int addedLineCount;

  const YamlDocumentLineChange({
    required this.startLine,
    required this.removedLineCount,
    required this.addedLineCount,
  });
}

/// Maintains line boundaries without splitting the complete YAML document on
/// every keystroke. Only complete lines around the changed range are replaced.
class YamlDocumentMetricsController {
  String _text;
  final List<String> _lines;
  final List<int> _lineStarts;
  int debugLastChangedLineCount = 0;

  YamlDocumentMetricsController([String text = ''])
      : _text = text,
        _lines = text.split('\n'),
        _lineStarts = _buildLineStarts(text);

  String get text => _text;
  List<String> get lines => UnmodifiableListView(_lines);
  int get lineCount => _lines.length;

  void replaceText(String text) {
    _text = text;
    _lines
      ..clear()
      ..addAll(text.split('\n'));
    _lineStarts
      ..clear()
      ..addAll(_buildLineStarts(text));
    debugLastChangedLineCount = _lines.length;
  }

  YamlDocumentLineChange? updateText(String nextText) {
    if (nextText == _text) {
      debugLastChangedLineCount = 0;
      return null;
    }

    final oldText = _text;
    final sharedLimit = math.min(oldText.length, nextText.length);
    var prefix = 0;
    while (prefix < sharedLimit &&
        oldText.codeUnitAt(prefix) == nextText.codeUnitAt(prefix)) {
      prefix++;
    }

    var suffix = 0;
    while (suffix < sharedLimit - prefix &&
        oldText.codeUnitAt(oldText.length - suffix - 1) ==
            nextText.codeUnitAt(nextText.length - suffix - 1)) {
      suffix++;
    }

    final startOffset =
        prefix == 0 ? 0 : oldText.lastIndexOf('\n', prefix - 1) + 1;
    final oldChangedEnd = oldText.length - suffix;
    final nextChangedEnd = nextText.length - suffix;
    final oldFollowingBreak = oldText.indexOf('\n', oldChangedEnd);
    final nextFollowingBreak = nextText.indexOf('\n', nextChangedEnd);
    final oldSegmentEnd =
        oldFollowingBreak < 0 ? oldText.length : oldFollowingBreak;
    final nextSegmentEnd =
        nextFollowingBreak < 0 ? nextText.length : nextFollowingBreak;

    final startLine = _lineIndexAtOffset(startOffset);
    final oldEndLine = _lineIndexAtOffset(oldSegmentEnd);
    final removedLineCount = oldEndLine - startLine + 1;
    final replacement =
        nextText.substring(startOffset, nextSegmentEnd).split('\n');

    _lines.replaceRange(
      startLine,
      startLine + removedLineCount,
      replacement,
    );

    final replacementStarts = <int>[];
    var lineOffset = startOffset;
    for (final line in replacement) {
      replacementStarts.add(lineOffset);
      lineOffset += line.length + 1;
    }
    _lineStarts.replaceRange(
      startLine,
      startLine + removedLineCount,
      replacementStarts,
    );
    final offsetDelta = nextText.length - oldText.length;
    for (var index = startLine + replacement.length;
        index < _lineStarts.length;
        index++) {
      _lineStarts[index] += offsetDelta;
    }

    _text = nextText;
    debugLastChangedLineCount = replacement.length;
    return YamlDocumentLineChange(
      startLine: startLine,
      removedLineCount: removedLineCount,
      addedLineCount: replacement.length,
    );
  }

  int _lineIndexAtOffset(int offset) {
    var low = 0;
    var high = _lineStarts.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_lineStarts[middle] <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return math.max(0, low - 1);
  }

  static List<int> _buildLineStarts(String text) {
    final starts = <int>[0];
    for (var index = 0; index < text.length; index++) {
      if (text.codeUnitAt(index) == 0x0A) starts.add(index + 1);
    }
    return starts;
  }
}

class YamlDocumentWidthCache {
  final YamlDocumentMetricsController _document;
  final List<double> _widths = [];
  final SplayTreeMap<double, int> _widthIndex = SplayTreeMap();
  TextStyle? _style;
  double? _textScale;
  double _characterWidth = 0;
  int debugLastMeasuredLineCount = 0;

  YamlDocumentWidthCache({YamlDocumentMetricsController? document})
      : _document = document ?? YamlDocumentMetricsController();

  void clear() {
    _widths.clear();
    _widthIndex.clear();
    _style = null;
    _textScale = null;
    _characterWidth = 0;
    debugLastMeasuredLineCount = 0;
  }

  double update({
    required String text,
    required TextStyle style,
    required TextScaler textScaler,
    required double horizontalPadding,
  }) {
    final scale = textScaler.scale(1);
    final styleChanged = _style != style || _textScale != scale;
    if (styleChanged) {
      if (_document.text != text) _document.replaceText(text);
      _widths.clear();
      _widthIndex.clear();
      final painter = TextPainter(
        text: TextSpan(text: 'M', style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      _characterWidth = painter.width;
      for (final line in _document.lines) {
        final width = _estimatedLineWidth(line);
        _widths.add(width);
        _addWidth(width);
      }
      debugLastMeasuredLineCount = _document.lineCount;
      _style = style;
      _textScale = scale;
    } else {
      final change = _document.updateText(text);
      if (change != null) {
        final removed = _widths.sublist(
          change.startLine,
          change.startLine + change.removedLineCount,
        );
        for (final width in removed) {
          _removeWidth(width);
        }
        final added = <double>[];
        final lines = _document.lines;
        for (var index = change.startLine;
            index < change.startLine + change.addedLineCount;
            index++) {
          final width = _estimatedLineWidth(lines[index]);
          added.add(width);
          _addWidth(width);
        }
        _widths.replaceRange(
          change.startLine,
          change.startLine + change.removedLineCount,
          added,
        );
        debugLastMeasuredLineCount = change.addedLineCount;
      } else {
        debugLastMeasuredLineCount = 0;
      }
    }

    final longest = _widthIndex.isEmpty ? 0.0 : _widthIndex.lastKey()!;
    return horizontalPadding + longest;
  }

  double _estimatedLineWidth(String line) {
    var columns = 0;
    for (final rune in line.runes) {
      if (rune == 0x09) {
        final remainder = columns % YamlIndentGuideModel.indentSize;
        columns += remainder == 0
            ? YamlIndentGuideModel.indentSize
            : YamlIndentGuideModel.indentSize - remainder;
      } else {
        columns += rune > 0xFF ? 2 : 1;
      }
    }
    return columns * _characterWidth;
  }

  void _addWidth(double width) {
    _widthIndex.update(width, (count) => count + 1, ifAbsent: () => 1);
  }

  void _removeWidth(double width) {
    final count = _widthIndex[width];
    if (count == null) return;
    if (count <= 1) {
      _widthIndex.remove(width);
    } else {
      _widthIndex[width] = count - 1;
    }
  }
}

class YamlDocumentHorizontalScrollController extends ScrollController {
  double _documentWidth = 0;

  double get documentWidth => _documentWidth;

  bool updateDocumentWidth(double width) {
    final nextWidth = math.max(0.0, width);
    if ((nextWidth - _documentWidth).abs() < 0.01) return false;
    _documentWidth = nextWidth;
    return true;
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _YamlDocumentHorizontalScrollPosition(
      owner: this,
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _YamlDocumentHorizontalScrollPosition
    extends ScrollPositionWithSingleContext {
  final YamlDocumentHorizontalScrollController owner;

  _YamlDocumentHorizontalScrollPosition({
    required this.owner,
    required super.physics,
    required super.context,
    required double initialPixels,
    required super.keepScrollOffset,
    required super.oldPosition,
    required super.debugLabel,
  }) : super(initialPixels: initialPixels);

  double get _documentMaxExtent {
    if (!hasViewportDimension) return 0;
    return math.max(0, owner.documentWidth - viewportDimension);
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final nextMax = math.max(maxScrollExtent, _documentMaxExtent);
    if (hasPixels && pixels > nextMax) {
      correctPixels(nextMax);
    }
    return super.applyContentDimensions(
      minScrollExtent,
      nextMax,
    );
  }
}

class YamlLineNumberPainter extends CustomPainter {
  static const _lineHeight = 13.0 * 1.46;
  static const _topPadding = 10.0;

  final int lineCount;
  final int cursorLine;
  final double verticalOffset;
  final double gutterWidth;

  const YamlLineNumberPainter({
    required this.lineCount,
    required this.cursorLine,
    required this.verticalOffset,
    required this.gutterWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(gutterWidth - 0.5, 0),
      Offset(gutterWidth - 0.5, size.height),
      Paint()
        ..color = _YamlEditorSurface._border
        ..strokeWidth = 1,
    );

    final first = (((verticalOffset - _topPadding) / _lineHeight).floor())
        .clamp(0, lineCount - 1)
        .toInt();
    final visibleEnd =
        ((verticalOffset + size.height) / _lineHeight).ceil() + 1;
    final last = visibleEnd.clamp(first + 1, lineCount).toInt();
    for (var index = first; index < last; index++) {
      final line = index + 1;
      final painter = TextPainter(
        text: TextSpan(
          text: '$line',
          style: TextStyle(
            fontSize: 12,
            height: 1.46,
            fontFamily: 'ProxlyMono',
            color: line == cursorLine
                ? _YamlEditorSurface._text
                : _YamlEditorSurface._muted,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          gutterWidth -
              YamlEditorLayoutMetrics.lineNumberHorizontalPadding -
              YamlEditorLayoutMetrics.dividerWidth -
              painter.width,
          _topPadding + index * _lineHeight - verticalOffset,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant YamlLineNumberPainter oldDelegate) {
    return oldDelegate.lineCount != lineCount ||
        oldDelegate.cursorLine != cursorLine ||
        oldDelegate.verticalOffset != verticalOffset ||
        oldDelegate.gutterWidth != gutterWidth;
  }
}

// Re-Editor briefly attaches both old and new horizontal scroll views when its
// empty-document hint disappears. Paint against the newest attached position
// instead of ScrollController.offset, which requires exactly one position.
double _yamlScrollOffset(ScrollController controller) {
  for (final position in controller.positions.toList().reversed) {
    if (position.hasPixels) return position.pixels;
  }
  return 0;
}

class YamlLineNumberLayer extends StatelessWidget {
  final CodeLineEditingController controller;
  final CodeScrollController scrollController;
  final int cursorLine;
  final double gutterWidth;

  const YamlLineNumberLayer({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.cursorLine,
    required this.gutterWidth,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          scrollController.horizontalScroller,
          scrollController.verticalScroller,
        ]),
        builder: (context, child) {
          final horizontal =
              _yamlScrollOffset(scrollController.horizontalScroller);
          final vertical = _yamlScrollOffset(scrollController.verticalScroller);
          return Transform.translate(
            key: const ValueKey('yaml_line_numbers_horizontal_offset'),
            offset: Offset(-horizontal, 0),
            child: CustomPaint(
              painter: YamlLineNumberPainter(
                lineCount: controller.lineCount,
                cursorLine: cursorLine,
                verticalOffset: vertical,
                gutterWidth: gutterWidth,
              ),
            ),
          );
        },
      ),
    );
  }
}

@immutable
class YamlIndentGuideBlock {
  final int level;
  final int startLine;
  final int endLine;
  final int guideColumn;

  const YamlIndentGuideBlock({
    required this.level,
    required this.startLine,
    required this.endLine,
    required this.guideColumn,
  });

  bool containsLine(int line) => line >= startLine && line < endLine;
}

@immutable
class YamlIndentGuideModel {
  static const indentSize = 2;
  static const maxDepth = 64;

  final List<String> lines;
  final List<int> depths;
  final List<List<YamlIndentGuideBlock>> _blocksByLevel;

  const YamlIndentGuideModel._({
    required this.lines,
    required this.depths,
    required List<List<YamlIndentGuideBlock>> blocksByLevel,
  }) : _blocksByLevel = blocksByLevel;

  factory YamlIndentGuideModel.fromText(String text) {
    return YamlIndentGuideModel.fromLines(text.split('\n'));
  }

  factory YamlIndentGuideModel.fromLines(List<String> sourceLines) {
    final lines = List<String>.of(sourceLines, growable: false);
    final rawDepths = List<int>.filled(lines.length, -1);

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final columns = _leadingIndentColumns(lines[lineIndex]);
      if (columns == null) continue;
      rawDepths[lineIndex] = (columns ~/ indentSize).clamp(0, maxDepth).toInt();
    }

    final previousDepths = List<int?>.filled(lines.length, null);
    final nextDepths = List<int?>.filled(lines.length, null);
    int? previous;
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      previousDepths[lineIndex] = previous;
      if (rawDepths[lineIndex] >= 0) previous = rawDepths[lineIndex];
    }
    int? next;
    for (var lineIndex = lines.length - 1; lineIndex >= 0; lineIndex--) {
      nextDepths[lineIndex] = next;
      if (rawDepths[lineIndex] >= 0) next = rawDepths[lineIndex];
    }

    final depths = List<int>.from(rawDepths);
    for (var lineIndex = 0; lineIndex < depths.length; lineIndex++) {
      if (depths[lineIndex] >= 0) continue;
      final before = previousDepths[lineIndex];
      final after = nextDepths[lineIndex];
      depths[lineIndex] =
          before == null || after == null ? 0 : math.min(before, after);
    }

    final blocksByLevel = List.generate(
      maxDepth + 1,
      (_) => <YamlIndentGuideBlock>[],
    );
    final activeStarts = List<int?>.filled(maxDepth + 1, null);
    var previousDepth = 0;

    for (var lineIndex = 0; lineIndex < depths.length; lineIndex++) {
      final depth = depths[lineIndex];
      if (depth < previousDepth) {
        for (var level = previousDepth; level > depth; level--) {
          final startLine = activeStarts[level];
          if (startLine != null) {
            blocksByLevel[level].add(
              YamlIndentGuideBlock(
                level: level,
                startLine: startLine,
                endLine: lineIndex,
                guideColumn: level * indentSize,
              ),
            );
            activeStarts[level] = null;
          }
        }
      } else if (depth > previousDepth) {
        for (var level = previousDepth + 1; level <= depth; level++) {
          activeStarts[level] = lineIndex;
        }
      }
      previousDepth = depth;
    }

    for (var level = previousDepth; level > 0; level--) {
      final startLine = activeStarts[level];
      if (startLine != null) {
        blocksByLevel[level].add(
          YamlIndentGuideBlock(
            level: level,
            startLine: startLine,
            endLine: lines.length,
            guideColumn: level * indentSize,
          ),
        );
      }
    }

    return YamlIndentGuideModel._(
      lines: List.unmodifiable(lines),
      depths: List.unmodifiable(depths),
      blocksByLevel: List<List<YamlIndentGuideBlock>>.unmodifiable(
        blocksByLevel.map<List<YamlIndentGuideBlock>>(
          (blocks) => List<YamlIndentGuideBlock>.unmodifiable(blocks),
        ),
      ),
    );
  }

  static int? _leadingIndentColumns(String line) {
    var columns = 0;
    for (final unit in line.codeUnits) {
      if (unit == 0x20) {
        columns++;
      } else if (unit == 0x09) {
        final remainder = columns % indentSize;
        columns += remainder == 0 ? indentSize : indentSize - remainder;
      } else {
        return columns;
      }
    }
    return null;
  }

  int depthForLine(int line) {
    if (line < 0 || line >= depths.length) return 0;
    return depths[line];
  }

  List<YamlIndentGuideBlock> blocksAtLevel(int level) {
    if (level <= 0 || level >= _blocksByLevel.length) return const [];
    return _blocksByLevel[level];
  }

  Iterable<YamlIndentGuideBlock> visibleBlocks(
    int startLine,
    int endLine,
  ) sync* {
    if (startLine >= endLine) return;
    for (var level = 1; level < _blocksByLevel.length; level++) {
      final blocks = _blocksByLevel[level];
      var low = 0;
      var high = blocks.length;
      while (low < high) {
        final middle = (low + high) >> 1;
        if (blocks[middle].endLine <= startLine) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      for (var index = low; index < blocks.length; index++) {
        final block = blocks[index];
        if (block.startLine >= endLine) break;
        yield block;
      }
    }
  }
}

class YamlIndentGuidePainter extends CustomPainter {
  static const _lineHeight = 13.0 * 1.46;
  static const _topPadding = 10.0;

  final YamlIndentGuideModel model;
  final int activeLine;
  final double horizontalOffset;
  final double verticalOffset;
  final double codeLeftPadding;
  final double characterWidth;
  final double devicePixelRatio;

  const YamlIndentGuidePainter({
    required this.model,
    required this.activeLine,
    required this.horizontalOffset,
    required this.verticalOffset,
    required this.codeLeftPadding,
    required this.characterWidth,
    this.devicePixelRatio = 1,
  });

  static double guideX({
    required int guideColumn,
    required double codeLeftPadding,
    required double characterWidth,
    double horizontalOffset = 0,
  }) {
    return codeLeftPadding +
        (guideColumn - YamlIndentGuideModel.indentSize) * characterWidth -
        horizontalOffset;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (model.lines.isEmpty) return;
    final first = (((verticalOffset - _topPadding) / _lineHeight).floor())
        .clamp(0, model.lines.length - 1)
        .toInt();
    final visibleEnd =
        ((verticalOffset + size.height) / _lineHeight).ceil() + 1;
    final last = visibleEnd.clamp(first + 1, model.lines.length).toInt();
    final physicalPixel = 1 / devicePixelRatio;
    final inactivePaint = Paint()
      ..color = _YamlEditorSurface._muted.withValues(alpha: 0.20)
      ..strokeWidth = physicalPixel;
    final activePaint = Paint()
      ..color = _YamlEditorSurface._muted.withValues(alpha: 0.58)
      ..strokeWidth = physicalPixel;
    final activeDepth = model.depthForLine(activeLine);

    for (final block in model.visibleBlocks(first, last)) {
      final rawX = guideX(
        guideColumn: block.guideColumn,
        codeLeftPadding: codeLeftPadding,
        characterWidth: characterWidth,
        horizontalOffset: horizontalOffset,
      );
      final x = (rawX * devicePixelRatio).floorToDouble() / devicePixelRatio +
          physicalPixel / 2;
      if (x < 0 || x > size.width) continue;

      final startLine = math.max(block.startLine, first);
      final endLine = math.min(block.endLine, last);
      final top = _topPadding + startLine * _lineHeight - verticalOffset;
      final bottom = _topPadding + endLine * _lineHeight - verticalOffset;
      final isActive =
          block.level == activeDepth && block.containsLine(activeLine);
      canvas.drawLine(
        Offset(x, top),
        Offset(x, bottom),
        isActive ? activePaint : inactivePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant YamlIndentGuidePainter oldDelegate) {
    return oldDelegate.model != model ||
        oldDelegate.activeLine != activeLine ||
        oldDelegate.horizontalOffset != horizontalOffset ||
        oldDelegate.verticalOffset != verticalOffset ||
        oldDelegate.codeLeftPadding != codeLeftPadding ||
        oldDelegate.characterWidth != characterWidth ||
        oldDelegate.devicePixelRatio != devicePixelRatio;
  }
}

class YamlIndentGuideLayer extends StatefulWidget {
  final CodeLineEditingController controller;
  final CodeScrollController scrollController;
  final YamlEditorLayoutMetrics metrics;
  final YamlDocumentMetricsController document;

  const YamlIndentGuideLayer({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.metrics,
    required this.document,
  });

  @override
  State<YamlIndentGuideLayer> createState() => _YamlIndentGuideLayerState();
}

class _YamlIndentGuideLayerState extends State<YamlIndentGuideLayer> {
  static const _backgroundAnalysisThreshold = 256 * 1024;

  late String _text;
  late YamlDocumentMetricsController _document;
  late YamlIndentGuideModel _model;
  late int _activeLine;
  Timer? _analysisTimer;
  int _analysisRevision = 0;

  @override
  void initState() {
    super.initState();
    _readController(rebuild: false);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant YamlIndentGuideLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    _readController(rebuild: false);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    _analysisRevision++;
    _analysisTimer?.cancel();
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() => _readController(rebuild: true);

  void _readController({required bool rebuild}) {
    final nextText = widget.controller.text;
    final nextActiveLine = widget.controller.selection.extentIndex
        .clamp(0, math.max(0, widget.controller.lineCount - 1))
        .toInt();
    final textChanged = !rebuild || nextText != _text;
    final activeLineChanged = !rebuild || nextActiveLine != _activeLine;
    if (!textChanged && !activeLineChanged) return;

    if (textChanged) {
      _text = nextText;
      if (!rebuild) {
        _analysisTimer?.cancel();
        _document = widget.document;
        if (_document.text != nextText) _document.replaceText(nextText);
        if (nextText.length >= _backgroundAnalysisThreshold) {
          _model = YamlIndentGuideModel.fromText('');
          _scheduleIndentAnalysis(Duration.zero);
        } else {
          _model = YamlIndentGuideModel.fromLines(_document.lines);
        }
      } else {
        _document.updateText(nextText);
        _scheduleIndentAnalysis(const Duration(milliseconds: 75));
      }
    }
    _activeLine = nextActiveLine;
    if (rebuild && mounted) setState(() {});
  }

  void _scheduleIndentAnalysis(Duration delay) {
    _analysisTimer?.cancel();
    final revision = ++_analysisRevision;
    _analysisTimer = Timer(delay, () async {
      final snapshot = List<String>.of(_document.lines, growable: false);
      final nextModel = _document.text.length >= _backgroundAnalysisThreshold
          ? await Isolate.run(() => YamlIndentGuideModel.fromLines(snapshot))
          : YamlIndentGuideModel.fromLines(snapshot);
      if (!mounted || revision != _analysisRevision) return;
      _model = nextModel;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          widget.scrollController.horizontalScroller,
          widget.scrollController.verticalScroller,
        ]),
        builder: (context, child) {
          final horizontal =
              _yamlScrollOffset(widget.scrollController.horizontalScroller);
          final vertical =
              _yamlScrollOffset(widget.scrollController.verticalScroller);
          return CustomPaint(
            key: const ValueKey('yaml_indent_guides'),
            painter: YamlIndentGuidePainter(
              model: _model,
              activeLine: _activeLine,
              horizontalOffset: horizontal,
              verticalOffset: vertical,
              codeLeftPadding: widget.metrics.codeLeftPadding,
              characterWidth: widget.metrics.characterWidth,
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            ),
          );
        },
      ),
    );
  }
}

class _YamlEditorSurface extends StatefulWidget {
  final CodeLineEditingController controller;
  final CodeScrollController scrollController;
  final YamlDocumentHorizontalScrollController horizontalScrollController;
  final FocusNode focusNode;
  final SelectionToolbarController toolbarController;
  final bool loading;
  final bool enabled;
  final int cursorLine;

  const _YamlEditorSurface({
    required this.controller,
    required this.scrollController,
    required this.horizontalScrollController,
    required this.focusNode,
    required this.toolbarController,
    required this.loading,
    required this.enabled,
    required this.cursorLine,
  });

  static const _editorBg = Color(0xFF1E1E1E);
  static const _titleBg = Color(0xFF151515);
  static const _sideBg = Color(0xFF252526);
  static const _border = Color(0xFF3C3C3C);
  static const _text = Color(0xFFD4D4D4);
  static const _muted = Color(0xFF858585);
  static const _blue = Color(0xFF007ACC);
  static const _green = Color(0xFF6A9955);
  static const _selection = Color(0xFF264F78);
  static const _lineHighlight = Color(0xFF2A2D2E);

  @override
  State<_YamlEditorSurface> createState() => _YamlEditorSurfaceState();
}

class _YamlEditorSurfaceState extends State<_YamlEditorSurface> {
  late YamlDocumentMetricsController _document;
  late YamlDocumentWidthCache _widthCache;
  bool _extentUpdateScheduled = false;
  int _extentRevision = 0;

  @override
  void initState() {
    super.initState();
    _document = YamlDocumentMetricsController(widget.controller.text);
    _widthCache = YamlDocumentWidthCache(document: _document);
    widget.controller.addListener(_scheduleExtentUpdate);
  }

  @override
  void didUpdateWidget(covariant _YamlEditorSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleExtentUpdate);
      widget.controller.addListener(_scheduleExtentUpdate);
      _document = YamlDocumentMetricsController(widget.controller.text);
      _widthCache = YamlDocumentWidthCache(document: _document);
    }
    _scheduleExtentUpdate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _widthCache.clear();
    _scheduleExtentUpdate();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleExtentUpdate);
    super.dispose();
  }

  void _scheduleExtentUpdate() {
    if (_extentUpdateScheduled) return;
    _extentUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _extentUpdateScheduled = false;
      if (!mounted) return;
      final metrics =
          YamlEditorLayoutMetrics.forLineCount(widget.controller.lineCount);
      final contentWidth = _widthCache.update(
        text: widget.controller.text,
        style: const TextStyle(
          fontSize: YamlEditorLayoutMetrics.codeFontSize,
          fontFamily: 'ProxlyMono',
        ),
        textScaler: MediaQuery.textScalerOf(context),
        horizontalPadding: metrics.codeLeftPadding + 16,
      );
      if (widget.horizontalScrollController.updateDocumentWidth(contentWidth)) {
        setState(() => _extentRevision++);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final metrics =
        YamlEditorLayoutMetrics.forLineCount(widget.controller.lineCount);
    _scheduleExtentUpdate();
    return ColoredBox(
      key: const ValueKey('yaml_editor_fullscreen_surface'),
      color: _YamlEditorSurface._editorBg,
      child: widget.loading
          ? const Center(
              child: CircularProgressIndicator(
                color: _YamlEditorSurface._blue,
              ),
            )
          : Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: CodeEditor(
                    controller: widget.controller,
                    scrollController: widget.scrollController,
                    focusNode: widget.focusNode,
                    toolbarController: widget.toolbarController,
                    autofocus: false,
                    readOnly: !widget.enabled,
                    showCursorWhenReadOnly: true,
                    wordWrap: false,
                    hint: tr('编辑 YAML 配置'),
                    padding: EdgeInsets.fromLTRB(
                      metrics.codeLeftPadding,
                      10,
                      16 + (_extentRevision.isOdd ? 0.001 : 0),
                      16,
                    ),
                    verticalScrollbarWidth: 8,
                    horizontalScrollbarHeight: 8,
                    chunkAnalyzer: NonCodeChunkAnalyzer(),
                    style: CodeEditorStyle(
                      fontSize: 13,
                      fontHeight: 1.46,
                      fontFamily: 'ProxlyMono',
                      textColor: _YamlEditorSurface._text,
                      hintTextColor: _YamlEditorSurface._green,
                      backgroundColor: _YamlEditorSurface._editorBg,
                      selectionColor: _YamlEditorSurface._selection,
                      cursorColor: Color(0xFFAEAFAD),
                      cursorLineColor: _YamlEditorSurface._lineHighlight,
                      codeTheme: CodeHighlightTheme(
                        languages: {
                          'yaml': CodeHighlightThemeMode(mode: langYaml),
                          'yml': CodeHighlightThemeMode(mode: langYaml),
                        },
                        theme: atomOneDarkTheme,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  bottom: 8,
                  child: YamlIndentGuideLayer(
                    controller: widget.controller,
                    scrollController: widget.scrollController,
                    metrics: metrics,
                    document: _document,
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 8,
                  width: metrics.gutterWidth,
                  child: YamlLineNumberLayer(
                    controller: widget.controller,
                    scrollController: widget.scrollController,
                    cursorLine: widget.cursorLine,
                    gutterWidth: metrics.gutterWidth,
                  ),
                ),
              ],
            ),
    );
  }
}

class YamlEditorSelectionToolbar extends StatelessWidget {
  final TextSelectionToolbarAnchors anchors;
  final CodeLineEditingController controller;
  final bool editable;
  final FocusNode focusNode;
  final VoidCallback onDismiss;

  const YamlEditorSelectionToolbar({
    super.key,
    required this.anchors,
    required this.controller,
    required this.editable,
    required this.focusNode,
    required this.onDismiss,
  });

  void _finish(VoidCallback action) {
    action();
    onDismiss();
    if (!focusNode.hasFocus) focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = !controller.selection.isCollapsed;
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: anchors,
      buttonItems: [
        if (editable && hasSelection)
          ContextMenuButtonItem(
            type: ContextMenuButtonType.cut,
            onPressed: () => _finish(controller.cut),
          ),
        if (hasSelection)
          ContextMenuButtonItem(
            type: ContextMenuButtonType.copy,
            onPressed: () => _finish(() => unawaited(controller.copy())),
          ),
        if (editable)
          ContextMenuButtonItem(
            type: ContextMenuButtonType.paste,
            onPressed: () => _finish(controller.paste),
          ),
        ContextMenuButtonItem(
          type: ContextMenuButtonType.selectAll,
          onPressed: () => _finish(controller.selectAll),
        ),
      ],
    );
  }
}

class YamlEditorShortcutBar extends StatelessWidget {
  final CodeLineEditingController controller;
  final FocusNode focusNode;
  final bool enabled;

  const YamlEditorShortcutBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
  });

  void _run(VoidCallback action) {
    if (!enabled) return;
    action();
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    return CodeEditorTapRegion(
      child: TextFieldTapRegion(
        child: ExcludeFocus(
          child: Container(
            key: const ValueKey('yaml_editor_shortcut_bar'),
            height: 80,
            decoration: const BoxDecoration(
              color: _YamlEditorSurface._sideBg,
              border: Border(
                top: BorderSide(color: _YamlEditorSurface._border, width: 1),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Row(
                children: [
                  _EditorFunctionPad(
                    enabled: enabled,
                    onIndent: () => _run(() {
                      controller.applyIndent();
                      controller.applyIndent();
                    }),
                  ),
                  const _ShortcutDivider(),
                  _EditorArrowPad(
                    enabled: enabled,
                    onMove: (direction) => _run(
                      () => controller.moveCursor(direction),
                    ),
                  ),
                  const _ShortcutDivider(),
                  Expanded(
                    child: _EditorSymbolPad(
                      enabled: enabled,
                      onInsert: (symbol) => _run(
                        () => controller.replaceSelection(symbol),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorFunctionPad extends StatelessWidget {
  final bool enabled;
  final VoidCallback onIndent;

  const _EditorFunctionPad({
    required this.enabled,
    required this.onIndent,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 68,
      child: Center(
        child: _EditorTextKey(
          key: const ValueKey('yaml_key_tab'),
          label: 'TAB',
          tooltip: tr('增加缩进'),
          enabled: enabled,
          onPressed: onIndent,
        ),
      ),
    );
  }
}

class _EditorArrowPad extends StatelessWidget {
  final bool enabled;
  final ValueChanged<AxisDirection> onMove;

  const _EditorArrowPad({required this.enabled, required this.onMove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 108,
      height: 68,
      child: Stack(
        children: [
          Positioned(
            left: 36,
            top: 0,
            child: _EditorRepeatIconKey(
              key: const ValueKey('yaml_key_up'),
              icon: Icons.keyboard_arrow_up_rounded,
              tooltip: tr('光标上移'),
              enabled: enabled,
              onPressed: () => onMove(AxisDirection.up),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            child: _EditorRepeatIconKey(
              key: const ValueKey('yaml_key_left'),
              icon: Icons.keyboard_arrow_left_rounded,
              tooltip: tr('光标左移'),
              enabled: enabled,
              onPressed: () => onMove(AxisDirection.left),
            ),
          ),
          Positioned(
            left: 36,
            bottom: 0,
            child: _EditorRepeatIconKey(
              key: const ValueKey('yaml_key_down'),
              icon: Icons.keyboard_arrow_down_rounded,
              tooltip: tr('光标下移'),
              enabled: enabled,
              onPressed: () => onMove(AxisDirection.down),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: _EditorRepeatIconKey(
              key: const ValueKey('yaml_key_right'),
              icon: Icons.keyboard_arrow_right_rounded,
              tooltip: tr('光标右移'),
              enabled: enabled,
              onPressed: () => onMove(AxisDirection.right),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorSymbolPad extends StatelessWidget {
  static const _topRow = ['-', ':', '"', "'"];
  static const _bottomRow = ['[', ']', '#', '|'];

  final bool enabled;
  final ValueChanged<String> onInsert;

  const _EditorSymbolPad({required this.enabled, required this.onInsert});

  Widget _row(Iterable<String> symbols) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final symbol in symbols)
          Expanded(
            child: _EditorTextKey(
              key: ValueKey('yaml_key_$symbol'),
              label: symbol,
              tooltip: tr('插入 $symbol'),
              enabled: enabled,
              onPressed: () => onInsert(symbol),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_row(_topRow), _row(_bottomRow)],
      ),
    );
  }
}

class _EditorTextKey extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  const _EditorTextKey({
    super.key,
    required this.label,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 38, minHeight: 34),
              child: Center(
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: enabled
                        ? _YamlEditorSurface._text
                        : _YamlEditorSurface._muted,
                    fontSize: label == 'TAB' ? 12 : 16,
                    fontFamily: 'ProxlyMono',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorRepeatIconKey extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  const _EditorRepeatIconKey({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  @override
  State<_EditorRepeatIconKey> createState() => _EditorRepeatIconKeyState();
}

class _EditorRepeatIconKeyState extends State<_EditorRepeatIconKey> {
  Timer? _repeatTimer;

  @override
  void didUpdateWidget(covariant _EditorRepeatIconKey oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) _stopRepeating();
  }

  @override
  void dispose() {
    _stopRepeating();
    super.dispose();
  }

  void _startRepeating() {
    if (!widget.enabled) return;
    widget.onPressed();
    _repeatTimer?.cancel();
    _repeatTimer = Timer.periodic(
      const Duration(milliseconds: 75),
      (_) => widget.onPressed(),
    );
  }

  void _stopRepeating() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onPressed : null,
        onLongPressStart: widget.enabled ? (_) => _startRepeating() : null,
        onLongPressEnd: widget.enabled ? (_) => _stopRepeating() : null,
        onLongPressCancel: widget.enabled ? _stopRepeating : null,
        child: SizedBox(
          width: 36,
          height: 34,
          child: Icon(
            widget.icon,
            size: 22,
            color: widget.enabled
                ? _YamlEditorSurface._text
                : _YamlEditorSurface._muted,
          ),
        ),
      ),
    );
  }
}

class _ShortcutDivider extends StatelessWidget {
  const _ShortcutDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: _YamlEditorSurface._border,
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String message;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  const _InfoBanner({
    required this.message,
    required this.color,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    return Container(
      margin: compact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: compact ? 8 : 11,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: compact ? BorderRadius.zero : BorderRadius.circular(12),
        border: compact
            ? Border(
                bottom: BorderSide(
                  color: color.withValues(alpha: 0.32),
                  width: 0.6,
                ),
              )
            : Border.all(
                color: color.withValues(alpha: 0.32),
                width: 0.6,
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              tr(message),
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 10),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: color,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: AdaptiveSingleLineText(tr(actionLabel!)),
            ),
          ],
        ],
      ),
    );
  }
}
