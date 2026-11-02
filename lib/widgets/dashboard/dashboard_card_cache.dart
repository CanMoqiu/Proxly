import 'package:flutter/widgets.dart';

/// Keeps unchanged card widgets out of unrelated dashboard rebuilds.
/// Include inherited values used while constructing the card in the key.
class DashboardCardCache {
  Object? _key;
  Widget? _widget;

  Widget resolve(Object key, Widget Function() build) {
    if (_widget == null || key != _key) {
      _widget = build();
      _key = key;
    }
    return _widget!;
  }
}
