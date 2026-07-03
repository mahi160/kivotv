import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-tunable A/V sync offset in seconds, passed to mpv's `audio-delay`.
///
/// ponytail: fixed manual offset, not auto-detection. The lag comes from
/// downstream HDMI/soundbar audio processing that varies per TV setup and
/// isn't measurable from inside the app — a slider the user nudges until it
/// looks right is the whole fix. Negative delays video to catch up to audio
/// that arrives late (the common case with AV receivers).
class AudioDelayNotifier extends Notifier<double> {
  static const _key = 'kivo_audio_delay_secs';

  @override
  double build() {
    _load();
    return 0;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_key);
    if (saved != null && saved != state) state = saved;
  }

  Future<void> set(double seconds) async {
    state = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key, seconds);
  }
}

final audioDelayProvider = NotifierProvider<AudioDelayNotifier, double>(
  AudioDelayNotifier.new,
);
