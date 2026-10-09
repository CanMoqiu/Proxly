import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/adaptive_ui.dart';

enum AppLanguage { simplifiedChinese, english }

class AppLocaleController extends ChangeNotifier {
  AppLocaleController._();

  static final instance = AppLocaleController._();
  static const preferenceKey = 'app_language';

  AppLanguage _language = AppLanguage.english;

  AppLanguage get language => _language;

  Locale get locale => switch (_language) {
        AppLanguage.simplifiedChinese => const Locale('zh', 'CN'),
        AppLanguage.english => const Locale('en'),
      };

  Locale get effectiveLocale => locale;

  String get zashboardLanguage =>
      _language == AppLanguage.simplifiedChinese ? 'zh-CN' : 'en-US';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(preferenceKey);
    _language = switch (saved) {
      'zh_CN' || 'zh_HK' || 'zh_TW' => AppLanguage.simplifiedChinese,
      'en' => AppLanguage.english,
      _ => resolveSystemLanguage(
          WidgetsBinding.instance.platformDispatcher.locales),
    };
    if (saved != _storageValue(_language)) {
      await prefs.setString(preferenceKey, _storageValue(_language));
    }
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (_language == language) return;
    _language = language;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(preferenceKey, _storageValue(language));
  }

  static AppLanguage resolveSystemLanguage(List<Locale>? locales) {
    final locale = locales?.isNotEmpty == true ? locales!.first : null;
    return locale?.languageCode == 'zh'
        ? AppLanguage.simplifiedChinese
        : AppLanguage.english;
  }

  static String _storageValue(AppLanguage language) => switch (language) {
        AppLanguage.simplifiedChinese => 'zh_CN',
        AppLanguage.english => 'en',
      };
}

class AppLocaleScope extends InheritedNotifier<AppLocaleController> {
  const AppLocaleScope({
    super.key,
    required AppLocaleController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLocaleController watch(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppLocaleScope>()!
        .notifier!;
  }
}

String tr(String source) {
  final locale = AppLocaleController.instance.effectiveLocale;
  if (locale.languageCode == 'zh') return source;
  return _english[source] ?? _dynamicEnglish(source) ?? source;
}

class AppLanguagePicker extends StatelessWidget {
  final bool compact;

  const AppLanguagePicker({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.watch(context);
    final appLocale = AppLocaleController.instance;
    final current = appLocale.language;
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = colorScheme.onSurface;

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colorScheme.surface),
        elevation: const WidgetStatePropertyAll(8),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 4),
        ),
      ),
      menuChildren: AppLanguage.values
          .map(
            (language) => MenuItemButton(
              onPressed: () => appLocale.setLanguage(language),
              leadingIcon: language == current
                  ? Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    )
                  : const SizedBox(width: 18, height: 18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 96),
                child: AdaptiveSingleLineText(
                  _languageLabel(language),
                  alignment: Alignment.centerLeft,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 13,
                    letterSpacing: 0,
                    color: foreground,
                  ),
                ),
              ),
            ),
          )
          .toList(),
      builder: (context, menuController, child) {
        return Tooltip(
          message: tr('切换语言'),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (menuController.isOpen) {
                  menuController.close();
                } else {
                  menuController.open();
                }
              },
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 10 : 12,
                  vertical: compact ? 8 : 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: foreground.withValues(alpha: 0.18),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.language_rounded, size: 18, color: foreground),
                    const SizedBox(width: 8),
                    Flexible(
                      child: AdaptiveSingleLineText(
                        _languageLabel(current),
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 0,
                          color: foreground,
                        ),
                        alignment: Alignment.centerLeft,
                        textAlign: TextAlign.left,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 18,
                      color: foreground,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _languageLabel(AppLanguage language) => switch (language) {
      AppLanguage.simplifiedChinese => '简体中文',
      AppLanguage.english => 'English',
    };

const _english = <String, String>{
  '只能重命名配置目录中的普通 YAML 文件':
      'Only regular YAML files in configuration directories can be renamed',
  '无法确认当前运行配置，请刷新连接后重试重命名':
      'Could not identify the active configuration. Refresh the connection before retrying the rename',
  '不能重命名当前运行的订阅配置，请先切换到其他配置':
      'Switch to another configuration before renaming the active subscription file',
  '关闭连接失败，请检查网络和 Token 后重试':
      'Could not close the connection. Check the network and token, then retry',
  '应用结果未确认，请检查 OpenClash 状态后重试':
      'The result could not be confirmed. Check the OpenClash state before retrying',
  '删除配置': 'Delete configuration',
  '删除配置文件？': 'Delete configuration file?',
  '删除': 'Delete',
  '此操作无法撤销。': 'This cannot be undone.',
  '未保存的修改也会丢弃。': 'Unsaved changes will also be discarded.',
  '只能删除配置目录中的普通 YAML 文件':
      'Only regular YAML files in configuration directories can be deleted',
  '无法确认当前运行配置，请刷新连接后重试删除':
      'Could not identify the active configuration. Refresh the connection before retrying deletion',
  '不能删除当前运行配置，请先切换到其他配置':
      'Switch to another configuration before deleting the active file',
  '运行状态': 'Runtime status',
  '当前配置': 'Current configuration',
  '正在检查当前配置...': 'Checking the active configuration...',
  '运行操作': 'Runtime actions',
  '长按卡片拖动排序，关闭开关隐藏卡片':
      'Long-press a card to reorder; turn its switch off to hide it',
  '无法确认当前配置；若修改了运行配置，请稍后手动重启 OpenClash':
      'Could not identify the active configuration. Restart OpenClash manually if you changed it.',
  'Clash 状态': 'Clash status',
  '当前 YAML': 'Current YAML',
  'Clash 操作': 'Clash actions',
  '快捷设置': 'Quick settings',
  '自定义首页': 'Customize dashboard',
  '拖动手柄排序，关闭开关隐藏卡片': 'Drag to reorder; turn off a switch to hide a card',
  '拖动排序': 'Drag to reorder',
  '恢复默认': 'Reset layout',
  '卡片已隐藏，点击右上角自定义首页以恢复。':
      'Cards are hidden. Customize the dashboard to restore them.',
  '读取首页布局失败': 'Could not load the dashboard layout',
  '保存首页布局失败，请重试': 'Could not save the dashboard layout. Please try again.',
  '暂无订阅流量': 'No subscription traffic available',
  '编辑配置': 'Edit configuration',
  '文件管理': 'File actions',
  '文件操作': 'File operation',
  '完成': 'Done',
  '选择要编辑的文件，不改变当前运行配置。':
      'Choose a file to edit. The running configuration stays unchanged.',
  '当前 YAML 配置有未保存修改，继续前要保存吗？':
      'This YAML file has unsaved changes. Save before continuing?',
  '导出当前内容': 'Export current content',
  '选择 YAML 或上传新配置开始编辑':
      'Choose a YAML file or upload a configuration to start editing',
  '覆盖已有配置？': 'Overwrite existing configuration?',
  '覆盖': 'Overwrite',
  '版本': 'Version',
  '前往 GitHub 发布页下载 IPA，自签后手动安装。':
      'Download the IPA from GitHub Releases, then sign and install it manually.',
  '正式版': 'Release',
  '测试版': 'Test build',
  '版本信息读取失败，重试': 'Could not load version information. Retry',
  '无法打开链接，请检查浏览器设置': 'Could not open the link. Check your browser settings',
  '使用与支持': 'Help and support',
  'iOS 安装与更新': 'iOS installation and updates',
  '下载 IPA、自签安装和覆盖更新说明': 'Download, sign and update your IPA',
  '问题反馈': 'Report an issue',
  '请附版本信息、复现步骤和已脱敏的截图':
      'Include version information, steps and screenshots with secrets removed',
  '项目源码': 'Source code',
  'Proxly 的使用与分发许可': 'Terms for using and distributing Proxly',
  '开源致谢': 'Open-source acknowledgements',
  '第三方许可证': 'Third-party licenses',
  'Flutter、依赖库、JetBrains Mono 与旗帜字体':
      'Flutter, dependencies, JetBrains Mono and flag fonts',
  "通过自签安装新版": "Install new versions with your signing tool",
  "凭据暂时不可用，请解锁设备后重试。已保存的配置未被删除。":
      "Credentials are temporarily unavailable. Unlock the device and retry. Your saved settings have been preserved.",
  "启动失败，请重试。已保存的配置未被删除。":
      "Startup failed. Retry to continue. Your saved settings have been preserved.",
  "请检查控制器地址、网络连接，以及系统设置中的 Proxly 局域网权限。":
      "Check the controller address, network connection, and Proxly local network permission in Settings.",
  "面板加载超时，请重试": "The panel took too long to load. Please retry.",
  "面板启动失败，请重试": "Could not start the panel. Please retry.",
  "面板加载失败，请重试": "Could not load the panel. Please retry.",
  "面板初始化失败，请重试": "Could not initialize the panel. Please retry.",
  "面板进程已停止，请重试": "The panel process stopped. Please retry.",
  "新面板加载失败，请重试激活": "The new panel could not be loaded. Retry activation.",
  "正在加载新面板…": "Loading the new panel…",
  "面板更新完成": "Panel update complete",
  "Zashboard 是内置 Web 控制面板。新版可能影响页面适配，更新后将重新加载面板。":
      "Zashboard is the built-in web panel. A new version may affect the layout. The panel will reload after updating.",
  "Proxly 是一款专为 OpenClash / Mihomo 设计的监控面板，让你在手机上实时掌握代理状态、流量用量与连接详情，无需打开浏览器。":
      "Proxly is a monitoring dashboard for OpenClash / Mihomo that displays proxy status, traffic usage, and connection details on your phone.",
  'Clash 地址仅支持本机、局域网或本地域名':
      'Only localhost, private network addresses, or local domains are supported',
  'Clash 控制中心': 'Clash Control Center',
  'Clash 配置文件': 'Clash configuration files',
  'DNS 缓存已清理': 'DNS cache cleared',
  'DNS模式': 'DNS mode',
  'GitHub API 返回格式异常': 'GitHub API returned an unexpected response',
  'GitHub API 请求频率超限，请稍后再试':
      'GitHub API rate limit exceeded. Please try again later',
  'IP:端口': 'IP:port',
  'OpenClash 地址': 'OpenClash address',
  'OpenClash 重启成功': 'OpenClash restarted successfully',
  'OpenClash 重启命令已发送': 'OpenClash restart command sent',
  'Proxly 帮你在手机上管理 OpenClash / Mihomo，':
      'Proxly helps you manage OpenClash / Mihomo from your phone,',
  'Proxly 帮你在手机上管理 OpenClash / Mihomo，查看运行状态、流量、连接和 YAML 配置。':
      'Manage OpenClash / Mihomo from your phone and view status, traffic, connections, and YAML configurations.',
  'Proxly 是一款专为 OpenClash / Mihomo 设计的 Android 监控面板，':
      'Proxly is an Android monitoring dashboard designed for OpenClash / Mihomo,',
  'Proxly 是一款专为 OpenClash / Mihomo 设计的 Android 监控面板，让你在手机上实时掌握代理状态、流量用量与连接详情，无需打开浏览器。':
      'Proxly is an Android monitoring dashboard for OpenClash / Mihomo that lets you monitor proxy status, traffic usage, and connection details from your phone without opening a browser.',
  'Proxly 与 Clash / OpenClash / Mihomo 项目无官方关联':
      'Proxly is not officially affiliated with Clash, OpenClash, or Mihomo',
  'SSH 登录': 'SSH login',
  'SSH 密码': 'SSH password',
  'SSH 密码（可选）': 'SSH password (optional)',
  'Token 错误': 'Invalid token',
  'Zashboard 面板': 'Zashboard panel',
  'Zashboard 面板更新': 'Zashboard panel update',
  'Zashboard 是内置 Web 控制面板。新版可能调整页面结构，影响代理页和连接页的适配效果。更新完成后 Proxly 会自动重启以加载新面板。':
      'Zashboard is the built-in web control panel. New versions may change the page structure and affect the Proxy and Connections integrations. Proxly restarts automatically after the update.',
  '保存': 'Save',
  '保存设置': 'Save settings',
  '保存修改？': 'Save changes?',
  '本地': 'Local',
  '本软件按"原样"提供，不附带任何明示或暗示的担保。':
      'This software is provided "as is", without warranty of any kind, express or implied.',
  '本软件以 MIT 协议开源，允许任何人免费使用、复制、修改、合并、':
      'This software is licensed under the MIT License. Anyone may use, copy, modify, merge,',
  '编辑 YAML 配置': 'Edit YAML configuration',
  '打开文件选择器': 'Open file picker',
  '安装': 'Install',
  '不保存': "Don't save",
  '测试连接': 'Test connection',
  '查看活跃连接和完整代理链路': 'View active connections and full proxy chains',
  '查看速率曲线与上传、下载用量': 'View speed charts and upload/download usage',
  '查看运行状态、流量、连接和 YAML 配置。':
      'View status, traffic, connections, and YAML configurations.',
  '处理中': 'Processing',
  '传输协议': 'Transport protocol',
  '代理': 'Proxy',
  '代理控制': 'Proxy control',
  '代理链路': 'Proxy chain',
  '当前 YAML 配置有未保存修改，退出前要保存吗？':
      'The current YAML configuration has unsaved changes. Save before leaving?',
  '当前更像是订阅链接或远程配置模式':
      'The current setup appears to use a subscription URL or remote configuration',
  '当前使用配置': 'Active configuration',
  '当前仍显示为订阅模式，请检查 OpenClash 配置':
      'The active source is still shown as subscription mode. Check the OpenClash configuration',
  '当前 Clash 内核不支持清理 DNS 缓存':
      'The current Clash core does not support clearing the DNS cache',
  '当前 Clash 内核不支持关闭所有连接':
      'The current Clash core does not support closing all connections',
  '导入配置': 'Import settings',
  '等待 Clash 重新上线...': 'Waiting for Clash to come back online...',
  '等待超时，请手动检查 Clash 状态': 'Timed out. Please check the Clash status manually',
  '第三方依赖': 'Third-party dependencies',
  '调试与实验性功能': 'Debugging and experimental features',
  '读取 OpenClash 当前使用的配置来源':
      'Read the configuration source currently used by OpenClash',
  '读取、编辑并上传 OpenClash YAML': 'Read, edit, and upload OpenClash YAML files',
  '读取、编辑并上传 YAML 配置': 'Read, edit, and upload YAML configurations',
  '读取、上传并编辑 OpenClash YAML 配置':
      'Read, upload, and edit OpenClash YAML configurations',
  '读取当前配置失败：请先在设置页填写并保存 SSH 密码':
      'Unable to load the active configuration. Save the SSH password in Settings first',
  '读取本地文件失败': 'Failed to read the local file',
  '读取本地文件': 'Read local file',
  '读取当前配置': 'Load active configuration',
  '读取配置列表': 'Load configuration list',
  '读取文件': 'Read file',
  '读取文件失败': 'Failed to read file',
  '读取更新检测设置失败': 'Failed to load update check setting',
  '保存更新检测设置失败': 'Failed to save update check setting',
  '读取中…': 'Loading…',
  '发布、分发、再授权及销售本软件的副本，但须保留上述版权声明与本许可声明。\n\n':
      'publish, distribute, sublicense, and/or sell copies of the software, provided that the copyright and permission notices are retained.\n\n',
  '发布包缺少 SHA256 摘要，已拒绝更新':
      'The release package has no SHA256 digest. Update rejected',
  '发布包下载地址不可信，已拒绝更新': 'The release package URL is not trusted. Update rejected',
  '发布包中未找到 dist.zip': 'dist.zip was not found in the release package',
  '返回': 'Back',
  '格式错误：不是有效的配置文件': 'Invalid format: not a valid configuration file',
  '跟随系统': 'Follow system',
  '更新内置 Web 控制面板。新版可能需要重新适配代理页和连接页。':
      'Update the built-in web panel. New versions may require Proxy and Connections page adjustments.',
  '更新': 'Update',
  '解析失败：文件内容不是合法 JSON': 'Parsing failed: the file does not contain valid JSON',
  '解析': 'Parse',
  '更新日志': 'Release notes',
  '更新完成，正在重启 Proxly…': 'Update complete. Restarting Proxly…',
  '更新中': 'Updating',
  '更新检测已关闭，可在关于页重新开启':
      'Update checks disabled. You can re-enable them on the About page.',
  '功能介绍': 'Features',
  '功能介绍、版本日志、开源协议': 'Features, release notes, and open-source licenses',
  '关于': 'About',
  '关于 Proxly': 'About Proxly',
  '规则': 'Rule',
  '欢迎使用 Proxly': 'Welcome to Proxly',
  '活跃连接': 'Active',
  '即将在外部浏览器中打开，确定继续？': 'This link will open in an external browser. Continue?',
  '继续': 'Continue',
  '继续更新': 'Continue update',
  '检查并更新': 'Check and update',
  '检查更新': 'Check for updates',
  '检查连接': 'Check connection',
  '检查失败，重试': 'Check failed. Retry',
  '检查中…': 'Checking…',
  '将使用设置页保存的 SSH 密码执行重启。如需更换密码，请到设置页修改。':
      'The restart uses the SSH password saved in Settings. Change it in Settings if needed.',
  '解压后未找到 index.html，发布包格式有误':
      'index.html was not found after extraction. The release package is invalid',
  '仅首尾': 'First and last only',
  '进程': 'Process',
  '进站地址': 'Inbound address',
  '进站名': 'Inbound name',
  '开发者选项': 'Developer options',
  '高级选项': 'Advanced options',
  '清理 DNS 缓存': 'Clear DNS cache',
  '清理 DNS 缓存？': 'Clear DNS cache?',
  '清理 DNS 缓存超时，请检查控制器连接':
      'Clearing the DNS cache timed out. Check the controller connection',
  '将清理 Clash 内核的 DNS 解析缓存。确定继续？':
      'This clears the Clash core DNS cache. Continue?',
  '清理失败': 'Cleanup',
  '清理中': 'Clearing',
  '关闭连接': 'Close connections',
  '关闭所有连接？': 'Close all connections?',
  '关闭连接超时，请检查控制器连接':
      'Closing connections timed out. Check the controller connection',
  '将立即关闭所有当前 Clash 代理连接，部分应用可能会自动重新连接。确定继续？':
      'This immediately closes all active Clash proxy connections. Some apps may reconnect automatically. Continue?',
  '关闭中': 'Closing',
  '关闭后不再自动检测新版本，仍可在关于页手动检查更新。':
      'When off, Proxly will not detect new versions automatically. You can still check manually on the About page.',
  '关闭更新检测': 'Disable update checks',
  '开始设置': 'Get started',
  '开源协议': 'Open-source license',
  '控制器地址': 'Controller address',
  '控制器密钥': 'Controller secret',
  '控制台': 'Console',
  '累计上传': 'Total upload',
  '累计下载': 'Total download',
  '立即更新': 'Update now',
  '立即重启': 'Restart now',
  '例如 192.168.1.1:9090': 'For example, 192.168.1.1:9090',
  '连接': 'Connections',
  '连接 Tab 内容': 'Connections tab content',
  '连接ID': 'Connection ID',
  '连接类型': 'Connection type',
  '连接设置': 'Connection settings',
  '连接详情': 'Connection details',
  '连接信息': 'Connection information',
  '连接页显示': 'Connections page display',
  '链接': 'Link',
  '流量信息': 'Traffic information',
  '路由器密码': 'Router password',
  '没有从 OpenClash 配置中找到本地 YAML 文件':
      'No local YAML file was found in the OpenClash configuration',
  '没有可导入的非冲突配置': 'No non-conflicting settings to import',
  '没有找到 YAML 配置文件，可上传新配置。':
      'No YAML configuration found. You can upload a new one.',
  '没有找到可切换的 YAML 配置文件': 'No switchable YAML configuration found',
  '密钥错误，请检查后重试': 'Invalid secret. Check it and try again',
  '密钥验证失败，请检查后重试': 'Secret verification failed. Check it and try again',
  '面板发布包校验失败，请稍后重试':
      'Panel release package verification failed. Please try again later',
  '面板尚未加载，请稍后再试': 'The panel is not ready. Please try again shortly',
  '默认跟随系统，也可以固定为浅色或深色。':
      'Follows the system by default, or choose a fixed light or dark theme.',
  '目标地址': 'Destination address',
  '内核版本': 'Core version',
  '排序': 'Sort',
  '配置文件': 'Configuration file',
  '屏幕上显示可拖动的深浅色切换按钮，长按拖动，点击切换':
      'Show a draggable theme button. Long-press to move it and tap to switch theme',
  '浅色': 'Light',
  '切换并重启': 'Switch and restart',
  '切换当前配置？': 'Switch the active configuration?',
  '切换配置': 'Switch configuration',
  '切换配置失败：请先在设置页填写并保存 SSH 密码':
      'Unable to switch configurations. Save the SSH password in Settings first',
  '切换语言': 'Change language',
  '应用语言': 'App language',
  '语言': 'Language',
  '语言切换会立即应用，并同步内置 Zashboard 面板。':
      'Language changes apply immediately and are synchronized with the built-in Zashboard panel.',
  '请求超时，请检查网络连接后重试':
      'Request timed out. Check your network connection and try again',
  '请输入密码': 'Enter password',
  '请输入路径': 'Enter path',
  '请输入密钥': 'Enter secret',
  '请输入(IP:端口)': 'Enter IP:port',
  '请输入管理密钥': 'Enter the controller secret',
  '请填写 Clash 控制器地址': 'Enter the Clash controller address',
  '请先填写 Clash 控制器地址': 'Enter the Clash controller address first',
  '请先填写 OpenClash 地址': 'Enter the OpenClash address first',
  '请先填写控制器地址': 'Enter the controller address first',
  '请先在设置页填写 Clash 地址': 'Enter the Clash address in Settings first',
  '请先在设置页填写 OpenClash 地址': 'Enter the OpenClash address in Settings first',
  '请先在设置页填写 SSH 密码': 'Enter the SSH password in Settings first',
  '请先在设置页填写并保存 SSH 密码': 'Enter and save the SSH password in Settings first',
  '请选择 .yaml 或 .yml 文件': 'Select a .yaml or .yml file',
  '请允许"安装未知应用"\n开启后重新点击更新':
      'Allow "Install unknown apps"\nThen tap Update again',
  '取消': 'Cancel',
  '稍后': 'Later',
  '去开启': 'Open settings',
  '去设置': 'Go to Settings',
  '确定': 'OK',
  '确认': 'Confirm',
  '确认更新 Zashboard？': 'Update Zashboard?',
  '确认重启': 'Confirm restart',
  '确认重启 OpenClash': 'Restart OpenClash?',
  '配置已保存，是否立即重启 OpenClash 使修改生效？':
      'The configuration was saved. Restart OpenClash now to apply the changes?',
  '让你在手机上实时掌握代理状态、流量用量与连接详情，无需打开浏览器。':
      'so you can monitor proxy status, traffic usage, and connection details without opening a browser.',
  '上传': 'Upload',
  '上传量': 'Uploaded',
  '上传配置': 'Upload configuration',
  '上传速度': 'Upload speed',
  '上传新配置': 'Upload new configuration',
  '文件名': 'File name',
  '请输入文件名': 'Enter a file name',
  '上传目录：/etc/openclash/config': 'Upload directory: /etc/openclash/config',
  '文件名不能为空': 'File name cannot be empty',
  '文件名不能是 . 或 ..': 'File name cannot be . or ..',
  '文件名不能包含路径分隔符或控制字符':
      'File name cannot contain path separators or control characters',
  '文件名需以 .yaml 或 .yml 结尾': 'File name must end with .yaml or .yml',
  '文件名无效，请输入 .yaml 或 .yml 文件名':
      'Invalid file name. Enter a .yaml or .yml file name',
  '目标文件名已存在': 'A file with that name already exists',
  '重命名失败且无法完整回滚，请检查当前配置文件和 OpenClash 配置引用':
      'Rename failed and could not be fully rolled back. Check the configuration file and OpenClash reference',
  '无法更新 OpenClash 配置引用，文件名已恢复':
      'The OpenClash configuration reference could not be updated. The file name was restored',
  '重命名': 'Rename',
  '导出': 'Export',
  '导出配置': 'Export configuration',
  '正在使用': 'Active configuration',
  '总行数': 'Lines',
  '编码': 'Encoding',
  '尚未读取': 'Not loaded yet',
  '设置': 'Settings',
  '设置外观模式和连接页默认显示方式':
      'Choose the appearance and default Connections page display',
  '设置页未保存 SSH 密码，本次输入后会同步保存到设置页。':
      'No SSH password is saved in Settings. This password will also be saved there.',
  '设置已保存': 'Settings saved',
  '深色': 'Dark',
  '时间 旧→新': 'Time: oldest first',
  '时间 新→旧': 'Time: newest first',
  '实时流量': 'Live traffic',
  '使用偏好': 'Preferences',
  '是否立即下载并安装？': 'Download and install now?',
  '首页': 'Home',
  '刷新当前配置': 'Refresh active configuration',
  '刷新列表': 'Refresh list',
  '填写控制器地址；密钥和 SSH 密码可按需填写，之后可在设置页修改':
      'Enter the controller address. The secret and SSH password are optional and can be changed later in Settings',
  '填写 OpenClash 外部控制地址，格式为 IP:端口':
      'Enter the OpenClash controller address in IP:port format',
  '填写 config 文件夹内的目标路径，例如 /etc/openclash/config/config.yaml':
      'Enter a target path in the config folder, for example /etc/openclash/config/config.yaml',
  '跳过此版本': 'Skip this version',
  '通过 Zashboard 管理代理节点': 'Manage proxy nodes with Zashboard',
  '外部控制密钥（可选）': 'External controller secret (optional)',
  '外观模式': 'Appearance',
  '外观主题': 'Theme',
  '完成设置': 'Finish setup',
  '完整链路': 'Full chain',
  '未保存': 'Unsaved',
  '未连接': 'Not connected',
  '未配置 Clash 地址': 'Clash address not configured',
  '未设置密钥可留空': 'Leave blank if no secret is configured',
  '未使用 YAML 配置': 'Not using a YAML configuration',
  '未知版本': 'Unknown version',
  '文件超过 5 MB 限制': 'File exceeds the 5 MB limit',
  '无法连接，请检查地址是否正确': 'Unable to connect. Check the address',
  '无法连接控制器，请检查地址和端口':
      'Unable to connect to the controller. Check the address and port',
  '无更新': 'No updates',
  '下载量': 'Downloaded',
  '下载': 'Download',
  '下载内容 SHA256 校验失败': 'Downloaded file failed SHA256 verification',
  '下载内容不是有效 APK': 'Downloaded file is not a valid APK',
  '下载速度': 'Download speed',
  '显示控制台按钮': 'Show Console button',
  '在首页左上角显示 Zashboard 控制台入口':
      'Show the Zashboard Console shortcut in the top-left corner of Home',
  '显示主题悬浮球': 'Show floating theme button',
  '新连接': 'New connection',
  '嗅探主机': 'Sniffed host',
  '需要 SSH 密码': 'SSH password required',
  '选择 YAML 配置': 'Select YAML configuration',
  'YAML 配置文件': 'YAML configuration files',
  '选择 YAML 配置文件': 'Select a YAML configuration file',
  '选择底部「连接」Tab 的显示内容': 'Choose what to show in the bottom Connections tab',
  '选择后会写入 OpenClash 当前配置，并在确认后重启。':
      'The selected file becomes the active OpenClash configuration and OpenClash restarts after confirmation.',
  '已复制': 'Copied',
  '版本号已复制': 'Version copied',
  '已同步': 'Synced',
  '用于读取和编辑 OpenClash 配置文件':
      'Used to read and edit OpenClash configuration files',
  '用于访问已设置密钥的控制器，未设置可留空': 'Required only when the controller uses a secret',
  '用于管理 YAML 配置和重启 OpenClash，未使用 SSH 可留空':
      'Used to manage YAML configurations and restart OpenClash; optional when SSH is not used',
  '用于管理配置文件和重启 OpenClash':
      'Used to manage configuration files and restart OpenClash',
  '已用': 'Used',
  '原生列表': 'Native list',
  '原生列表响应更快；Zashboard 面板会以移动端模式打开。':
      'The native list is faster; the Zashboard panel opens in mobile mode.',
  '源地址': 'Source address',
  '远程路径': 'Remote path',
  '远程路径需以 .yaml 或 .yml 结尾': 'The remote path must end with .yaml or .yml',
  '远端地址': 'Remote address',
  '运行概览': 'Overview',
  '运行中': 'Running',
  '在 GitHub Releases 查看所有版本': 'View all versions on GitHub Releases',
  '在 GitHub 查看完整功能说明': 'View the full feature guide on GitHub',
  '暂无活跃连接': 'No active connections',
  '正在读取...': 'Loading...',
  '正在加载控制台': 'Loading console',
  '正在检查最新版本…': 'Checking for the latest version…',
  '正在解压…': 'Extracting…',
  '正在解压面板文件…': 'Extracting panel files…',
  '正在连接 SSH...': 'Connecting over SSH...',
  '正在保存设置...': 'Saving settings...',
  '正在切换配置并重启 OpenClash...':
      'Switching configuration and restarting OpenClash...',
  '正在重启 OpenClash...': 'Restarting OpenClash...',
  '正在验证设置...': 'Verifying settings...',
  '剩余': 'Remaining',
  '总量': 'Total',
  '无限制': 'Unlimited',
  '维护操作': 'Maintenance',
  '重启 OpenClash，或维护 Clash 内核的 DNS 缓存与代理连接。':
      'Restart OpenClash, clear the DNS cache, or close all proxy connections.',
  '直连': 'Direct',
  '只扫描 Clash/OpenClash 目录下的 config 文件夹。':
      'Only config folders under Clash/OpenClash directories are scanned.',
  '只支持上传到 Clash/OpenClash config 文件夹内的 YAML 文件':
      'YAML files can only be uploaded into a Clash/OpenClash config folder',
  '只支持上传到 Clash/OpenClash 的 config 文件夹':
      'Uploads are limited to Clash/OpenClash config folders',
  '重启 Clash': 'Restart Clash',
  '重启': 'Restart',
  '重启 OpenClash': 'Restart OpenClash',
  '重启中': 'Restarting',
  '重启失败': 'Restart failed',
  '重试': 'Retry',
  'OpenClash 快捷设置': 'OpenClash quick settings',
  '设置会立即应用；切换运行模式时现有连接可能短暂重连。':
      'Changes apply immediately; existing connections may briefly reconnect when the running mode changes.',
  '正在应用设置...': 'Applying setting...',
  'Clash 返回了不支持的代理模式': 'Clash returned an unsupported proxy mode',
  '读取快捷设置': 'Load quick settings',
  '直接读取并调整 OpenClash 当前运行参数':
      'Read and adjust the active OpenClash runtime settings',
  '运行模式': 'Running mode',
  '所有 Clash 代理连接已关闭': 'All Clash proxy connections have been closed',
  '更新检测': 'Update checks',
  '当前基础模式由 OpenClash 管理，可选择对应运行方式':
      'OpenClash manages the base mode; choose the corresponding runtime type',
  '增强': 'Enhanced',
  '兼容': 'Compatible',
  '混合': 'Mixed',
  '代理模式': 'Proxy mode',
  '切换 Mihomo 处理连接时使用的规则范围': 'Choose how Mihomo applies rules to connections',
  '全局': 'Global',
  '区域绕过': 'Area bypass',
  '指定区域流量不经过内核': 'Bypass the core for the selected region',
  '未知错误': 'Unknown error',
  '大陆': 'Mainland',
  '海外': 'Overseas',
  '停用': 'Off',
  '域名嗅探': 'Domain sniffing',
  '识别连接中的域名，降低按域名分流失效的概率':
      'Detect domains in connections to improve domain-based routing',
  'DNS 代理': 'DNS proxy',
  '让 DNS 查询遵循代理规则，减少解析与访问不一致':
      'Make DNS queries follow proxy rules to avoid routing inconsistencies',
  '流媒体解锁': 'Streaming unlock',
  '自动为常见流媒体服务选择可解锁节点':
      'Automatically select unlock-capable nodes for popular streaming services',
  '当前 OpenClash 未提供流媒体解锁组件':
      'The current OpenClash installation does not provide streaming unlock',
  '需要先在 OpenClash 中启用路由器本机代理': 'Enable router-self proxy in OpenClash first',
  '仅支持规则代理模式': 'Available only in Rule mode',
  '流媒体解锁仅支持规则代理模式': 'Streaming unlock is available only in Rule mode',
  '请先在 OpenClash 中启用路由器本机代理': 'Enable router-self proxy in OpenClash first',
  '请先关闭流媒体解锁': 'Turn off streaming unlock first',
  '运行模式已更新': 'Running mode updated',
  '代理模式已更新': 'Proxy mode updated',
  '区域绕过已更新': 'Area bypass updated',
  '域名嗅探已更新': 'Domain sniffing updated',
  'DNS 代理已更新': 'DNS proxy updated',
  '流媒体解锁已更新': 'Streaming unlock updated',
  '流媒体解锁已启用，后台任务将在下一轮检测中生效':
      'Streaming unlock enabled; the background task will pick it up on its next check',
  '流媒体解锁已关闭': 'Streaming unlock disabled',
  '增加缩进': 'Indent',
  '减少缩进': 'Outdent',
  '光标左移': 'Move cursor left',
  '光标右移': 'Move cursor right',
  '光标上移': 'Move cursor up',
  '光标下移': 'Move cursor down',
  '当前环境缺少 UCI 工具': 'UCI is unavailable in the current environment',
  '当前环境缺少 Curl 工具': 'Curl is unavailable in the current environment',
  '当前环境缺少 Ruby，无法安全修改运行时配置':
      'Ruby is unavailable, so the runtime configuration cannot be changed safely',
  'Mihomo 当前未运行': 'Mihomo is not running',
  '未找到 OpenClash 生成的运行时配置':
      'The OpenClash-generated runtime configuration was not found',
  '当前环境不支持 OpenClash 防火墙重载':
      'The current environment does not support OpenClash firewall reloads',
  '当前运行模式不支持无重启切换':
      'The current running mode cannot be changed without a restart',
  '无法创建设置备份': 'Unable to create a settings backup',
  '运行时配置修改失败': 'Failed to modify the runtime configuration',
  'Mihomo 热重载失败': 'Mihomo hot reload failed',
  'OpenClash 防火墙重载失败': 'OpenClash firewall reload failed',
  'OpenClash 设置保存失败': 'Failed to save OpenClash settings',
  '重新读取后设置未生效': 'The setting did not take effect after verification',
  'Mihomo 未能连续通过健康检查': 'Mihomo did not pass consecutive health checks',
  'APK 文件超过 250 MB 限制': 'The APK exceeds the 250 MB limit',
  '检测到 Mihomo 进程发生变化': 'The Mihomo process changed during the operation',
  '实际状态可能不完整，请检查 OpenClash':
      'The actual state may be incomplete; check OpenClash',
  '当前环境无法完成无重启切换':
      'The current environment cannot complete a restart-free change',
  '检测版本': 'Check version',
  '检测中…': 'Checking…',
  '检查': 'Check',
  '版本格式异常': 'Invalid version format',
  'SSH 设备信任': 'Trusted SSH devices',
  '尚未信任 SSH 设备': 'No trusted SSH devices',
  '清除 SSH 信任': 'Clear SSH trust',
  '清除 SSH 信任？': 'Clear trusted SSH devices?',
  '清除后，下次执行 YAML、快捷设置或重启操作时，需要重新确认设备指纹。':
      'After clearing trust, you must verify the device fingerprint again before using YAML, quick settings, or restart actions.',
  'SSH 信任已清除': 'SSH trust cleared',
  '确认 SSH 设备身份': 'Verify SSH device identity',
  'SSH 身份指纹已变化': 'SSH host fingerprint changed',
  '首次连接此 SSH 设备。请确认该指纹属于你的路由器，确认前不会发送 SSH 密码。':
      'This is the first connection to this SSH device. Verify that the fingerprint belongs to your router. The SSH password will not be sent before confirmation.',
  '设备指纹与此前记录不一致。可能是路由器重装或更新，也可能存在冒充风险。请确认后再继续。':
      'The device fingerprint differs from the trusted record. The router may have been reinstalled or updated, but this can also indicate impersonation. Verify it before continuing.',
  '设备': 'Device',
  '算法': 'Algorithm',
  '旧指纹': 'Previous fingerprint',
  '新指纹': 'New fingerprint',
  'SHA-256 指纹': 'SHA-256 fingerprint',
  '信任并继续': 'Trust and continue',
  '信任新指纹并继续': 'Trust new fingerprint and continue',
  '发布包超过 50 MB，已停止下载': 'The release package exceeds 50 MB. Download stopped',
  '发布包文件数量超过 2000 项': 'The release package contains more than 2,000 entries',
  '发布包包含异常条目': 'The release package contains an invalid entry',
  '发布包解压后的总大小超过 100 MB': 'The extracted release package exceeds 100 MB',
  '配置文件超过 5 MB，无法导入': 'The settings file exceeds 5 MB and cannot be imported',
  '配置项超过 2000 个，无法导入':
      'The settings file contains more than 2,000 entries and cannot be imported',
  'Copyright © 2026 Proxly\n\n本软件以 MIT 协议开源，允许任何人免费使用、复制、修改、合并、发布、分发、再授权及销售本软件的副本，但须保留上述版权声明与本许可声明。\n\n本软件按"原样"提供，不附带任何明示或暗示的担保。':
      'Copyright © 2026 Proxly\n\nThis software is licensed under the MIT License. Permission is granted to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies, provided that the copyright and permission notices are retained.\n\nThis software is provided "as is", without warranty of any kind, express or implied.',
};

String? _dynamicEnglish(String source) {
  Match? match;
  if ((match = RegExp(r'^插入 (.+)$').firstMatch(source)) != null) {
    return 'Insert ${match![1]}';
  }
  if ((match = RegExp(r'^应用失败，已恢复原设置：(.+)$').firstMatch(source)) != null) {
    return 'Change failed and the previous setting was restored: ${_english[match![1]] ?? match[1]}';
  }
  if ((match = RegExp(r'^应用失败且未能完整回滚：(.+)$').firstMatch(source)) != null) {
    return 'The change and rollback both failed: ${_english[match![1]] ?? match[1]}';
  }
  if ((match = RegExp(r'^应用失败：(.+)$').firstMatch(source)) != null) {
    return 'Change failed: ${_english[match![1]] ?? match[1]}';
  }
  if ((match = RegExp(r'^(\d+)分钟前$').firstMatch(source)) != null) {
    return '${match![1]} minutes ago';
  }
  if ((match = RegExp(r'^所在目录：(.+)$').firstMatch(source)) != null) {
    return 'Directory: ${match![1]}';
  }
  if ((match = RegExp(r'^总行数：(\d+)$').firstMatch(source)) != null) {
    return 'Lines: ${match![1]}';
  }
  if ((match = RegExp(r'^行 (\d+)，列 (\d+)$').firstMatch(source)) != null) {
    return 'Line ${match![1]}, column ${match[2]}';
  }
  if (source == '编码：UTF-8') return 'Encoding: UTF-8';
  if ((match = RegExp(r'^(\d+)小时前$').firstMatch(source)) != null) {
    return '${match![1]} hours ago';
  }
  if ((match = RegExp(r'^设置已保存但重启失败：(.+)$').firstMatch(source)) != null) {
    return 'Settings were saved, but OpenClash failed to restart: ${match![1]}';
  }
  if ((match = RegExp(r'^配置已切换，但 OpenClash 重启失败：(.+)$').firstMatch(source)) !=
      null) {
    return 'The configuration was switched, but OpenClash failed to restart: ${match![1]}';
  }
  if ((match = RegExp(r'^(.+)失败：(.+)$').firstMatch(source)) != null) {
    final failureMatch = match!;
    return '${_english[failureMatch[1]] ?? failureMatch[1]} failed: ${failureMatch[2]}';
  }
  if ((match = RegExp(r'^错误：(.+)$').firstMatch(source)) != null) {
    return 'Error: ${match![1]}';
  }
  if ((match = RegExp(r'^无法连接：(.+)$').firstMatch(source)) != null) {
    return 'Unable to connect: ${match![1]}';
  }
  if ((match = RegExp(r'^连接(?:正常|成功) · Clash (.+)$').firstMatch(source)) !=
      null) {
    return 'Connected · Clash ${match![1]}';
  }
  if ((match = RegExp(r'^连接失败 · (?:HTTP|状态码) (.+)$').firstMatch(source)) !=
      null) {
    return 'Connection failed · HTTP ${match![1]}';
  }
  if ((match = RegExp(r'^请求失败 (.+)$').firstMatch(source)) != null) {
    return 'Request failed: ${match![1]}';
  }
  if ((match =
          RegExp(r'^下载失败(?: HTTP|:|：| \()?(.+?)(?:\))?$').firstMatch(source)) !=
      null) {
    return 'Download failed: ${match![1]!.trim()}';
  }
  if ((match = RegExp(r'^(.+) 行$').firstMatch(source)) != null) {
    return '${match![1]} lines';
  }
  if ((match = RegExp(r'^行 (.+), 列 (.+)$').firstMatch(source)) != null) {
    final positionMatch = match!;
    return 'Line ${positionMatch[1]}, column ${positionMatch[2]}';
  }
  if ((match = RegExp(r'^版本 (.+)$').firstMatch(source)) != null) {
    return 'Version ${match![1]}';
  }
  if ((match = RegExp(r'^发现新版本 (.+)$').firstMatch(source)) != null) {
    return 'New version ${match![1]} available';
  }
  if ((match = RegExp(r'^当前已是最新版本 (.+)$').firstMatch(source)) != null) {
    return 'You already have the latest version (${match![1]})';
  }
  if ((match =
          RegExp(r'^(?:正在)?下载 (.+?)(?:… (\d+)%|…)?$').firstMatch(source)) !=
      null) {
    final progress = match![2];
    return progress == null
        ? 'Downloading ${match[1]}…'
        : 'Downloading ${match[1]}… $progress%';
  }
  if ((match = RegExp(r'^已保存 (.+)，修改会在重启 OpenClash 后生效$').firstMatch(source)) !=
      null) {
    return 'Saved ${match![1]}. Changes take effect after OpenClash restarts';
  }
  if ((match = RegExp(r'^已保存 (.+)$').firstMatch(source)) != null) {
    return 'Saved ${match![1]}';
  }
  if ((match = RegExp(r'^已上传 (.+)$').firstMatch(source)) != null) {
    return 'Uploaded ${match![1]}';
  }
  if ((match = RegExp(r'^已重命名为 (.+)$').firstMatch(source)) != null) {
    return 'Renamed to ${match![1]}';
  }
  if ((match = RegExp(r'^已导出 (.+)$').firstMatch(source)) != null) {
    return 'Exported ${match![1]}';
  }
  if ((match = RegExp(r'^已删除 (.+)$').firstMatch(source)) != null) {
    return 'Deleted ${match!.group(1)}';
  }
  if ((match = RegExp(r'^已发现 (\d+) 个 YAML 文件$').firstMatch(source)) != null) {
    return 'Found ${match![1]} YAML files';
  }
  if ((match = RegExp(r'^正在切换到 (.+)$').firstMatch(source)) != null) {
    return 'Switching to ${match![1]}';
  }
  if ((match = RegExp(r'^已切换到 (.+)，OpenClash 正在重启$').firstMatch(source)) !=
      null) {
    return 'Switched to ${match![1]}; OpenClash is restarting';
  }
  if ((match = RegExp(r'^已切换到 (.+)$').firstMatch(source)) != null) {
    return 'Switched to ${match![1]}';
  }
  if ((match = RegExp(r'^将切换到 (.+) 并重启 OpenClash。重启期间代理会短暂断开。$')
          .firstMatch(source)) !=
      null) {
    return 'Switch to ${match![1]} and restart OpenClash? The proxy will be briefly unavailable.';
  }
  if ((match = RegExp(r'^已导入 (\d+) 项配置，跳过 (\d+) 项冲突数据$').firstMatch(source)) !=
      null) {
    return 'Imported ${match![1]} settings and skipped ${match[2]} conflicting entries';
  }
  if ((match = RegExp(r'^已信任 (\d+) 台 SSH 设备$').firstMatch(source)) != null) {
    return '${match![1]} trusted SSH devices';
  }
  if ((match = RegExp(r'^配置已导入，但有 (\d+) 个页面未能立即刷新$').firstMatch(source)) !=
      null) {
    return 'Settings imported, but ${match![1]} pages could not refresh immediately';
  }
  if ((match = RegExp(r'^发布包包含不支持的符号链接: (.+)$').firstMatch(source)) != null) {
    return 'The release package contains an unsupported symbolic link: ${match![1]}';
  }
  if ((match = RegExp(r'^发布包中的单个文件超过 20 MB: (.+)$').firstMatch(source)) !=
      null) {
    return 'A file in the release package exceeds 20 MB: ${match![1]}';
  }
  if ((match = RegExp(r'^发布包包含异常压缩文件: (.+)$').firstMatch(source)) != null) {
    return 'The release package contains a suspiciously compressed file: ${match![1]}';
  }
  if ((match = RegExp(r'^发布包包含重复路径: (.+)$').firstMatch(source)) != null) {
    return 'The release package contains a duplicate path: ${match![1]}';
  }
  if ((match = RegExp(r'^发布包包含冲突路径: (.+)$').firstMatch(source)) != null) {
    return 'The release package contains a conflicting path: ${match![1]}';
  }
  if ((match = RegExp(r'^配置项 (.+) 超过 1 MB，无法导入$').firstMatch(source)) != null) {
    return 'Setting ${match![1]} exceeds 1 MB and cannot be imported';
  }
  if ((match = RegExp(r'^GitHub API 请求失败 \((.+)\)$').firstMatch(source)) !=
      null) {
    return 'GitHub API request failed (${match![1]})';
  }
  if ((match = RegExp(r'^发布包包含不安全路径: (.+)$').firstMatch(source)) != null) {
    return 'The release package contains an unsafe path: ${match![1]}';
  }
  if ((match = RegExp(r'^下载内容类型异常: (.+)$').firstMatch(source)) != null) {
    return 'Unexpected download content type: ${match![1]}';
  }
  if ((match = RegExp(r'^安装失败\((.+)\): (.+)$').firstMatch(source)) != null) {
    return 'Installation failed (${match![1]}): ${match[2]}';
  }
  if ((match = RegExp(r'^已发送切换命令，但当前仍显示为订阅模式，请检查 OpenClash 配置$')
          .firstMatch(source)) !=
      null) {
    return 'The switch command was sent, but the active source is still shown as subscription mode. Check the OpenClash configuration.';
  }
  if (source == '已发送切换命令，但未能确认当前配置已变更') {
    return 'The switch command was sent, but the active configuration change could not be confirmed.';
  }
  if ((match = RegExp(r'^新版本 (.+)$').firstMatch(source)) != null) {
    return 'New version ${match![1]}';
  }
  return null;
}
