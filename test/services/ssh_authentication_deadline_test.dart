import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/ssh_authentication_deadline.dart';

void main() {
  test('waiting for fingerprint approval does not spend authentication time',
      () async {
    final deadline =
        SshAuthenticationDeadline(const Duration(milliseconds: 30));
    final authenticated = Completer<void>();
    final waiting = deadline.waitFor(authenticated.future);
    final accepted = await deadline.verify(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      return true;
    });
    expect(accepted, isTrue);
    authenticated.complete();
    await waiting;
  });

  test('network authentication still times out after approval', () async {
    final deadline =
        SshAuthenticationDeadline(const Duration(milliseconds: 30));
    final waiting = deadline.waitFor(Completer<void>().future);
    final assertion = expectLater(waiting, throwsA(isA<TimeoutException>()));
    await deadline.verify(() async => true);
    await assertion;
  });
}
