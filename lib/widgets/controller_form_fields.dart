import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../services/router_tool.dart';
import '../theme/app_theme.dart';
import 'adaptive_ui.dart';
import 'app_popup.dart';

Future<RouterTool?> showControllerBackendPicker(
  BuildContext context,
  RouterTool? selected,
) {
  FocusScope.of(context).unfocus();
  return AppPopup.sheet<RouterTool>(
    context: context,
    builder: (_) => AppOptionsSheet<RouterTool>(
      title: tr('代理后端'),
      selectedValue: selected,
      options: [
        for (final tool in RouterTool.values)
          AppSheetOption(
            value: tool,
            label: tr(
                tool == RouterTool.generic ? 'Mihomo / Clash通用配置' : tool.label),
          ),
      ],
    ),
  );
}

class ControllerFormFields extends StatefulWidget {
  const ControllerFormFields({
    super.key,
    required this.name,
    required this.address,
    required this.port,
    required this.secret,
    required this.sshPort,
    required this.sshSecret,
    required this.backend,
    required this.onChooseBackend,
    this.addressFocus,
    this.enabled = true,
    this.addressError = false,
    this.editedFields = const {},
    this.backendEdited = false,
    this.onChanged,
  });

  final TextEditingController name, address, port, secret, sshPort, sshSecret;
  final RouterTool? backend;
  final VoidCallback? onChooseBackend;
  final FocusNode? addressFocus;
  final bool enabled, addressError;
  final Set<TextEditingController> editedFields;
  final bool backendEdited;
  final ValueChanged<String>? onChanged;

  @override
  State<ControllerFormFields> createState() => _ControllerFormFieldsState();
}

class _ControllerFormFieldsState extends State<ControllerFormFields> {
  bool _showSecret = false;
  bool _showSshSecret = false;

  @override
  Widget build(BuildContext context) {
    final backend = widget.backend;
    return Column(
      children: [
        _field('名称', widget.name, '可选', 'controller_name_field'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: AppSettingPickerRow(
            title: tr('代理后端'),
            picker: AppSelectionPicker(
              key: const ValueKey('controller_backend_picker'),
              label: tr(switch (backend) {
                null => '自动识别',
                RouterTool.generic => '通用配置',
                _ => backend.label,
              }),
              icon: Icons.dns_outlined,
              tooltip: tr('代理后端'),
              compact: true,
              borderColor:
                  widget.backendEdited ? AppPalette.of(context).warning : null,
              onTap: widget.enabled ? widget.onChooseBackend : null,
            ),
          ),
        ),
        Column(
          spacing: 12,
          children: [
            _field(
              '控制器地址',
              widget.address,
              '192.168.1.1',
              'controller_address_field',
              focusNode: widget.addressFocus,
              keyboardType: TextInputType.url,
              error: widget.addressError,
            ),
            _field(
              '控制器端口',
              widget.port,
              '9090',
              'controller_port_field',
              keyboardType: TextInputType.number,
            ),
            _field(
              '控制器密钥',
              widget.secret,
              '可选',
              'controller_secret_field',
              obscure: !_showSecret,
              onToggle: () => setState(() => _showSecret = !_showSecret),
            ),
            _field(
              'SSH 端口',
              widget.sshPort,
              '22',
              'ssh_port_field',
              keyboardType: TextInputType.number,
            ),
            _field(
              'SSH 密钥',
              widget.sshSecret,
              '可选',
              'ssh_secret_field',
              obscure: !_showSshSecret,
              onToggle: () => setState(() => _showSshSecret = !_showSshSecret),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController controller,
    String hint,
    String fieldKey, {
    TextInputType? keyboardType,
    FocusNode? focusNode,
    bool error = false,
    bool obscure = false,
    VoidCallback? onToggle,
  }) {
    final palette = AppPalette.of(context);
    final labelColor = error ? palette.error : palette.textPrimary;
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final decoration = theme.inputDecorationTheme;
    final border = decoration.border ?? const OutlineInputBorder();

    InputBorder? editedBorder(InputBorder? themedBorder) {
      if (!widget.editedFields.contains(controller)) return null;
      final shape = themedBorder ?? border;
      return shape.copyWith(
        borderSide: shape.borderSide.copyWith(color: palette.warning),
      );
    }

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (focused) {
          controller.selection =
              TextSelection.collapsed(offset: controller.text.length);
        }
      },
      child: TextField(
        key: ValueKey(fieldKey),
        controller: controller,
        focusNode: focusNode,
        enabled: widget.enabled,
        keyboardType: keyboardType,
        textInputAction: fieldKey == 'ssh_secret_field'
            ? TextInputAction.done
            : TextInputAction.next,
        textAlign: TextAlign.start,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: widget.onChanged,
        style: TextStyle(fontSize: 14, color: palette.textPrimary),
        decoration: InputDecoration(
          labelText: tr(label),
          labelStyle: TextStyle(fontSize: 14, color: labelColor),
          floatingLabelStyle: WidgetStateTextStyle.resolveWith(
            (states) => TextStyle(
              fontSize: 14,
              color: error
                  ? palette.error
                  : states.contains(WidgetState.focused)
                      ? primary
                      : palette.textSecondary,
            ),
          ),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
          maintainHintSize: false,
          hintFadeDuration: Duration.zero,
          hint: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 240),
            // Let the Material label finish moving before revealing the hint.
            curve: const Interval(.7, 1, curve: Curves.easeOut),
            builder: (context, opacity, child) =>
                Opacity(opacity: opacity, child: child),
            child: Text(
              tr(hint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: 14,
                color: Color.alphaBlend(
                  palette.textSecondary.withValues(alpha: .84),
                  palette.surface,
                ),
              ),
            ),
          ),
          isDense: true,
          filled: true,
          border: border,
          enabledBorder: editedBorder(decoration.enabledBorder),
          focusedBorder: editedBorder(decoration.focusedBorder),
          disabledBorder: editedBorder(decoration.disabledBorder),
          constraints: const BoxConstraints(minHeight: 52),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          suffixIconConstraints:
              const BoxConstraints.tightFor(width: 40, height: 36),
          suffixIcon: onToggle == null
              ? null
              : IconButton(
                  tooltip: tr(obscure ? '显示' : '隐藏'),
                  iconSize: 17,
                  padding: EdgeInsets.zero,
                  onPressed: widget.enabled ? onToggle : null,
                  icon: Icon(
                    obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: palette.textSecondary,
                  ),
                ),
        ),
      ),
    );
  }
}

class ControllerTestFeedback extends StatefulWidget {
  const ControllerTestFeedback({
    super.key,
    required this.message,
    required this.success,
  });

  final String message;
  final bool success;

  @override
  State<ControllerTestFeedback> createState() => _ControllerTestFeedbackState();
}

class _ControllerTestFeedbackState extends State<ControllerTestFeedback> {
  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(covariant ControllerTestFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message != oldWidget.message) _reveal();
  }

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = widget.success ? palette.success : palette.error;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        liveRegion: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                widget.success
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                size: 17,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(widget.message),
                  style: TextStyle(fontSize: 13, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
