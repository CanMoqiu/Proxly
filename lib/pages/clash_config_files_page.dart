import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

enum _ExitChoice { cancel, discard, save }

class YamlRestartAfterSaveDialog extends StatelessWidget {
  const YamlRestartAfterSaveDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('确认重启 OpenClash')),
      content: Text(tr('配置已保存，是否立即重启 OpenClash 使修改生效？')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: AdaptiveSingleLineText(tr('稍后')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: AdaptiveSingleLineText(tr('立即重启')),
        ),
      ],
    );
  }
}

class _PickedFileTooLargeException implements Exception {
  const _PickedFileTooLargeException();
}

class ClashConfigFilesPage extends StatefulWidget {
  const ClashConfigFilesPage({super.key});

  @override
  State<ClashConfigFilesPage> createState() => _ClashConfigFilesPageState();
}

class _ClashConfigFilesPageState extends State<ClashConfigFilesPage>
    with TransientFeedbackStateMixin<ClashConfigFilesPage> {
  final _restartCoordinator = OpenClashRestartCoordinator.instance;
  List<ClashConfigFile> _files = [];
  bool _loadingFiles = false;
  bool _uploading = false;
  bool _restarting = false;
  bool _errorNeedsSettings = false;
  String? _activeConfigPath;
  String? _openSwipePath;
  String? _busyFilePath;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshFiles());
  }

  @override
  void dispose() {
    disposeTransientFeedback();
    super.dispose();
  }

  void _clearOperationFeedback() {
    cancelFeedbackClear('file_operation');
    _errorNeedsSettings = false;
    _error = null;
    _message = null;
  }

  void _scheduleOperationFeedback({required bool isError}) {
    scheduleFeedbackClear(
      'file_operation',
      isError: isError,
      clear: () => setState(() {
        _errorNeedsSettings = false;
        _error = null;
        _message = null;
      }),
    );
  }

  Future<void> _refreshFiles() async {
    cancelFeedbackClear('file_operation');
    setState(() {
      _loadingFiles = true;
      _errorNeedsSettings = false;
      _error = null;
      _message = null;
    });
    try {
      final files = await ClashConfigFileService.listFiles();
      ClashActiveConfig? activeConfig;
      try {
        activeConfig = await ClashConfigFileService.getActiveConfig();
      } catch (_) {
        activeConfig = null;
      }
      if (!mounted) return;
      setState(() {
        _files = files;
        _activeConfigPath = ClashConfigFileService.matchActiveConfigPath(
          files,
          activeConfig,
        );
        _message = files.isEmpty ? '没有找到 YAML 配置文件，可上传新配置。' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _formatError('读取配置列表', e));
      _scheduleOperationFeedback(isError: true);
    } finally {
      if (mounted) setState(() => _loadingFiles = false);
    }
  }

  Future<void> _openFile(ClashConfigFile file) async {
    if (_consumeOpenSwipe()) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ClashConfigEditorPage(file: file)),
    );
    if (!mounted) return;
    if (changed == true) {
      await _promptRestartAfterSave(file);
    }
  }

  Future<void> _promptRestartAfterSave(ClashConfigFile file) async {
    cancelFeedbackClear('file_operation');
    setState(() {
      _errorNeedsSettings = false;
      _error = null;
      _message = '已保存 ${file.name}';
    });
    final restart = await showDialog<bool>(
      context: context,
      builder: (_) => const YamlRestartAfterSaveDialog(),
    );
    if (!mounted) return;
    if (restart != true) {
      _scheduleOperationFeedback(isError: false);
      return;
    }

    setState(() {
      _restarting = true;
      _message = '正在重启 OpenClash...';
    });
    final result = await _restartCoordinator.restart(
      reason: OpenClashRestartReason.yamlEditor,
    );
    if (!mounted) return;
    setState(() {
      _restarting = false;
      if (result.success) {
        _message = 'OpenClash 重启成功';
      } else {
        _message = null;
        _error = _formatError(
          '重启 OpenClash',
          result.error ?? '未知错误',
        );
      }
    });
    _scheduleOperationFeedback(isError: !result.success);
  }

  Future<void> _uploadConfig() async {
    if (_consumeOpenSwipe()) return;
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
        withReadStream: true,
        dialogTitle: tr('选择 YAML 配置文件'),
      );
    } on PlatformException catch (e) {
      _showSnack('打开文件选择器失败：${e.message ?? e.code}', success: false);
      return;
    } catch (e) {
      _showSnack('打开文件选择器失败：$e', success: false);
      return;
    }
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;

    final picked = result.files.first;
    if (!ClashConfigFileService.isYamlPath(picked.name)) {
      _showSnack('请选择 .yaml 或 .yml 文件', success: false);
      return;
    }
    if (picked.size > ClashConfigFileService.maxConfigBytes) {
      _showSnack('文件超过 5 MB 限制', success: false);
      return;
    }
    late final Uint8List bytes;
    try {
      final readBytes = await _readPickedFileBytes(picked);
      if (readBytes == null) {
        _showSnack('读取本地文件失败', success: false);
        return;
      }
      bytes = readBytes;
    } on _PickedFileTooLargeException {
      _showSnack('文件超过 5 MB 限制', success: false);
      return;
    } catch (e) {
      _showSnack('读取本地文件失败：$e', success: false);
      return;
    }

    final fileName = await _showFileNameDialog(initialValue: picked.name);
    if (fileName == null) return;
    late final String normalizedPath;
    try {
      normalizedPath = ClashConfigFileService.uploadPathForFileName(fileName);
    } catch (_) {
      _showSnack('文件名无效，请输入 .yaml 或 .yml 文件名', success: false);
      return;
    }

    setState(() {
      _uploading = true;
      _clearOperationFeedback();
    });
    try {
      await ClashConfigFileService.writeFileBytes(
        normalizedPath,
        Uint8List.fromList(bytes),
      );
      if (!mounted) return;
      final uploaded = ClashConfigFile(path: normalizedPath);
      setState(() {
        if (!_files.any((file) => file.path == normalizedPath)) {
          _files = [..._files, uploaded]
            ..sort((a, b) => a.path.compareTo(b.path));
        }
        _message = '已上传 ${uploaded.name}';
      });
      _scheduleOperationFeedback(isError: false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _formatError('上传', e));
      _scheduleOperationFeedback(isError: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<Uint8List?> _readPickedFileBytes(PlatformFile picked) async {
    final directBytes = picked.bytes;
    if (directBytes != null) return directBytes;

    final stream = picked.readStream;
    if (stream != null) {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        if (builder.length + chunk.length >
            ClashConfigFileService.maxConfigBytes) {
          throw const _PickedFileTooLargeException();
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    }

    final path = picked.path;
    if (path == null) return null;
    final file = File(path);
    if (await file.length() > ClashConfigFileService.maxConfigBytes) {
      throw const _PickedFileTooLargeException();
    }
    return file.readAsBytes();
  }

  Future<String?> _showFileNameDialog({
    required String initialValue,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => YamlUploadFileNameDialog(initialValue: initialValue),
    );
  }

  Future<void> _renameConfig(ClashConfigFile file) async {
    _closeOpenSwipe();
    final fileName = await showDialog<String>(
      context: context,
      builder: (_) => YamlFileNameDialog(
        title: '重命名',
        confirmText: '确认',
        description: '所在目录：${file.directory}',
        initialValue: file.name,
        fieldKey: const ValueKey('yaml_rename_file_name'),
        showFieldTitle: false,
      ),
    );
    if (!mounted || fileName == null || fileName == file.name) return;

    setState(() {
      _busyFilePath = file.path;
      _clearOperationFeedback();
    });
    try {
      final renamed = await ClashConfigFileService.renameFile(
        file.path,
        fileName,
        updateActiveReference: _activeConfigPath == file.path,
      );
      if (!mounted) return;
      setState(() {
        _files = [
          for (final existing in _files)
            if (existing.path == file.path) renamed else existing,
        ]..sort((a, b) => a.path.compareTo(b.path));
        if (_activeConfigPath == file.path) {
          _activeConfigPath = renamed.path;
        }
        _message = '已重命名为 ${renamed.name}';
      });
      _scheduleOperationFeedback(isError: false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _formatError('重命名', e));
      _scheduleOperationFeedback(isError: true);
    } finally {
      if (mounted) setState(() => _busyFilePath = null);
    }
  }

  Future<void> _exportConfig(ClashConfigFile file) async {
    _closeOpenSwipe();
    setState(() {
      _busyFilePath = file.path;
      _clearOperationFeedback();
    });
    try {
      final bytes = await ClashConfigFileService.readFileBytes(file.path);
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: tr('导出配置'),
        fileName: file.name,
        type: FileType.custom,
        allowedExtensions: const ['yaml', 'yml'],
        bytes: bytes,
      );
      if (!mounted || outputPath == null) return;
      setState(() => _message = '已导出 ${file.name}');
      _scheduleOperationFeedback(isError: false);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = _formatError('导出', e.message ?? e.code),
      );
      _scheduleOperationFeedback(isError: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _formatError('导出', e));
      _scheduleOperationFeedback(isError: true);
    } finally {
      if (mounted) setState(() => _busyFilePath = null);
    }
  }

  bool _consumeOpenSwipe() {
    if (_openSwipePath == null) return false;
    setState(() => _openSwipePath = null);
    return true;
  }

  void _closeOpenSwipe() {
    if (_openSwipePath != null) setState(() => _openSwipePath = null);
  }

  void _openSwipe(ClashConfigFile file) {
    if (_openSwipePath != file.path) {
      setState(() => _openSwipePath = file.path);
    }
  }

  void _handleBack() {
    if (_consumeOpenSwipe()) return;
    Navigator.of(context).pop();
  }

  String _formatError(String action, Object error) {
    _errorNeedsSettings = error is SshPasswordRequiredException;
    if (error is SshPasswordRequiredException) {
      return '请先在设置页填写 SSH 密码';
    }
    return '$action失败：$error';
  }

  void _showSnack(String message, {required bool success}) {
    if (!mounted) return;
    AppFeedback.showSnackBar(
      context,
      tr(message),
      tone: success ? AppFeedbackTone.success : AppFeedbackTone.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final palette = AppPalette.of(context);
    final bgColor = palette.pageBackground;
    final cardBg = palette.surface;
    final cardBorder = palette.border;
    final textColor = palette.textPrimary;
    final hintColor = palette.textSecondary;

    return PopScope(
      canPop: _openSwipePath == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _closeOpenSwipe();
      },
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: textColor),
            onPressed: _handleBack,
          ),
          title: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _closeOpenSwipe,
            child: AdaptiveSingleLineText(
              tr('Clash 配置文件'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: tr('上传配置'),
              icon: _uploading || _restarting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.file_download_outlined,
                      color: textColor,
                      size: 22,
                    ),
              onPressed: _uploading || _restarting ? null : _uploadConfig,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(0.5),
            child: Container(height: 0.5, color: cardBorder),
          ),
        ),
        body: NotificationListener<ScrollStartNotification>(
          onNotification: (notification) {
            if (notification.metrics.axis == Axis.vertical) {
              _closeOpenSwipe();
            }
            return false;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _closeOpenSwipe,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    _InfoBanner(
                      message: _error!,
                      color: palette.error,
                      actionLabel: _errorNeedsSettings ? '去设置' : null,
                      onAction: _errorNeedsSettings
                          ? () {
                              if (!_consumeOpenSwipe()) {
                                Navigator.of(context).pop();
                              }
                            }
                          : null,
                    ),
                  if (_message != null)
                    _InfoBanner(
                      message: _message!,
                      color: palette.success,
                    ),
                  _FileListCard(
                    files: _files,
                    loading: _loadingFiles,
                    activeConfigPath: _activeConfigPath,
                    openSwipePath: _openSwipePath,
                    busyFilePath: _busyFilePath,
                    cardBg: cardBg,
                    cardBorder: cardBorder,
                    textColor: textColor,
                    hintColor: hintColor,
                    onRefresh: () {
                      if (!_consumeOpenSwipe()) _refreshFiles();
                    },
                    onOpen: _openFile,
                    onRename: _renameConfig,
                    onExport: _exportConfig,
                    onSwipeOpen: _openSwipe,
                    onSwipeClose: _closeOpenSwipe,
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

class YamlUploadFileNameDialog extends StatelessWidget {
  final String initialValue;

  const YamlUploadFileNameDialog({super.key, required this.initialValue});

  @override
  Widget build(BuildContext context) {
    return YamlFileNameDialog(
      title: '上传新配置',
      confirmText: '上传',
      description: '上传目录：${ClashConfigFileService.defaultUploadDirectory}',
      initialValue: initialValue,
      fieldKey: const ValueKey('yaml_upload_file_name'),
      contentKey: const ValueKey('yaml_upload_dialog_content'),
    );
  }
}

class YamlFileNameDialog extends StatefulWidget {
  final String title;
  final String confirmText;
  final String description;
  final String initialValue;
  final Key fieldKey;
  final Key? contentKey;
  final bool showFieldTitle;

  const YamlFileNameDialog({
    super.key,
    required this.title,
    required this.confirmText,
    required this.description,
    required this.initialValue,
    required this.fieldKey,
    this.contentKey,
    this.showFieldTitle = true,
  });

  @override
  State<YamlFileNameDialog> createState() => _YamlFileNameDialogState();
}

class _YamlFileNameDialogState extends State<YamlFileNameDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final candidate = _controller.text.trim();
    final validationError = _uploadFileNameError(candidate);
    if (validationError != null) {
      setState(() => _errorText = validationError);
      return;
    }
    Navigator.of(context).pop(candidate);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SafeArea(
        minimum: const EdgeInsets.all(20),
        child: ConstrainedBox(
          key: widget.contentKey,
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(widget.title),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 18),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.showFieldTitle) ...[
                      Text(
                        tr('文件名'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                    ],
                    Text(
                      tr(widget.description),
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: widget.fieldKey,
                      controller: _controller,
                      autofocus: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      onChanged: (_) {
                        if (_errorText != null) {
                          setState(() => _errorText = null);
                        }
                      },
                      decoration: InputDecoration(
                        hintText: tr('请输入文件名'),
                        errorText: _errorText == null ? null : tr(_errorText!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: AdaptiveSingleLineText(tr('取消')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _submit,
                        child: AdaptiveSingleLineText(tr(widget.confirmText)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String? _uploadFileNameError(String value) {
  if (value.isEmpty) return '文件名不能为空';
  if (value == '.' || value == '..') return '文件名不能是 . 或 ..';
  if (value.contains('/') ||
      value.contains('\\') ||
      RegExp(r'[\x00-\x1F\x7F]').hasMatch(value)) {
    return '文件名不能包含路径分隔符或控制字符';
  }
  if (!ClashConfigFileService.isYamlPath(value)) {
    return '文件名需以 .yaml 或 .yml 结尾';
  }
  return null;
}

class ClashConfigEditorPage extends StatefulWidget {
  final ClashConfigFile file;
  final Future<String> Function(String path)? readFile;
  final Future<void> Function(String path, String content)? writeFile;

  const ClashConfigEditorPage({
    super.key,
    required this.file,
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

  bool _loading = true;
  bool _fileLoaded = false;
  bool _saving = false;
  bool _dirty = false;
  bool _savedDuringSession = false;
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
          editable: _fileLoaded && !_loading && !_saving,
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
    setState(() {
      _loading = true;
      _clearEditorFeedback();
    });
    try {
      final content =
          await (widget.readFile ?? ClashConfigFileService.readFile)(
        widget.file.path,
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
        widget.file.path,
        _editorController.text,
      );
      if (!mounted) return true;
      setState(() {
        _savedText = _editorController.text;
        _dirty = false;
        _savedDuringSession = true;
        _message = '已保存 ${widget.file.name}';
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

  Future<void> _handleExit() async {
    if (_saving) return;
    if (!_dirty) {
      if (mounted) Navigator.of(context).pop(_savedDuringSession);
      return;
    }

    final choice = await showDialog<_ExitChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('保存修改？')),
        content: Text(tr('当前 YAML 配置有未保存修改，退出前要保存吗？')),
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

    if (!mounted || choice == null || choice == _ExitChoice.cancel) return;
    if (choice == _ExitChoice.discard) {
      Navigator.of(context).pop(_savedDuringSession);
      return;
    }

    final saved = await _saveFile();
    if (mounted && saved) Navigator.of(context).pop(true);
  }

  String _formatError(String action, Object error) {
    if (error is SshPasswordRequiredException) {
      return '请先在设置页填写 SSH 密码';
    }
    return '$action失败：$error';
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final systemBottomInset = MediaQuery.paddingOf(context).bottom;
    final editorBottomInset =
        keyboardInset > 0 ? keyboardInset : systemBottomInset;

    return PopScope(
      // iOS edge-back is available for clean documents. Dirty documents keep
      // the explicit back action so the save/discard prompt cannot be bypassed.
      canPop: AppPlatform.isIOS && !_dirty && !_saving,
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
          title: AdaptiveSingleLineText(
            widget.file.name,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _YamlEditorSurface._text,
            ),
          ),
          centerTitle: true,
          actions: [
            YamlEditorSaveButton(
              dirty: _dirty,
              loading: _loading,
              saving: _saving,
              enabled: _fileLoaded,
              onSave: _saveFile,
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
                    enabled: _fileLoaded && !_saving,
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

class _FileListCard extends StatelessWidget {
  final List<ClashConfigFile> files;
  final bool loading;
  final String? activeConfigPath;
  final String? openSwipePath;
  final String? busyFilePath;
  final Color cardBg;
  final Color cardBorder;
  final Color textColor;
  final Color hintColor;
  final VoidCallback onRefresh;
  final ValueChanged<ClashConfigFile> onOpen;
  final ValueChanged<ClashConfigFile> onRename;
  final ValueChanged<ClashConfigFile> onExport;
  final ValueChanged<ClashConfigFile> onSwipeOpen;
  final VoidCallback onSwipeClose;

  const _FileListCard({
    required this.files,
    required this.loading,
    required this.activeConfigPath,
    required this.openSwipePath,
    required this.busyFilePath,
    required this.cardBg,
    required this.cardBorder,
    required this.textColor,
    required this.hintColor,
    required this.onRefresh,
    required this.onOpen,
    required this.onRename,
    required this.onExport,
    required this.onSwipeOpen,
    required this.onSwipeClose,
  });

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr('已发现 ${files.length} 个 YAML 文件'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tr('刷新列表'),
                  icon: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.refresh_rounded, color: textColor),
                  onPressed: loading ? null : onRefresh,
                ),
              ],
            ),
          ),
          if (files.isEmpty && !loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Text(
                tr('只扫描 Clash/OpenClash 目录下的 config 文件夹。'),
                style: TextStyle(fontSize: 12, color: hintColor),
              ),
            ),
          if (files.isNotEmpty) ...[
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: files.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 0, color: cardBorder),
              itemBuilder: (context, index) {
                final file = files[index];
                return SwipeConfigFileTile(
                  key: ValueKey('config_file_${file.path}'),
                  file: file,
                  active: activeConfigPath == file.path,
                  open: openSwipePath == file.path,
                  busy: busyFilePath == file.path,
                  backgroundColor: cardBg,
                  textColor: textColor,
                  hintColor: hintColor,
                  onOpen: () => onOpen(file),
                  onRename: () => onRename(file),
                  onExport: () => onExport(file),
                  onSwipeStart: onSwipeClose,
                  onSwipeOpen: () => onSwipeOpen(file),
                  onSwipeClose: onSwipeClose,
                );
              },
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

class SwipeConfigFileTile extends StatefulWidget {
  static const actionWidth = 144.0;

  final ClashConfigFile file;
  final bool active;
  final bool open;
  final bool busy;
  final Color backgroundColor;
  final Color textColor;
  final Color hintColor;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onExport;
  final VoidCallback onSwipeStart;
  final VoidCallback onSwipeOpen;
  final VoidCallback onSwipeClose;

  const SwipeConfigFileTile({
    super.key,
    required this.file,
    required this.active,
    required this.open,
    required this.busy,
    required this.backgroundColor,
    required this.textColor,
    required this.hintColor,
    required this.onOpen,
    required this.onRename,
    required this.onExport,
    required this.onSwipeStart,
    required this.onSwipeOpen,
    required this.onSwipeClose,
  });

  @override
  State<SwipeConfigFileTile> createState() => _SwipeConfigFileTileState();
}

class _SwipeConfigFileTileState extends State<SwipeConfigFileTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Animation<double>? _animation;
  double _offset = 0;
  double _dragStartOffset = 0;

  @override
  void initState() {
    super.initState();
    _offset = widget.open ? -SwipeConfigFileTile.actionWidth : 0;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
        final animation = _animation;
        if (animation != null && mounted) {
          setState(() => _offset = animation.value);
        }
      });
  }

  @override
  void didUpdateWidget(covariant SwipeConfigFileTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != oldWidget.open) {
      _animateTo(widget.open ? -SwipeConfigFileTile.actionWidth : 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    _controller.stop();
    _animation = Tween<double>(begin: _offset, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward(from: 0);
  }

  void _handleDragStart(DragStartDetails details) {
    if (widget.busy) return;
    _controller.stop();
    _dragStartOffset = _offset;
    if (!widget.open) widget.onSwipeStart();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (widget.busy) return;
    setState(() {
      _offset = (_offset + details.delta.dx)
          .clamp(-SwipeConfigFileTile.actionWidth, 0)
          .toDouble();
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (widget.busy) return;
    final velocity = details.primaryVelocity ?? 0;
    final startedOpen =
        _dragStartOffset.abs() > SwipeConfigFileTile.actionWidth / 2;
    final distanceThreshold =
        SwipeConfigFileTile.actionWidth * (startedOpen ? 0.65 : 0.35);
    final shouldOpen = velocity < -450 ||
        (velocity <= 450 && _offset.abs() > distanceThreshold);
    if (shouldOpen) {
      widget.onSwipeOpen();
      _animateTo(-SwipeConfigFileTile.actionWidth);
    } else {
      widget.onSwipeClose();
      _animateTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      key: ValueKey('swipe_file_${widget.file.path}'),
      height: 58,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              ignoring: !widget.open,
              child: ExcludeSemantics(
                excluding: !widget.open,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: SwipeConfigFileTile.actionWidth,
                    child: Row(
                      children: [
                        Expanded(
                          child: _SwipeAction(
                            key: ValueKey('rename_${widget.file.path}'),
                            color: const Color(0xFF626A78),
                            icon: Icons.drive_file_rename_outline_rounded,
                            label: tr('重命名'),
                            enabled: !widget.busy,
                            onPressed: widget.onRename,
                          ),
                        ),
                        Expanded(
                          child: _SwipeAction(
                            key: ValueKey('export_${widget.file.path}'),
                            color: primary,
                            icon: Icons.arrow_upward_rounded,
                            label: tr('导出'),
                            enabled: !widget.busy,
                            onPressed: widget.onExport,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Transform.translate(
              key: ValueKey('swipe_offset_${widget.file.path}'),
              offset: Offset(_offset, 0),
              child: Material(
                color: widget.backgroundColor,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onOpen,
                  onHorizontalDragStart: _handleDragStart,
                  onHorizontalDragUpdate: _handleDragUpdate,
                  onHorizontalDragEnd: _handleDragEnd,
                  onHorizontalDragCancel: () => _animateTo(
                      widget.open ? -SwipeConfigFileTile.actionWidth : 0),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        if (widget.active)
                          SvgPicture.asset(
                            'assets/icons/file-check.svg',
                            key: ValueKey('active_${widget.file.path}'),
                            width: 22,
                            height: 22,
                            semanticsLabel: tr('正在使用'),
                            colorFilter: ColorFilter.mode(
                              primary,
                              BlendMode.srcIn,
                            ),
                          )
                        else
                          Icon(
                            Icons.description_outlined,
                            color: widget.hintColor,
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.file.name,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 13,
                              color: widget.textColor,
                            ),
                          ),
                        ),
                        if (widget.busy)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: widget.hintColor,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeAction extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  const _SwipeAction({
    super.key,
    required this.color,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(height: 2),
            AdaptiveSingleLineText(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white),
            ),
          ],
        ),
      ),
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
