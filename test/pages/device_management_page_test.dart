import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/l10n/app_locale.dart';
import 'package:proxly/pages/device_management_page.dart';
import 'package:proxly/pages/settings_page.dart';
import 'package:proxly/services/connection_settings_store.dart';
import 'package:proxly/services/controller_connection_state.dart';
import 'package:proxly/theme/app_theme.dart';
import 'package:proxly/widgets/app_popup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('controller picker switches directly and confirms only deletions',
      (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const secureStorage = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final secrets = {'clash_token': 'original-token'};
    messenger.setMockMethodCallHandler(secureStorage, (call) async {
      final args = call.arguments as Map;
      final key = args['key'] as String;
      return switch (call.method) {
        'read' => secrets[key],
        'write' => secrets[key] = args['value'] as String,
        'delete' => secrets.remove(key),
        _ => null,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(secureStorage, null));
    SharedPreferences.setMockInitialValues({
      'app_language': 'en',
      'clash_host': 'router.local:9090',
    });
    final store = ConnectionSettingsStore.instance;
    await AppLocaleController.instance.load();
    await store.initializeProfiles();
    final first = store.activeDevice!;
    await tester.pumpWidget(
      AppLocaleScope(
        controller: AppLocaleController.instance,
        child: MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.35)),
            child: child!,
          ),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('settings_connection_card'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.byType(TextField)),
      findsNWidgets(6),
    );
    final switchButton = find.byKey(const ValueKey('settings_switch_device'));
    final switchControl = tester.widget<TextButton>(switchButton);
    expect(switchControl.style!.splashFactory, NoSplash.splashFactory);
    expect(switchControl.style!.overlayColor!.resolve({WidgetState.pressed}),
        Colors.transparent);
    expect(find.descendant(of: switchButton, matching: find.byType(Icon)),
        findsNothing);
    final picker = find.byType(DeviceManagementSheet);

    Finder row(String id) => find.byKey(ValueKey('device-row-$id'));
    Finder tile(String id) =>
        find.descendant(of: row(id), matching: find.byType(ListTile));

    Future<void> openPicker() async {
      await tester.tap(switchButton);
      await tester.pumpAndSettle();
      expect(picker, findsOneWidget);
      expect(find.text('Select controller'), findsOneWidget);
      expect(
        find.descendant(of: switchButton, matching: find.text('Switch')),
        findsOneWidget,
      );
      expect(tester.widget<TextButton>(switchButton).onPressed, isNull);
      expect(
        find.descendant(of: picker, matching: find.text('Add device')),
        findsOneWidget,
      );
    }

    await openPicker();
    expect(tester.widget<ListTile>(tile(first.id)).selected, isTrue);
    expect(
      find.descendant(
          of: row(first.id), matching: find.byIcon(Icons.check_rounded)),
      findsOneWidget,
    );
    await tester.tap(tile(first.id));
    await tester.pumpAndSettle();
    expect(picker, findsNothing);
    expect(find.byType(AppDialog), findsNothing);
    expect(store.activeDevice?.id, first.id);

    await openPicker();
    await tester.tap(find.text('Add device'));
    await tester.pumpAndSettle();
    final editor = find.byType(DeviceEditorPage);
    expect(
        ModalRoute.of(tester.element(editor)), isA<MaterialPageRoute<bool>>());
    expect(find.widgetWithIcon(IconButton, Icons.arrow_back), findsOneWidget);
    Finder field(String key) =>
        find.descendant(of: editor, matching: find.byKey(ValueKey(key)));
    await tester.enterText(field('controller_name_field'), 'Office');
    await tester.enterText(field('controller_address_field'), 'router.local');
    await tester.enterText(field('controller_port_field'), '9090');
    final secret = field('controller_secret_field');
    await tester.ensureVisible(secret);
    await tester.enterText(secret, 'office-token');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').hitTestable());
    await tester.pumpAndSettle();
    expect(store.activeDevice?.id, first.id);
    expect(find.text('Office'), findsOneWidget);
    expect(tester.widget<ListTile>(tile(first.id)).selected, isTrue);

    final firstRow = row(first.id);
    await tester.drag(firstRow, const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete').hitTestable(), findsNothing);
    expect(find.text('Rename').hitTestable(), findsNothing);
    expect(find.text('Edit').hitTestable(), findsNothing);

    final pending = Completer<void>();
    final action = store.runRemoteOperation(() => pending.future);
    final office = find.descendant(of: picker, matching: find.text('Office'));
    final list = find.descendant(of: picker, matching: find.byType(Scrollable));

    Future<void> showOffice() async {
      await tester.scrollUntilVisible(office, 56, scrollable: list);
      await tester.pumpAndSettle();
    }

    try {
      await tester.pump();
      expect(
        find.text('You can switch devices when the remote operation finishes.'),
        findsOneWidget,
      );
      await showOffice();
      await tester.tap(office);
      await tester.pump();
      expect(store.activeDevice?.id, first.id);
      expect(find.byType(AppDialog), findsNothing);
    } finally {
      pending.complete();
      await action;
    }
    await tester.pumpAndSettle();

    await showOffice();
    final officeTile =
        find.ancestor(of: office, matching: find.byType(ListTile));
    final tapPoint = tester.getCenter(officeTile);
    await tester.drag(officeTile, const Offset(-140, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete').hitTestable(), findsOneWidget);
    await tester.tapAt(tapPoint);
    await tester.pumpAndSettle();
    expect(picker, findsNothing);
    expect(find.byType(AppDialog), findsNothing);
    final current = store.activeDevice!;
    expect(current.name, 'Office');
    expect(find.text('Switched to Office'), findsOneWidget);
    final controllerName = find.descendant(
      of: card,
      matching: find.byKey(const ValueKey('controller_name_field')),
    );
    expect(tester.widget<TextField>(controllerName).controller?.text, 'Office');
    final connection = ControllerConnectionState.instance;
    connection.reportOffline(connection.observe());
    await tester.pump();
    expect(
      find.descendant(of: card, matching: find.text('Device offline')),
      findsOneWidget,
    );

    await openPicker();
    expect(tester.widget<ListTile>(tile(current.id)).selected, isTrue);
    await tester.drag(firstRow, const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsNothing);
    expect(await store.loadDevices(), hasLength(2));
    await tester.tap(find.text('Delete').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Delete device'), findsOneWidget);
    expect(find.text('Rename').hitTestable(), findsNothing);
    expect(find.text('Edit').hitTestable(), findsNothing);
    await tester.tap(find.text('Cancel').hitTestable());
    await tester.pumpAndSettle();
    expect(await store.loadDevices(), hasLength(2));
    await tester.drag(firstRow, const Offset(-240, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete').hitTestable());
    await tester.pumpAndSettle();
    expect(await store.loadDevices(), hasLength(1));
    expect(store.activeDevice?.id, current.id);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  },
      variant:
          TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));
}
