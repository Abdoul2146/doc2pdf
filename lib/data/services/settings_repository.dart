import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted user preferences.
class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _kThemeMode = 'settings.theme_mode';
  static const _kKeepScreenOn = 'settings.keep_screen_on';
  static const _kColorMode = 'settings.color_mode';
  static const _kPageSize = 'settings.page_size';
  static const _kOrientation = 'settings.orientation';

  static SettingsRepository instance(SharedPreferences prefs) =>
      SettingsRepository(prefs);

  ThemeMode themeMode() {
    final value = _prefs.getString(_kThemeMode);
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      _prefs.setString(_kThemeMode, mode.name);

  bool keepScreenOn() => _prefs.getBool(_kKeepScreenOn) ?? true;

  Future<void> setKeepScreenOn(bool value) =>
      _prefs.setBool(_kKeepScreenOn, value);

  String? colorMode() => _prefs.getString(_kColorMode);

  Future<void> setColorMode(String value) =>
      _prefs.setString(_kColorMode, value);

  String? pageSize() => _prefs.getString(_kPageSize);

  Future<void> setPageSize(String value) => _prefs.setString(_kPageSize, value);

  String? orientation() => _prefs.getString(_kOrientation);

  Future<void> setOrientation(String value) =>
      _prefs.setString(_kOrientation, value);
}
