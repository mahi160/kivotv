import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'persisted_notifier.dart';

/// Whether channels are sorted alphabetically (true) or in the order the
/// provider listed them in the playlist / M3U file (false).
///
/// Defaults to alphabetical. Persisted across launches.
class SortNotifier extends PersistedNotifier<bool> {
  static const _key = 'kivo_sort_alpha';

  @override
  bool get initialValue => true;

  @override
  bool? readSaved(SharedPreferences prefs) => prefs.getBool(_key);

  @override
  Future<void> writeSaved(SharedPreferences prefs, bool value) =>
      prefs.setBool(_key, value);

  Future<void> toggle() => set(!state);
}

final sortAlphaProvider = NotifierProvider<SortNotifier, bool>(
  SortNotifier.new,
);
