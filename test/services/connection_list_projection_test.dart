import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/clash_service.dart';
import 'package:proxly/services/connection_list_projection.dart';

void main() {
  late ConnectionListProjection projection;
  late List<ConnectionEntry> connections;
  setUp(() {
    projection = ConnectionListProjection();
    connections = [
      _connection('a', 1, '192.168.1.2', upload: 30, download: 10),
      _connection('b', 2, '192.168.1.3', upload: 20, download: 30),
      _connection('c', 3, '192.168.1.2', upload: 10, download: 20),
    ];
  });

  for (final (sort, expected) in [
    ('time_desc', ['c', 'b', 'a']),
    ('time_asc', ['a', 'b', 'c']),
    ('down_desc', ['b', 'c', 'a']),
    ('up_desc', ['a', 'b', 'c']),
    ('down_speed_desc', ['a', 'c', 'b']),
    ('up_speed_desc', ['b', 'a', 'c']),
  ]) {
    test('$sort preserves ordering without mutating the shared snapshot', () {
      final result = projection.select(connections,
          sortBy: sort,
          uploadSpeeds: {'b': 30, 'a': 20},
          downloadSpeeds: {'a': 30, 'c': 20});
      expect(result.map((entry) => entry.id), expected);
      expect(connections.map((entry) => entry.id), ['a', 'b', 'c']);
      expect(() => result.clear(), throwsUnsupportedError);
    });
  }

  test('display-only rebuilds reuse the view even with unrelated speed changes',
      () {
    final first = projection.select(connections, sortBy: 'time_desc');
    final next = projection
        .select(connections, sortBy: 'time_desc', uploadSpeeds: {'a': 50});
    expect(next, same(first));
  });

  test('speed sorting invalidates only for its relevant speed map', () {
    final speeds = {'a': 30, 'b': 20, 'c': 10};
    final first = projection.select(connections,
        sortBy: 'up_speed_desc', uploadSpeeds: speeds);
    expect(
        projection.select(connections,
            sortBy: 'up_speed_desc',
            uploadSpeeds: speeds,
            downloadSpeeds: {'c': 100}),
        same(first));
    final updated = projection.select(connections,
        sortBy: 'up_speed_desc', uploadSpeeds: {'a': 10, 'b': 20, 'c': 30});
    expect(updated.map((entry) => entry.id), ['c', 'b', 'a']);
    expect(updated, isNot(same(first)));
  });

  test('filter and sort changes immediately replace the cached view', () {
    projection.select(connections, sortBy: 'time_desc');
    final filtered = projection.select(connections,
        sortBy: 'time_desc', sourceIp: '192.168.1.2');
    expect(filtered.map((entry) => entry.id), ['c', 'a']);
    expect(
        projection.select(connections,
            sortBy: 'time_desc', sourceIp: '192.168.1.2'),
        same(filtered));
    expect(
        projection
            .select(connections, sortBy: 'time_asc', sourceIp: '192.168.1.2')
            .map((entry) => entry.id),
        ['a', 'c']);
    expect(projection.select(connections, sortBy: 'time_asc'), hasLength(3));
    expect(
        projection.select(connections,
            sortBy: 'time_asc', sourceIp: '192.168.1.99'),
        isEmpty);
  });

  test('new snapshots and successful removals replace stale entries', () {
    final first = projection.select(connections, sortBy: 'down_desc');
    final replacement =
        _connection('a', 1, '192.168.1.2', upload: 30, download: 100);
    final next = projection
        .select([replacement, ...connections.skip(1)], sortBy: 'down_desc');
    expect(next.first, same(replacement));
    expect(first.first.id, 'b');
    final remaining = projection.select(
        next.where((entry) => entry.id != 'a').toList(),
        sortBy: 'down_desc');
    expect(remaining.map((entry) => entry.id), ['b', 'c']);
    expect(projection.select([], sortBy: 'down_desc'), isEmpty);
  });
}

ConnectionEntry _connection(String id, int minute, String sourceIp,
        {required int upload, required int download}) =>
    ConnectionEntry(
      id: id,
      sourceIp: sourceIp,
      sourcePort: '1234',
      host: '$id.example.com',
      sniffHost: '',
      destinationIp: '',
      destinationPort: '443',
      remoteDestination: '',
      network: 'tcp',
      type: '',
      chain: 'DIRECT',
      chainList: const ['DIRECT'],
      providerChains: const [],
      rule: '',
      inboundName: '',
      inboundIp: '',
      inboundPort: '',
      process: '',
      dnsMode: '',
      startTime: DateTime(2026, 1, 1, 0, minute),
      upload: upload,
      download: download,
      apiUpSpeed: 0,
      apiDownSpeed: 0,
    );
