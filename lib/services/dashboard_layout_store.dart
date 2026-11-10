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
  Set<DashboardCardId> _orderedCards = {};
  Future<void> _pendingWrite = Future.value();
  bool _disposed = false;
  int _revision = 0;

  List<DashboardCardId> get order => List.unmodifiable(_order);
  List<DashboardCardId> get visible => _order.where(isVisible).toList();
  bool isVisible(DashboardCardId id) => !_hidden.contains(id);

  List<DashboardCardId> availableOrder({
    Set<DashboardCardId> unavailable = const {},
  }) {
    final available = _order.where((id) => !unavailable.contains(id));
    if (_orderedCards.isEmpty) return available.toList();
    return [
      ...available.where(_orderedCards.contains),
      ...available.where((id) => !_orderedCards.contains(id)),
    ];
  }

  Future<void> load() async {
    final revision = _revision;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(preferenceKey);
    if (_disposed || revision != _revision || raw == null) return;
    try {
      final data = jsonDecode(raw);
      if (data is! Map || ![1, 2, 3].contains(data['version'])) return;
      final byName = {for (final id in DashboardCardId.values) id.name: id};
      final savedOrder = data['order'];
      final savedHidden = data['hidden'];
      if (savedOrder is! List || savedHidden is! List) return;
      if (data['version'] == 3 && data['ordered'] is! List) return;
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
      _orderedCards = {
        for (final name in data['version'] == 3
            ? data['ordered'] as List
            : listEquals(_order, DashboardCardId.values)
                ? const []
                : savedOrder)
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

  Future<void> reorder(
    int oldIndex,
    int newIndex, {
    Set<DashboardCardId> unavailable = const {},
  }) {
    final available = availableOrder(unavailable: unavailable);
    final id = available.removeAt(oldIndex);
    available.insert(newIndex, id);
    // Unavailable cards keep their saved slots for when support returns.
    var index = 0;
    for (var slot = 0; slot < _order.length; slot++) {
      if (!unavailable.contains(_order[slot])) {
        _order[slot] = available[index++];
      }
    }
    _orderedCards.addAll(available);
    return _save();
  }

  Future<void> reset() {
    _order = List.of(DashboardCardId.values);
    _hidden = {};
    _orderedCards = {};
    return _save();
  }

  Future<void> _save() {
    _revision++;
    notifyListeners();
    final snapshot = jsonEncode({
      'version': 3,
      'order': _order.map((id) => id.name).toList(),
      'hidden': _hidden.map((id) => id.name).toList(),
      'ordered': _orderedCards.map((id) => id.name).toList(),
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
