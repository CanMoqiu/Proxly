import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/tablet_layout.dart';

void main() {
  test('display classification is stable across tablet rotation', () {
    expect(TabletLayout.isTabletDisplay(const Size(1536, 2048), 2), isTrue);
    expect(TabletLayout.isTabletDisplay(const Size(2048, 1536), 2), isTrue);
    expect(TabletLayout.isTabletDisplay(const Size(1600, 2560), 2), isTrue);
    expect(TabletLayout.isTabletDisplay(const Size(1200, 1920), 2), isTrue);
    expect(TabletLayout.isTabletDisplay(const Size(1170, 2532), 3), isFalse);
    expect(TabletLayout.isTabletDisplay(const Size(2532, 1170), 3), isFalse);
    expect(TabletLayout.isTabletDisplay(Size.zero, 1), isFalse);
  });

  test('tablets rotate while phones retain portrait', () {
    expect(TabletLayout.orientations(false), [DeviceOrientation.portraitUp]);
    expect(TabletLayout.orientations(true), containsAll(DeviceOrientation.values));
  });
}
