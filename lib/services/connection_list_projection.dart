import 'dart:collection';

import 'clash_service.dart';

/// Reuses a sorted view across display-only rebuilds of a connection snapshot.
/// Callers must replace the source list and speed maps when their values change.
class ConnectionListProjection {
  (List<ConnectionEntry>, String, String, Map<String, int>?)? _key;
  List<ConnectionEntry> _result = const [];

  List<ConnectionEntry> select(
    List<ConnectionEntry> connections, {
    required String sortBy,
    String sourceIp = '',
    Map<String, int> uploadSpeeds = const {},
    Map<String, int> downloadSpeeds = const {},
  }) {
    final speeds = switch (sortBy) {
      'up_speed_desc' => uploadSpeeds,
      'down_speed_desc' => downloadSpeeds,
      _ => null,
    };
    final key = (connections, sortBy, sourceIp, speeds);
    if (key == _key) return _result;

    final list = sourceIp.isEmpty
        ? List<ConnectionEntry>.of(connections)
        : connections.where((entry) => entry.sourceIp == sourceIp).toList();
    switch (sortBy) {
      case 'time_asc':
        list.sort((a, b) => a.startTime.compareTo(b.startTime));
      case 'down_desc':
        list.sort((a, b) => b.download.compareTo(a.download));
      case 'up_desc':
        list.sort((a, b) => b.upload.compareTo(a.upload));
      case 'down_speed_desc':
      case 'up_speed_desc':
        list.sort((a, b) => (speeds![b.id] ?? 0).compareTo(speeds[a.id] ?? 0));
      default:
        list.sort((a, b) => b.startTime.compareTo(a.startTime));
    }
    _key = key;
    _result = UnmodifiableListView(list);
    return _result;
  }
}
