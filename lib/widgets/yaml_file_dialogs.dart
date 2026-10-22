import 'app_popup.dart';
import 'package:flutter/material.dart';
import '../l10n/app_locale.dart';
import '../services/clash_config_file_service.dart';

class YamlRestartAfterSaveDialog extends StatelessWidget {
  const YamlRestartAfterSaveDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: Text(tr('确认重启 OpenClash')),
      content: Text(tr('配置已保存，是否立即重启 OpenClash 使修改生效？')),
      actions: [
        TextButton(
          onPressed: () => AppPopup.close(context, false),
          child: Text(tr('稍后')),
        ),
        FilledButton(
          onPressed: () => AppPopup.close(context, true),
          child: Text(tr('立即重启')),
        ),
      ],
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
    AppPopup.close(context, candidate);
  }

  @override
  Widget build(BuildContext context) => AppDialog(
        title: Text(tr(widget.title)),
        content: SizedBox(
            key: widget.contentKey,
            width: 320,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(widget.description),
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  TextField(
                    key: widget.fieldKey,
                    controller: _controller,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    onChanged: (_) {
                      if (_errorText != null) setState(() => _errorText = null);
                    },
                    decoration: InputDecoration(
                      labelText: widget.showFieldTitle ? tr('文件名') : null,
                      hintText: tr('请输入文件名'),
                      errorText: _errorText == null ? null : tr(_errorText!),
                    ),
                  ),
                ])),
        actions: [
          TextButton(
              onPressed: () => AppPopup.close(context), child: Text(tr('取消'))),
          FilledButton(onPressed: _submit, child: Text(tr(widget.confirmText))),
        ],
      );
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
