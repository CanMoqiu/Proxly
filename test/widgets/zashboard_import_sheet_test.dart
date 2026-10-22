import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/widgets/zashboard_import_sheet.dart';
import 'package:proxly/widgets/app_popup.dart';

void main() {
  testWidgets('import menu returns the chosen core or file source',
      (tester) async {
    for (final source in ZashboardImportSource.values) {
      ZashboardImportSource? chosen;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => TextButton(
                  onPressed: () async {
                    chosen = await AppPopup.sheet<ZashboardImportSource>(
                        context: context,
                        builder: (_) => const ZashboardImportSheet());
                  },
                  child: const Text('Open')))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final tiles = find.byType(ListTile);
      expect(tiles, findsNWidgets(2));
      await tester.tap(tiles.at(source.index));
      await tester.pumpAndSettle();
      expect(chosen, source);
    }
  });
}
