import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/native_connections_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'native connections error state stays retryable without pull refresh',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
    await AppLocaleController.instance.load();

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: const MaterialApp(home: NativeConnectionsPage()),
      ),
    );
    await tester.pump();

    expect(find.text('请先在设置页填写 Clash 地址'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'AdaptivePullRefresh',
      ),
      findsNothing,
    );
    expect(find.byType(RefreshIndicator), findsNothing);

    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.physics, isA<ClampingScrollPhysics>());
  });
}
