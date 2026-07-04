import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'persisted_notifier.dart';

/// User-tunable A/V sync offset in seconds, passed to mpv's `audio-delay`.
///
/// ponytail: fixed manual offset, not auto-detection. The lag comes from
/// downstream HDMI/soundbar audio processing that varies per TV setup and
/// isn't measurable from inside the app — a slider the user nudges until it
/// looks right is the whole fix. Negative delays video to catch up to audio
/// that arrives late (the common case with AV receivers).
class AudioDelayNotifier extends PersistedNotifier<double> {
  static const _key = 'kivo_audio_delay_secs';

  @override
  double get initialValue => 0;

  @override
  double? readSaved(SharedPreferences prefs) => prefs.getDouble(_key);

  @override
  Future<void> writeSaved(SharedPreferences prefs, double value) =>
      prefs.setDouble(_key, value);
}

final audioDelayProvider = NotifierProvider<AudioDelayNotifier, double>(
  AudioDelayNotifier.new,
);
