import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DashboardCardId {
  status,
  traffic,
  overview,
  currentYaml,
  operations,
  quickSettings,
}

class DashboardLayoutStore extends ChangeNotifier {
  static const preferenceKey = 'dashboard_layout_v1';
  List<DashboardCardId> _order = List.of(DashboardCardId.values);
  Set<DashboardCardId> _hidden = {};
  Future<void> _pendingWrite = Future.value();
  bool _disposed = false;
  int _revision = 0;

  List<DashboardCardId> get order => List.unmodifiable(_order);
  List<DashboardCardId> get visible => _order.where(isVisible).toList();
  bool isVisible(DashboardCardId id) => !_hidden.contains(id);

  Future<void> load() async {
    final revision = _revision;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(preferenceKey);
    if (_disposed || revision != _revision || raw == null) return;
    try {
      final data = jsonDecode(raw);
      if (data is! Map || ![1, 2].contains(data['version'])) return;
      final byName = {for (final id in DashboardCardId.values) id.name: id};
      final savedOrder = data['order'];
      final savedHidden = data['hidden'];
      if (savedOrder is! List || savedHidden is! List) return;
      _order = <DashboardCardId>{
        for (final name in savedOrder)
          if (byName[name] != null) byName[name]!,
        ...DashboardCardId.values,
      }.toList();
      // Migrate the old default without discarding a customized order or visibility.
      if (data['version'] == 1 &&
          listEquals(_order, const [
            DashboardCardId.status,
            DashboardCardId.currentYaml,
            DashboardCardId.operations,
            DashboardCardId.quickSettings,
            DashboardCardId.traffic,
            DashboardCardId.overview,
          ])) {
        _order = List.of(DashboardCardId.values);
      }
      _hidden = {
        for (final name in savedHidden)
          if (byName[name] != null) byName[name]!
      };
      notifyListeners();
    } on FormatException {
      // A damaged layout must not hide access to the dashboard controls.
    }
  }

  Future<void> setVisible(DashboardCardId id, bool visible) {
    if (visible) {
      _hidden.remove(id);
    } else {
      _hidden.add(id);
    }
    return _save();
  }

  Future<void> reorder(int oldIndex, int newIndex) {
    final id = _order.removeAt(oldIndex);
    _order.insert(newIndex, id);
    return _save();
  }

  Future<void> reset() {
    _order = List.of(DashboardCardId.values);
    _hidden = {};
    return _save();
  }

  Future<void> _save() {
    _revision++;
    notifyListeners();
    final snapshot = jsonEncode({
      'version': 2,
      'order': _order.map((id) => id.name).toList(),
      'hidden': _hidden.map((id) => id.name).toList(),
    });
    // Serialize snapshots so a slower earlier write cannot undo a later drag.
    final write = _pendingWrite.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(preferenceKey, snapshot)) {
        throw StateError('Dashboard layout was not saved');
      }
    });
    _pendingWrite = write.catchError((Object _) {});
    return write;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
