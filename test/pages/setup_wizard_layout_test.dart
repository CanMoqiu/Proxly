import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/setup_wizard_page.dart';
import 'package:proxly/theme/app_theme.dart';
import 'package:proxly/widgets/adaptive_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('English setup preferences scroll without scaling the page',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppLocaleController.instance.setLanguage(AppLanguage.english);
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await AppLocaleController.instance.setLanguage(AppLanguage.english);
    });

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.2),
            ),
            child: child!,
          ),
          home: const SetupWizardPage(),
        ),
      ),
    );

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '192.168.1.1:9090');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Preferences'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('setup_preferences_scroll')),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('Preferences'),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );
    expect(find.byType(ThemeModeSelector), findsOneWidget);
    expect(
      find.byKey(const ValueKey('theme_mode_system_switch')),
      findsOneWidget,
    );
    final zashboardOption = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text('Zashboard panel'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final decoration = zashboardOption.decoration! as BoxDecoration;
    expect(decoration.border!.top.color, AppTheme.lightPrimary);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short screens keep setup typography at its intended size',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppLocaleController.instance.setLanguage(AppLanguage.english);
    tester.view.physicalSize = const Size(360, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await AppLocaleController.instance.setLanguage(AppLanguage.english);
    });

    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SetupWizardPage(),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('setup_welcome_scroll')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Welcome to Proxly'),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('setup_config_scroll')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Connection settings'),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );

    await tester.enterText(
      find.byType(TextField).first,
      '192.168.1.1:9090',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('setup_preferences_scroll')),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('Preferences'),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
