import 'package:flutter/material.dart';

final ThemeData darkMode = (() {
  const colorScheme = ColorScheme.dark(
    surface: Color.fromARGB(255, 23, 23, 23),
    primary: Color.fromARGB(255, 28, 100, 218),
    secondary: Color.fromARGB(255, 30, 30, 31),
    tertiary:  Color.fromARGB(255, 66, 66, 66),
    tertiaryContainer: Color.fromARGB(255, 117, 117, 117),
    inversePrimary: Colors.white60,
  );

  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    inputDecorationTheme: _inputDecorationTheme(colorScheme),
    scaffoldBackgroundColor: colorScheme.surface,
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: colorScheme.surface,
    ),
    snackBarTheme: SnackBarThemeData(backgroundColor: colorScheme.primary,),
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.secondary,
      elevation: 0,
    ),
    bottomAppBarTheme: BottomAppBarTheme(color: colorScheme.secondary),

    textTheme: Typography.whiteCupertino,
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
