import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'persisted_notifier.dart';

/// Persisted app theme mode.
///
/// Defaults to [ThemeMode.system] (follow the TV's light/dark setting). The
/// settings drawer's "Dark mode" toggle flips to an explicit [ThemeMode.dark]
/// or [ThemeMode.light], and the choice is remembered across launches via
/// shared_preferences.
class ThemeModeNotifier extends PersistedNotifier<ThemeMode> {
  static const _key = 'kivo_theme_mode';

  @override
  ThemeMode get initialValue => ThemeMode.system;

  @override
  ThemeMode? readSaved(SharedPreferences prefs) => switch (prefs.getString(_key)) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => null, // nothing saved yet — keep initialValue
  };

  @override
  Future<void> writeSaved(SharedPreferences prefs, ThemeMode value) =>
      prefs.setString(_key, value.name);

  /// Flips between explicit light and dark. [systemIsDark] resolves the current
  /// effective brightness when the mode is still [ThemeMode.system], so the
  /// first toggle moves to the opposite of what's on screen.
  Future<void> toggle({required bool systemIsDark}) {
    final effectiveDark = switch (state) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => systemIsDark,
    };
    return set(effectiveDark ? ThemeMode.light : ThemeMode.dark);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
