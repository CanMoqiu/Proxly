import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/dashboard_layout_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'layout keeps order and visibility across launches and restores defaults',
      () async {
    SharedPreferences.setMockInitialValues({});
    final layout = DashboardLayoutStore();
    await layout.load();
    expect(layout.order.take(4), [
      DashboardCardId.status,
      DashboardCardId.currentYaml,
      DashboardCardId.operations,
      DashboardCardId.quickSettings
    ]);
    await layout.reorder(3, 0);
    await layout.setVisible(DashboardCardId.currentYaml, false);
    final restored = DashboardLayoutStore();
    await restored.load();
    expect(restored.order, layout.order);
    expect(restored.visible, isNot(contains(DashboardCardId.currentYaml)));
    await restored.reset();
    final defaults = DashboardLayoutStore();
    await defaults.load();
    expect(defaults.visible, DashboardCardId.values);
    layout.dispose();
    restored.dispose();
    defaults.dispose();
  });

  test('unknown IDs and duplicates do not lose new or hidden cards', () async {
    SharedPreferences.setMockInitialValues({
      DashboardLayoutStore.preferenceKey: jsonEncode({
        'version': 1,
        'order': ['overview', 'unknown', 'overview', 'status'],
        'hidden': ['status', 'unknown']
      })
    });
    final layout = DashboardLayoutStore();
    await layout.load();
    expect(layout.order.first, DashboardCardId.overview);
    expect(layout.order.toSet(), DashboardCardId.values.toSet());
    expect(layout.order.length, DashboardCardId.values.length);
    expect(layout.isVisible(DashboardCardId.status), isFalse);
    layout.dispose();
  });

  test('malformed layouts fall back without blocking dashboard access',
      () async {
    for (final value in [
      '{',
      '[]',
      '{"version":1,"order":4}',
      '{"version":2}'
    ]) {
      SharedPreferences.setMockInitialValues(
          {DashboardLayoutStore.preferenceKey: value});
      final layout = DashboardLayoutStore();
      await layout.load();
      expect(layout.visible, DashboardCardId.values);
      layout.dispose();
    }
  });

  test('rapid changes persist the newest complete layout even after disposal',
      () async {
    SharedPreferences.setMockInitialValues({});
    final layout = DashboardLayoutStore();
    final saves = [
      layout.setVisible(DashboardCardId.status, false),
      layout.reorder(0, 5),
      layout.setVisible(DashboardCardId.status, true),
      layout.setVisible(DashboardCardId.traffic, false)
    ];
    final order = layout.order;
    final visible = layout.visible;
    layout.dispose();
    await Future.wait(saves);
    final restored = DashboardLayoutStore();
    await restored.load();
    expect(restored.order, order);
    expect(restored.visible, visible);
    restored.dispose();
  });
}
