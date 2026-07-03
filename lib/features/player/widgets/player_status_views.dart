import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Passive status widgets shown over the video surface: buffering spinner,
/// stream-error panel, and the auto-skip toast.

// ─────────────────────────────────────────────────────────────────────────────
//  Buffering indicator
// ─────────────────────────────────────────────────────────────────────────────

class BufferingIndicator extends StatelessWidget {
  const BufferingIndicator({super.key, required this.speedBytesPerSec});

  /// Live download speed in bytes/s. Listened to directly so speed updates
  /// repaint only the label, not the player screen.
  final ValueListenable<double> speedBytesPerSec;

  static String _label(double v) {
    if (v <= 0) return 'Buffering…';
    if (v < 1024 * 1024) return '${(v / 1024).toStringAsFixed(0)} KB/s';
    return '${(v / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            color: Colors.white70,
            strokeWidth: 2.5,
          ),
          const SizedBox(height: 14),
          ValueListenableBuilder<double>(
            valueListenable: speedBytesPerSec,
            builder: (_, speed, _) => Text(
              _label(speed),
              style: const TextStyle(
                fontFamily: 'Outfit',
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Stream error view
// ─────────────────────────────────────────────────────────────────────────────

class StreamErrorView extends StatelessWidget {
  const StreamErrorView({
    super.key,
    required this.channelName,
    required this.message,
  });

  final String channelName;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xCC000000),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.signal_wifi_off_rounded,
              size: 56,
              color: Colors.white54,
            ),
            const SizedBox(height: 16),
            Text(
              channelName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white60),
            ),
            const SizedBox(height: 20),
            Text(
              'Press OK to retry  ·  ▲ ▼ to change channel',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Auto-skip toast
// ─────────────────────────────────────────────────────────────────────────────

class AutoSkipToast extends StatelessWidget {
  const AutoSkipToast({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xE0111827),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.skip_next_rounded, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
          Text(
            message,
            style: const TextStyle(
              fontFamily: 'Outfit',
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
