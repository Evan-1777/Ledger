import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class PreferencesStore {
  ThemeMode readThemeMode();
  Future<void> writeThemeMode(ThemeMode mode);
  bool readHideAmounts();
  Future<void> writeHideAmounts(bool value);
}

class SharedPreferencesStore implements PreferencesStore {
  SharedPreferencesStore(this.preferences);

  static const _themeKey = 'ledger_theme';
  static const _hideKey = 'ledger_hide_amounts';

  final SharedPreferences preferences;

  @override
  ThemeMode readThemeMode() => switch (preferences.getString(_themeKey)) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  @override
  Future<void> writeThemeMode(ThemeMode mode) =>
      preferences.setString(_themeKey, mode.name);

  @override
  bool readHideAmounts() => preferences.getBool(_hideKey) ?? false;

  @override
  Future<void> writeHideAmounts(bool value) =>
      preferences.setBool(_hideKey, value);
}
