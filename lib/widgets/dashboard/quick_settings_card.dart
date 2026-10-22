import 'dashboard_card_titles.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_locale.dart';
import '../../theme/app_theme.dart';
import '../adaptive_ui.dart';
import '../../services/openclash_quick_settings_service.dart';
import 'dashboard_button_style.dart';

class OpenClashQuickSettingsCard extends StatelessWidget {
  final OpenClashQuickSettings? settings;
  final bool readFailed;
  final bool busy;
  final Color cardBg;
  final Color cardBorder;
  final Color textColor;
  final Color hintColor;
  final ValueChanged<OpenClashBaseMode> onBaseModeChanged;
  final ValueChanged<OpenClashRunVariant> onRunVariantChanged;
  final ValueChanged<OpenClashProxyMode> onProxyModeChanged;
  final ValueChanged<OpenClashAreaBypass> onAreaBypassChanged;
  final ValueChanged<bool> onSnifferChanged;
  final ValueChanged<bool> onDnsProxyChanged;
  final ValueChanged<bool> onStreamUnlockChanged;

  const OpenClashQuickSettingsCard({
    super.key,
    required this.settings,
    this.readFailed = false,
    required this.busy,
    required this.cardBg,
    required this.cardBorder,
    required this.textColor,
    required this.hintColor,
    required this.onBaseModeChanged,
    required this.onRunVariantChanged,
    required this.onProxyModeChanged,
    required this.onAreaBypassChanged,
    required this.onSnifferChanged,
    required this.onDnsProxyChanged,
    required this.onStreamUnlockChanged,
  });

  @override
  Widget build(BuildContext context) {
    final current = settings;
    final enabled = current != null && !busy && !readFailed;
    final compatibilityLabel =
        current?.baseMode == OpenClashBaseMode.fakeIp ? tr('增强') : tr('兼容');
    final runModeSupported = current?.baseMode != OpenClashBaseMode.unknown &&
        current?.runVariant != null;

    var streamDescription = tr('自动为常见流媒体服务选择可解锁节点');
    if (current != null && !current.streamUnlockSupported) {
      streamDescription = tr('当前 OpenClash 未提供流媒体解锁组件');
    } else if (current != null && !current.routerSelfProxyEnabled) {
      streamDescription = tr('需要先在 OpenClash 中启用路由器本机代理');
    } else if (current != null &&
        current.proxyMode != OpenClashProxyMode.rule) {
      streamDescription = tr('仅支持规则代理模式');
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 0.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveSingleLineText(
            dashboardCardTitle(DashboardCardId.quickSettings),
            alignment: Alignment.centerLeft,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: 16),
          if (readFailed) ...[
            Text(
              tr('快捷设置暂时无法刷新，请检查软路由连接和 SSH 设置。'),
              style: TextStyle(fontSize: 12, color: hintColor),
            ),
            const SizedBox(height: 12),
          ],
          _QuickChoiceGroup<OpenClashBaseMode>(
            labels: const ['Fake-IP', 'Redir-Host'],
            values: const [
              OpenClashBaseMode.fakeIp,
              OpenClashBaseMode.redirHost
            ],
            selected: current?.baseMode,
            enabled: enabled && runModeSupported,
            valueKeyPrefix: 'quick_setting_base',
            onSelected: onBaseModeChanged,
          ),
          const SizedBox(height: 16),
          _QuickSettingsSection(
            title: tr('运行模式'),
            description: tr('选择当前基础模式对应的运行方式'),
            textColor: textColor,
            hintColor: hintColor,
            child: _QuickChoiceGroup<OpenClashRunVariant>(
              labels: [compatibilityLabel, 'TUN', tr('混合')],
              values: OpenClashRunVariant.values,
              selected: current?.runVariant,
              enabled: enabled && runModeSupported,
              valueKeyPrefix: 'quick_setting_run',
              onSelected: onRunVariantChanged,
            ),
          ),
          Divider(height: 24, color: cardBorder),
          _QuickSettingsSection(
            title: tr('代理模式'),
            description: tr('切换 Mihomo 处理连接时使用的规则范围'),
            textColor: textColor,
            hintColor: hintColor,
            child: _QuickChoiceGroup<OpenClashProxyMode>(
              labels: [tr('规则'), tr('全局'), tr('直连')],
              values: OpenClashProxyMode.values,
              selected: current?.proxyMode,
              enabled: enabled,
              valueKeyPrefix: 'quick_setting_proxy',
              onSelected: onProxyModeChanged,
            ),
          ),
          Divider(height: 24, color: cardBorder),
          _QuickSettingsSection(
            title: tr('区域绕过'),
            description: tr('指定区域流量不经过内核'),
            textColor: textColor,
            hintColor: hintColor,
            child: _QuickChoiceGroup<OpenClashAreaBypass>(
              labels: [tr('大陆'), tr('海外'), tr('停用')],
              values: const [
                OpenClashAreaBypass.mainland,
                OpenClashAreaBypass.overseas,
                OpenClashAreaBypass.disabled,
              ],
              selected: current?.areaBypass,
              enabled: enabled,
              valueKeyPrefix: 'quick_setting_area',
              onSelected: onAreaBypassChanged,
            ),
          ),
          Divider(height: 24, color: cardBorder),
          _QuickSwitchRow(
            key: const ValueKey('quick_setting_sniffer'),
            title: tr('域名嗅探'),
            description: tr('识别连接中的域名，降低按域名分流失效的概率'),
            value: current?.snifferEnabled ?? false,
            enabled: enabled,
            textColor: textColor,
            hintColor: hintColor,
            onChanged: onSnifferChanged,
          ),
          Divider(height: 16, color: cardBorder),
          _QuickSwitchRow(
            key: const ValueKey('quick_setting_dns_proxy'),
            title: tr('DNS 代理'),
            description: tr('让 DNS 查询遵循代理规则，减少解析与访问不一致'),
            value: current?.dnsProxyEnabled ?? false,
            enabled: enabled,
            textColor: textColor,
            hintColor: hintColor,
            onChanged: onDnsProxyChanged,
          ),
          Divider(height: 16, color: cardBorder),
          _QuickSwitchRow(
            key: const ValueKey('quick_setting_stream_unlock'),
            title: tr('流媒体解锁'),
            description: streamDescription,
            value: current?.streamUnlockEnabled ?? false,
            enabled: enabled,
            textColor: textColor,
            hintColor: hintColor,
            onChanged: onStreamUnlockChanged,
          ),
        ],
      ),
    );
  }
}

class _QuickSettingsSection extends StatelessWidget {
  final String title;
  final String description;
  final Color textColor;
  final Color hintColor;
  final Widget child;

  const _QuickSettingsSection({
    required this.title,
    required this.description,
    required this.textColor,
    required this.hintColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 11, color: hintColor),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _QuickChoiceGroup<T> extends StatelessWidget {
  final List<String> labels;
  final List<T> values;
  final T? selected;
  final bool enabled;
  final String valueKeyPrefix;
  final ValueChanged<T> onSelected;

  const _QuickChoiceGroup({
    required this.labels,
    required this.values,
    required this.selected,
    required this.enabled,
    required this.valueKeyPrefix,
    required this.onSelected,
  }) : assert(labels.length == values.length);

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      key: ValueKey('${valueKeyPrefix}_group'),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.inputBackground,
        borderRadius:
            BorderRadius.circular(DashboardButtonStyle.cornerRadius + 3),
        border: Border.all(color: palette.border, width: 0.5),
      ),
      child: AdaptiveOptionGroup(
        labels: labels,
        spacing: 0,
        reservedItemWidth: DashboardButtonStyle.padding.horizontal + 2,
        children: [
          for (var index = 0; index < values.length; index++)
            _QuickChoiceButton(
              key: ValueKey('${valueKeyPrefix}_${values[index]}'),
              label: labels[index],
              selected: selected == values[index],
              enabled: enabled,
              onTap: () => onSelected(values[index]),
            ),
        ],
      ),
    );
  }
}

class _QuickChoiceButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _QuickChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AdaptiveSelectionButton(
      label: label,
      selected: selected,
      enabled: enabled,
      onTap: onTap,
      minimumHeight: DashboardButtonStyle.minimumHeight,
      cornerRadius: DashboardButtonStyle.cornerRadius,
      showUnselectedBorder: false,
      padding: DashboardButtonStyle.padding,
    );
  }
}

class _QuickSwitchRow extends StatelessWidget {
  final String title;
  final String description;
  final bool value;
  final bool enabled;
  final Color textColor;
  final Color hintColor;
  final ValueChanged<bool> onChanged;

  const _QuickSwitchRow({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.enabled,
    required this.textColor,
    required this.hintColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(fontSize: 11, color: hintColor),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          value: value,
          onChanged: enabled ? onChanged : null,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }
}
