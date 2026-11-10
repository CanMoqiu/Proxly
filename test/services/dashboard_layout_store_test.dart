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
    expect(layout.order, [
      DashboardCardId.status,
      DashboardCardId.traffic,
      DashboardCardId.overview,
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

  test('software filtering preserves custom slots and manual visibility',
      () async {
    SharedPreferences.setMockInitialValues({});
    final layout = DashboardLayoutStore();
    await layout.reorder(3, 0);
    await layout.setVisible(DashboardCardId.traffic, false);
    final original = layout.order;
    final unavailable = {DashboardCardId.currentYaml};
    final filtered = layout.availableOrder(unavailable: unavailable);
    expect(filtered, original.where((id) => !unavailable.contains(id)));
    await layout.reorder(0, 3, unavailable: unavailable);
    expect(layout.order.first, DashboardCardId.currentYaml);
    expect(layout.isVisible(DashboardCardId.traffic), isFalse);
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(DashboardLayoutStore.preferenceKey);
    for (final excluded in [unavailable, <DashboardCardId>{}, unavailable]) {
      layout.availableOrder(unavailable: excluded);
    }
    expect(prefs.getString(DashboardLayoutStore.preferenceKey), stored);
    final restored = DashboardLayoutStore();
    await restored.load();
    expect(restored.order, layout.order);
    expect(restored.availableOrder().first, DashboardCardId.currentYaml);
    expect(restored.isVisible(DashboardCardId.traffic), isFalse);
    layout.dispose();
    restored.dispose();
  });

  test('never arranged cards follow saved custom cards after software changes',
      () async {
    SharedPreferences.setMockInitialValues({});
    final layout = DashboardLayoutStore();
    await layout.setVisible(DashboardCardId.traffic, false);
    await layout.reorder(4, 0, unavailable: {DashboardCardId.currentYaml});
    final arranged =
        layout.availableOrder(unavailable: {DashboardCardId.currentYaml});
    final restored = DashboardLayoutStore();
    await restored.load();
    expect(
        restored.availableOrder(), [...arranged, DashboardCardId.currentYaml]);
    expect(restored.isVisible(DashboardCardId.traffic), isFalse);
    await restored.reorder(5, 1);
    expect(restored.availableOrder()[1], DashboardCardId.currentYaml);
    restored.availableOrder(unavailable: {DashboardCardId.currentYaml});
    expect(restored.availableOrder()[1], DashboardCardId.currentYaml);
    await restored.reset();
    expect(restored.availableOrder(), DashboardCardId.values);
    expect(restored.visible, DashboardCardId.values);
    layout.dispose();
    restored.dispose();
  });

  test('legacy custom order retains known cards and appends later additions',
      () async {
    SharedPreferences.setMockInitialValues({
      DashboardLayoutStore.preferenceKey: jsonEncode({
        'version': 2,
        'order': ['operations', 'status', 'overview'],
        'hidden': ['status']
      })
    });
    final layout = DashboardLayoutStore();
    await layout.load();
    expect(layout.availableOrder(), [
      DashboardCardId.operations,
      DashboardCardId.status,
      DashboardCardId.overview,
      DashboardCardId.traffic,
      DashboardCardId.currentYaml,
      DashboardCardId.quickSettings
    ]);
    expect(layout.isVisible(DashboardCardId.status), isFalse);
    layout.dispose();
  });

  test('old default order migrates while preserving hidden cards', () async {
    SharedPreferences.setMockInitialValues({
      DashboardLayoutStore.preferenceKey: jsonEncode({
        'version': 1,
        'order': [
          'status',
          'currentYaml',
          'operations',
          'quickSettings',
          'traffic',
          'overview'
        ],
        'hidden': ['traffic']
      })
    });
    final layout = DashboardLayoutStore();
    await layout.load();
    expect(layout.order, DashboardCardId.values);
    expect(layout.isVisible(DashboardCardId.traffic), isFalse);
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
