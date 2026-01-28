
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

// The "settings" box is already open from main.dart
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const String _themeKey = 'app_theme_mode';
  final _box = Hive.box('settings');

  @override
  ThemeMode build() {
    // Read the saved index immediately (Synchronous)
    final themeIndex = _box.get(_themeKey, defaultValue: ThemeMode.system.index);
    return ThemeMode.values[themeIndex];
  }

  void setTheme(ThemeMode mode) {
    state = mode;
    _box.put(_themeKey, mode.index);
  }

  void toggleTheme() {
    final nextMode = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    setTheme(nextMode);
  }
}

// Modern NotifierProvider
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(() {
  return ThemeModeNotifier();
});