import 'dart:async';

import 'package:flutter/foundation.dart';

/// Tracks live-stream drift and play duration for the currently open stream.
///
/// Drift = wall-clock elapsed − player-position elapsed since first healthy
/// play. It captures time lost to buffering/stalling and resets on channel
/// switch.
///
/// A [ChangeNotifier] ticking once per second so only its listeners (the
/// overlay's stream-info row) rebuild — never the whole player screen. The
/// tick also drives the "playing for X" clock, so that keeps updating even
/// before the drift reference is anchored.
class DriftTracker extends ChangeNotifier {
  Timer? _ticker;
  DateTime? _wallRef; // wall time when playing first became true
  Duration? _posRef; // player position at that moment
  DateTime? _streamOpenedAt;
  double _driftSec = 0;
  Duration Function()? _position;

  /// Seconds behind live, clamped to 0–999. 0 until anchored.
  double get driftSec => _driftSec;

  /// Wall time when the current stream opened (for "playing for X" display).
  DateTime? get streamOpenedAt => _streamOpenedAt;

  /// Call when a stream is opened. [position] reads the player's current
  /// playback position each tick.
  void start(Duration Function() position) {
    _position = position;
    _streamOpenedAt = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    notifyListeners();
  }

  /// Anchor the drift reference on the first healthy play of this stream.
  /// Subsequent calls are no-ops until [reset].
  void anchor(Duration position) {
    if (_wallRef != null) return;
    _wallRef = DateTime.now();
    _posRef = position;
  }

  /// Clear all state (channel switch / reload).
  void reset() {
    _ticker?.cancel();
    _ticker = null;
    _wallRef = null;
    _posRef = null;
    _streamOpenedAt = null;
    _driftSec = 0;
    notifyListeners();
  }

  void _tick() {
    final wRef = _wallRef;
    final pRef = _posRef;
    final position = _position;
    if (wRef != null && pRef != null && position != null) {
      final wallMs = DateTime.now().difference(wRef).inMilliseconds;
      final posMs = (position() - pRef).inMilliseconds;
      _driftSec = ((wallMs - posMs) / 1000.0).clamp(0, 999).toDouble();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
