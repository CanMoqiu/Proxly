import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_svg/flutter_svg.dart';

import '../l10n/app_locale.dart';
import '../services/clash_host_validator.dart';
import '../services/connection_feedback.dart';
import '../services/connection_settings_store.dart';
import '../services/router_detection_service.dart';
import '../services/router_tool.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_popup.dart';
import '../widgets/controller_form_fields.dart';

class DeviceManagementSheet extends StatefulWidget {
  const DeviceManagementSheet({super.key});

  @override
  State<DeviceManagementSheet> createState() => _DeviceManagementSheetState();
}

class _DeviceManagementSheetState extends State<DeviceManagementSheet> {
  final _store = ConnectionSettingsStore.instance;
  late Future<List<DeviceProfile>> _devices = _store.loadDevices();
  String? _revealedDevice;
  bool _busy = false;

  void _reload() {
    final devices = _store.loadDevices();
    setState(() {
      _devices = devices;
    });
  }

  void _reveal(String? id) => setState(() => _revealedDevice = id);

  Future<void> _add() async {
    setState(() {
      _busy = true;
      _revealedDevice = null;
    });
    try {
      final saved = await Navigator.of(
        context,
      ).push<bool>(
        MaterialPageRoute(builder: (_) => const DeviceEditorPage()),
      );
      if (mounted && saved == true) _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(DeviceProfile device) async {
    _reveal(null);
    final confirmed = await AppPopup.dialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: Text(tr('删除设备')),
        content: Text(device.name),
        actions: [
          TextButton(
            onPressed: () => AppPopup.close(context),
            child: Text(tr('取消')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => AppPopup.close(context, true),
            child: Text(tr('删除')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _store.deleteDevice(device.id);
      if (mounted) _reload();
    } catch (_) {
      _showError('无法删除设备，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    AppFeedback.showSnackBar(context, tr(message), tone: AppFeedbackTone.error);
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tr('选择控制器'),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _add,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(tr('新增设备')),
              ),
            ],
          ),
        ),
        Flexible(
          child: FutureBuilder<List<DeviceProfile>>(
            future: _devices,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  heightFactor: 1,
                  child: TextButton(
                    onPressed: _reload,
                    child: Text(tr('重试')),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(
                  heightFactor: 2,
                  child: CircularProgressIndicator(),
                );
              }
              return ListenableBuilder(
                listenable: _store.profilesChanged,
                builder: (context, _) => ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    if (!_store.canSwitchDevice && !_busy)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: Text(tr('远端操作完成后可切换设备。')),
                      ),
                    for (final device in snapshot.data!) _deviceRow(device),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _deviceRow(DeviceProfile device) {
    final active = _store.activeDevice?.id == device.id;
    return _DeviceRow(
      key: ValueKey('device-row-${device.id}'),
      device: device,
      active: active,
      revealed: _revealedDevice == device.id,
      onReveal: (open) => _reveal(open ? device.id : null),
      onSelect: !_busy && (active || _store.canSwitchDevice)
          ? () => AppPopup.close(context, device)
          : null,
      onDelete: active || _busy ? null : () => _delete(device),
    );
  }
}

class _DeviceRow extends StatefulWidget {
  const _DeviceRow({
    super.key,
    required this.device,
    required this.active,
    required this.revealed,
    required this.onReveal,
    required this.onSelect,
    required this.onDelete,
  });

  final DeviceProfile device;
  final bool active;
  final bool revealed;
  final ValueChanged<bool> onReveal;
  final VoidCallback? onSelect;
  final VoidCallback? onDelete;

  @override
  State<_DeviceRow> createState() => _DeviceRowState();
}

class _DeviceRowState extends State<_DeviceRow> {
  double? _dragOffset;

  void _finishDrag(double width, double velocity) {
    final open =
        velocity < -320 || (velocity < 320 && (_dragOffset ?? 0) >= width / 2);
    setState(() => _dragOffset = null);
    widget.onReveal(open);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final revealed = widget.revealed;
    final onDelete = widget.onDelete;
    final tile = AppSheetOptionTile(
      label: widget.device.name,
      subtitle: widget.device.host,
      selected: widget.active,
      leading: SvgPicture.asset(
        'assets/icons/router.svg',
        width: 24,
        height: 24,
        excludeFromSemantics: true,
        colorFilter: ColorFilter.mode(
          widget.active
              ? theme.colorScheme.primary
              : AppPalette.of(context).textSecondary,
          BlendMode.srcIn,
        ),
      ),
      onTap: widget.onSelect,
    );
    if (onDelete == null) return tile;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = 88.0.clamp(0.0, constraints.maxWidth * .4).toDouble();
        final offset = _dragOffset ?? (revealed ? width : 0.0);
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: width,
              child: ExcludeSemantics(
                excluding: !revealed,
                child: IgnorePointer(
                  ignoring: !revealed,
                  child: Material(
                    color: theme.colorScheme.errorContainer,
                    child: InkWell(
                      onTap: onDelete,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_outline_rounded,
                              color: theme.colorScheme.onErrorContainer),
                          Text(
                            tr('删除'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSlide(
              offset: Offset(-offset / constraints.maxWidth, 0),
              duration: _dragOffset == null
                  ? const Duration(milliseconds: 180)
                  : Duration.zero,
              curve: Curves.easeOutCubic,
              child: Semantics(
                customSemanticsActions: {
                  CustomSemanticsAction(label: tr('删除设备')): onDelete,
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) =>
                      setState(() => _dragOffset = offset),
                  onHorizontalDragUpdate: (details) => setState(
                    () => _dragOffset =
                        ((_dragOffset ?? offset) - details.delta.dx)
                            .clamp(0.0, width)
                            .toDouble(),
                  ),
                  onHorizontalDragEnd: (details) =>
                      _finishDrag(width, details.primaryVelocity ?? 0),
                  onHorizontalDragCancel: () =>
                      setState(() => _dragOffset = null),
                  child:
                      Material(color: theme.colorScheme.surface, child: tile),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class DeviceEditorPage extends StatefulWidget {
  const DeviceEditorPage({
    super.key,
    this.device,
    this.detectionService,
    this.store,
  });

  final DeviceProfile? device;
  final RouterDetectionService? detectionService;
  final ConnectionSettingsStore? store;

  @override
  State<DeviceEditorPage> createState() => _DeviceEditorPageState();
}

class _DeviceEditorPageState extends State<DeviceEditorPage> {
  late final _store = widget.store ?? ConnectionSettingsStore.instance;
  late final _name = TextEditingController(text: widget.device?.name);
  late final _initialEndpoint =
      ClashHostValidator.parseEndpoint(widget.device?.host ?? '');
  late final _host = TextEditingController(text: _initialEndpoint?.hostname);
  late final _controllerPort =
      TextEditingController(text: _initialEndpoint?.portText);
  final _token = TextEditingController();
  late final _port = TextEditingController(
    text: (widget.device?.sshPort ?? 22).toString(),
  );
  final _password = TextEditingController();
  RouterTool? _backendChoice;
  bool _loadingCredentials = false;
  bool _credentialsUnavailable = false;
  bool _testing = false;
  bool _saving = false;
  String? _result;
  bool _success = false;
  int _inputRevision = 0;

  bool get _ready =>
      !_loadingCredentials && !_credentialsUnavailable && !_saving;

  @override
  void initState() {
    super.initState();
    if (widget.device != null) _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    setState(() => _loadingCredentials = true);
    try {
      final settings = await _store.loadDevice(widget.device!.id);
      if (!mounted) return;
      _token.text = settings.token;
      _password.text = settings.sshPassword;
      _credentialsUnavailable = false;
    } catch (_) {
      if (mounted) _credentialsUnavailable = true;
    } finally {
      if (mounted) setState(() => _loadingCredentials = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _host,
      _controllerPort,
      _token,
      _port,
      _password
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _edited(String _) {
    _inputRevision++;
    if (_result != null) setState(() => _result = null);
  }

  String? _validatedHost() {
    final endpoint =
        ClashHostValidator.fromFields(_host.text, _controllerPort.text);
    if (endpoint.error == null) return endpoint.address;
    _setResult(endpoint.error!);
    return null;
  }

  void _setResult(String text, {bool success = false}) {
    setState(() {
      _result = text;
      _success = success;
    });
  }

  Future<void> _test() async {
    final host = _validatedHost();
    if (host == null) return;
    setState(() {
      _testing = true;
      _result = null;
    });
    final revision = _inputRevision;
    try {
      await (widget.detectionService ?? RouterDetectionService()).detect(
        host: host,
        token: _token.text.trim(),
        sshPassword: '',
        sshPort: 22,
      );
      if (mounted && revision == _inputRevision) {
        _setResult(tr('连接正常'), success: true);
      }
    } catch (error) {
      if (mounted && revision == _inputRevision) {
        _setResult(
          tr(switch (error) {
            StateError(message: 'unauthorized') => '请检查控制器密钥。',
            FormatException() => '控制器响应无效，请检查端口。',
            _ => ConnectionFeedback.unavailable,
          }),
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final host = _validatedHost();
    if (host == null) return;
    final name = _name.text.trim();
    final port = ConnectionSettings.parseSshPort(_port.text);
    if (port == null) {
      _setResult(tr('SSH 端口必须为 1–65535 之间的整数'));
      return;
    }
    setState(() => _saving = true);
    try {
      await _store.saveDevice(
        id: widget.device?.id,
        name: name.isEmpty ? host : name,
        host: host,
        token: _token.text.trim(),
        sshPassword: _password.text,
        sshPort: port,
        routerTool: _backendChoice,
      );
      if (mounted) Navigator.pop(context, true);
    } on ArgumentError {
      if (mounted) _setResult(tr('设备名称已使用'));
    } catch (_) {
      if (mounted) _setResult(tr('无法保存设备，请重试。'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseBackend() async {
    final choice = await showControllerBackendPicker(
        context, _backendChoice ?? widget.device?.routerTool);
    if (mounted && choice != null) setState(() => _backendChoice = choice);
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final colors = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.pageBackground,
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          tr(widget.device == null ? '新增设备' : '编辑设备'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: palette.pageBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(.5),
          child: Divider(height: .5, thickness: .5, color: palette.border),
        ),
      ),
      body: AdaptiveContent(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: AdaptiveScrollPadding.page(context),
          children: [
            Material(
              color: palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: palette.border, width: .5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_loadingCredentials) const LinearProgressIndicator(),
                    if (_credentialsUnavailable) ...[
                      Text(tr('凭据暂时不可用，请解锁设备后重试。已保存的配置未被删除。')),
                      TextButton(
                        onPressed: _loadCredentials,
                        child: Text(tr('重试')),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _credentialsUnavailable = false),
                        child: Text(tr('重新填写凭据')),
                      ),
                    ],
                    ControllerFormFields(
                      name: _name,
                      address: _host,
                      port: _controllerPort,
                      secret: _token,
                      sshPort: _port,
                      sshSecret: _password,
                      backend: _backendChoice ?? widget.device?.routerTool,
                      onChooseBackend: _chooseBackend,
                      enabled: _ready,
                      onChanged: _edited,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _ready && !_testing ? _test : null,
                      child: Text(tr(_testing ? '检查中…' : '测试连接')),
                    ),
                    if (_result case final text?)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            text,
                            style: TextStyle(
                              color: _success ? colors.primary : colors.error,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _ready && !_testing ? _save : null,
                      child: Text(tr(_saving ? '正在保存设置...' : '保存')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
