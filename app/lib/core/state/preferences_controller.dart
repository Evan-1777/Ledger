import 'package:flutter/material.dart';

import '../storage/preferences_store.dart';

class PreferencesController extends ChangeNotifier {
  PreferencesController(this._store)
    : themeMode = _store.readThemeMode(),
      hideAmounts = _store.readHideAmounts();

  final PreferencesStore _store;

  ThemeMode themeMode;
  bool hideAmounts;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (themeMode == mode) return;
    themeMode = mode;
    notifyListeners();
    await _store.writeThemeMode(mode);
  }

  Future<void> toggleHideAmounts() async {
    hideAmounts = !hideAmounts;
    notifyListeners();
    await _store.writeHideAmounts(hideAmounts);
  }
}
