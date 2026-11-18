import 'package:flutter/material.dart';

abstract final class TvColors {
  static const black = Color(0xFF000000);
  static const panel = Color(0xE6141925);
  static const panelStrong = Color(0xF5111622);
  static const blue = Color(0xFF0099FF);
  static const cyan = Color(0xFF4CC3FF);
}

ThemeData buildTvTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: TvColors.black,
    colorScheme: const ColorScheme.dark(
      primary: TvColors.blue,
      secondary: TvColors.cyan,
      surface: Color(0xFF111722),
    ),
    visualDensity: VisualDensity.standard,
    useMaterial3: true,
    fontFamily: 'Roboto',
  );
}
