import 'package:flutter/material.dart';

final ThemeData lightMode = (() {
  const colorScheme = ColorScheme.light(
    surface: Color.fromARGB(255, 229, 229, 234),
    primary: Color.fromARGB(255, 76, 145, 255),
    secondary: Color.fromARGB(255, 220, 220, 221),
    tertiary: Color.fromARGB(255, 184, 184, 184),
    tertiaryContainer: Color.fromARGB(255, 66, 66, 66),
    inversePrimary: Color.fromARGB(255, 33, 33, 33),
  );

  return ThemeData(
    brightness: Brightness.light,
    colorScheme: colorScheme,
    textTheme: Typography.blackCupertino,
    inputDecorationTheme: _inputDecorationTheme(colorScheme),

    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: colorScheme.surface,
    ),
    scaffoldBackgroundColor: colorScheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.secondary,
      elevation: 0,
    ),
  );
})();

InputDecorationTheme _inputDecorationTheme(ColorScheme colorScheme) {
  return InputDecorationTheme(
    filled: true,
    fillColor: colorScheme.secondary,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colorScheme.secondary, width: 2),
    ),

    hintStyle: TextStyle(color: colorScheme.tertiary),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colorScheme.secondary, width: 2),
    ),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );
}
