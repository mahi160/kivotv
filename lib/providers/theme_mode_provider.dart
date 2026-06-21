import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted app theme mode.
///
/// Defaults to [ThemeMode.system] (follow the TV's light/dark setting). The
/// settings drawer's "Dark mode" toggle flips to an explicit [ThemeMode.dark]
/// or [ThemeMode.light], and the choice is remembered across launches via
/// shared_preferences.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _prefsKey = 'kivo_theme_mode';

  @override
  ThemeMode build() {
    // Start from system; load the saved preference asynchronously.
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    final mode = switch (saved) {
      'light' => ThemeMode.light,
      'dark'  => ThemeMode.dark,
      _       => ThemeMode.system,
    };
    if (mode != state) state = mode;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }

  /// Flips between explicit light and dark. [systemIsDark] resolves the current
  /// effective brightness when the mode is still [ThemeMode.system], so the
  /// first toggle moves to the opposite of what's on screen.
  Future<void> toggle({required bool systemIsDark}) {
    final effectiveDark = switch (state) {
      ThemeMode.dark   => true,
      ThemeMode.light  => false,
      ThemeMode.system => systemIsDark,
    };
    return set(effectiveDark ? ThemeMode.light : ThemeMode.dark);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
