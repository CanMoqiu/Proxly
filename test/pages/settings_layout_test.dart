import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('connection settings appear before appearance settings',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pump();

    final connectionCard =
        find.byKey(const ValueKey('settings_connection_card'));
    final themeCard = find.byKey(const ValueKey('settings_theme_card'));
    expect(connectionCard, findsOneWidget);
    expect(themeCard, findsOneWidget);
    expect(
      tester.getTopLeft(connectionCard).dy,
      lessThan(tester.getTopLeft(themeCard).dy),
    );
  });

  testWidgets(
      'settings scroll padding stays compact on short safe-area screens',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await AppLocaleController.instance.load();
    tester.view.physicalSize = const Size(360, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewPadding: const EdgeInsets.only(bottom: 18),
            ),
            child: child!,
          ),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pump();

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scrollView.padding, const EdgeInsets.fromLTRB(16, 24, 16, 42));
    expect((scrollView.padding! as EdgeInsets).bottom, lessThan(80));
  });
}
