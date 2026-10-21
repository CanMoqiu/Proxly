import 'package:flutter/material.dart';

abstract final class DashboardButtonStyle {
  static const double minimumHeight = 48;
  static const double spacing = 8;
  static const double iconSize = 18;
  static const double cornerRadius = 12;
  static const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);

  static const action = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(48, minimumHeight)),
    padding: WidgetStatePropertyAll(padding),
    shape: WidgetStatePropertyAll(RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(cornerRadius)),
    )),
    textStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.padded,
  );

  static const icon = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size.square(minimumHeight)),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.padded,
  );
}
