import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/app_secure_storage.dart';
import 'package:proxly/widgets/app_startup.dart';
import 'package:proxly/l10n/app_locale.dart';

void main() {
  testWidgets('startup retains a usable retry screen when Keychain is locked',
      (tester) async {
    var attempts = 0;
    final retry = Completer<bool>();
    await tester.pumpWidget(AppStartup(initialize: () async {
      attempts++;
      if (attempts == 1) throw const SecureStorageUnavailableException();
      return retry.future;
    }));
    await tester.pump();
    expect(find.text(tr('凭据暂时不可用，请解锁设备后重试。已保存的配置未被删除。')), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(attempts, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    retry.complete(true);
  });
}
