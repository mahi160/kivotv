/// Swallows duplicate BACK events.
///
/// Some TV firmware (TCL/Realtek) delivers KEYCODE_BACK through both the
/// key-event pipeline and the Activity's onBackPressed() independently, so a
/// single physical press can arrive twice a few ms apart — the second copy
/// possibly landing on a different screen after the first navigated away.
///
/// Usage: call [arm] when a back action fires (or a screen mounts); while
/// [swallow] is true, ignore further back events as echoes.
class BackGuard {
  BackGuard({this.window = const Duration(milliseconds: 600)});

  final Duration window;
  DateTime? _armedAt;

  void arm() => _armedAt = DateTime.now();

  /// True while a recent [arm] means the current event is likely the echo.
  bool get swallow {
    final armedAt = _armedAt;
    return armedAt != null && DateTime.now().difference(armedAt) < window;
  }
}
