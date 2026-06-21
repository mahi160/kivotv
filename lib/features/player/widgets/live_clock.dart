import 'dart:async';

import 'package:flutter/material.dart';

/// Stateful HH:MM clock that refreshes every 30 seconds.
/// Shown in the top-right corner of the player overlay.
class LiveClock extends StatefulWidget {
  const LiveClock({super.key});

  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  late Timer    _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now   = DateTime.now();
    // Update every 30 s — precise enough for HH:MM display.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    return Text(
      '$h:$m',
      style: const TextStyle(
        fontFamily:    'Outfit',
        fontSize:      26,
        fontWeight:    FontWeight.w400,
        letterSpacing: 3,
        color:         Colors.white,
        fontFeatures:  [FontFeature.tabularFigures()],
        shadows:       [Shadow(blurRadius: 6)],
      ),
    );
  }
}
