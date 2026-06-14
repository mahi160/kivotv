import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeKey = 'kivo_theme_mode';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _values = {
    'light':  ThemeMode.light,
    'dark':   ThemeMode.dark,
    'system': ThemeMode.system,
  };

  @override
  ThemeMode build() => ThemeMode.system; // default until prefs load

  /// Call once at app start to hydrate from disk.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_kThemeKey);
    if (raw != null) state = _values[raw] ?? ThemeMode.system;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kThemeKey,
      _values.entries.firstWhere((e) => e.value == mode).key,
    );
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
