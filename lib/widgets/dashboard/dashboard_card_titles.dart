import '../../l10n/app_locale.dart';
import '../../services/dashboard_layout_store.dart';

export '../../services/dashboard_layout_store.dart' show DashboardCardId;

String dashboardCardTitle(DashboardCardId id) => tr(switch (id) {
      DashboardCardId.status => '运行状态',
      DashboardCardId.traffic => '流量信息',
      DashboardCardId.overview => '运行概览',
      DashboardCardId.currentYaml => '当前配置',
      DashboardCardId.operations => '运行操作',
      DashboardCardId.quickSettings => '快捷设置',
    });
