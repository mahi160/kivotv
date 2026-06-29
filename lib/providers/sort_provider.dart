import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether channels are sorted alphabetically (true) or in the order the
/// provider listed them in the playlist / M3U file (false).
///
/// Defaults to alphabetical. Persisted across launches.
class SortNotifier extends Notifier<bool> {
  static const _key = 'kivo_sort_alpha';

  @override
  bool build() {
    _load();
    return true; // default: alphabetical
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_key);
    if (saved != null && saved != state) state = saved;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, state);
  }
}

final sortAlphaProvider = NotifierProvider<SortNotifier, bool>(
  SortNotifier.new,
);
