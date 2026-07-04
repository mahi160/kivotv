import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Base for a [Notifier] whose state is one value persisted via
/// SharedPreferences: starts from [initialValue], asynchronously loads the
/// saved value once prefs resolve, and writes through on every [set].
///
/// Subclasses implement only how their one value is read from / written to
/// prefs — see [SortNotifier], [AudioDelayNotifier], [ThemeModeNotifier].
abstract class PersistedNotifier<T> extends Notifier<T> {
  T get initialValue;

  /// Null when nothing has been saved yet.
  T? readSaved(SharedPreferences prefs);
  Future<void> writeSaved(SharedPreferences prefs, T value);

  @override
  T build() {
    _load();
    return initialValue;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = readSaved(prefs);
    if (saved != null && saved != state) state = saved;
  }

  Future<void> set(T value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await writeSaved(prefs, value);
  }
}
