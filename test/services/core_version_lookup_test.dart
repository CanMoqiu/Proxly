import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/core_version_lookup.dart';

void main() {
  test('offline cold start recovers on connection without a settings change',
      () async {
    var online = false;
    var calls = 0;
    final lookup = CoreVersionLookup(load: () async {
      calls++;
      if (!online) throw StateError('offline');
      return 'v1.19.0';
    });
    await lookup.refresh();
    expect(lookup.value, '--');
    online = true;
    await lookup.refresh(force: true);
    expect(lookup.value, 'v1.19.0');
    await lookup.refresh();
    expect(calls, 2);
  });

  test('failed version requests retry with a cooldown while traffic is online',
      () async {
    var now = DateTime(2026);
    var calls = 0;
    final lookup = CoreVersionLookup(
        now: () => now,
        load: () async {
          if (++calls < 2) throw StateError('temporarily unavailable');
          return 'v1.19.1';
        });
    await lookup.refresh();
    for (var i = 0; i < 4; i++) {
      now = now.add(const Duration(seconds: 1));
      await lookup.refresh();
    }
    expect(calls, 1);
    now = now.add(const Duration(seconds: 1));
    await lookup.refresh();
    expect(lookup.value, 'v1.19.1');
  });

  test(
      'concurrent snapshots share a request and reconnect refreshes a known version',
      () async {
    var gate = Completer<String>();
    var calls = 0;
    final lookup = CoreVersionLookup(load: () {
      calls++;
      return gate.future;
    });
    final pending = lookup.refresh();
    final concurrent = lookup.refresh(force: true);
    expect(calls, 1);
    gate.complete('v1');
    await Future.wait([pending, concurrent]);
    gate = Completer<String>();
    final reconnected = lookup.refresh(force: true);
    gate.complete('v2');
    await reconnected;
    expect(lookup.value, 'v2');
    expect(calls, 2);
  });

  test(
      'late replies from the previous controller never replace the new version',
      () async {
    final old = Completer<String>();
    final current = Completer<String>();
    var calls = 0;
    final lookup = CoreVersionLookup(
      load: () => ++calls == 1 ? old.future : current.future,
    );
    final pendingOld = lookup.refresh();
    lookup.reset();
    final pendingCurrent = lookup.refresh();
    current.complete('new-controller');
    await pendingCurrent;
    old.complete('old-controller');
    await pendingOld;
    expect(lookup.value, 'new-controller');
  });

  test('synchronous errors and empty versions do not stop later retries',
      () async {
    var now = DateTime(2026);
    var calls = 0;
    final lookup = CoreVersionLookup(
        now: () => now,
        load: () {
          calls++;
          if (calls == 1) throw StateError('not configured');
          return Future.value(calls == 2 ? '  ' : 'v3');
        });
    for (var i = 0; i < 3; i++) {
      await lookup.refresh();
      now = now.add(const Duration(seconds: 5));
    }
    expect(lookup.value, 'v3');
    expect(calls, 3);
  });
}
