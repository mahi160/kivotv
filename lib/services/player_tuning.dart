/// libmpv tuning + NativePlayer property helpers for live IPTV on low-end
/// Android TV boxes (Amlogic/Mali, 1 GB RAM, 4K panels).
///
/// Every function here is best-effort: it silently no-ops on platforms
/// without a [NativePlayer] backend and swallows property errors — playback
/// still works with mpv defaults.
library;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// One-time property setup after the [Player] is created.
Future<void> configurePlayerForLiveTv(Player player) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  try {
    // ── HW decode ─────────────────────────────────────────────────────────
    // mediacodec (no -copy): HW decode via MediaCodec → SurfaceTexture →
    // OpenGL. Avoids the Amlogic/Mali gralloc unlock bug with
    // mediacodec-copy/auto-safe.
    await platform.setProperty('hwdec', 'mediacodec');
    await platform.setProperty('hwdec-codecs', 'all');
    // vd-lavc-dr: direct rendering — decoder writes directly into the GPU
    // buffer, eliminating one CPU→GPU copy per frame. Critical for 4K where
    // that copy alone can cause choppiness on the Amlogic SoC.
    await platform.setProperty('vd-lavc-dr', 'yes');
    await platform.setProperty('vd-lavc-fast', 'yes');
    await platform.setProperty('vd-lavc-threads', '0');
    // Skip the in-loop deblocking filter on non-reference frames. Only
    // matters when the software decoder kicks in (HW-unsupported codec /
    // profile), where it frees 20–30 % CPU at 4K for a visually negligible
    // cost at TV viewing distance.
    await platform.setProperty('vd-lavc-skiploopfilter', 'nonref');

    // ── A/V sync + frame drop ─────────────────────────────────────────────
    await platform.setProperty('video-sync', 'audio');
    // decoder+vo: drop at both stages. VO-only can let the decoder pipeline
    // back up under 4K load; decoder drops give it headroom earlier.
    await platform.setProperty('framedrop', 'decoder+vo');

    // ── Scaling / filtering (CPU+GPU cost not justified for IPTV) ─────────
    await platform.setProperty('scale', 'bilinear');
    await platform.setProperty('cscale', 'bilinear');
    await platform.setProperty('dscale', 'bilinear');
    await platform.setProperty('sigmoid-upscaling', 'no');
    await platform.setProperty('correct-downscaling', 'no');
    await platform.setProperty('linear-downscaling', 'no');
    await platform.setProperty('dither-depth', 'no');
    await platform.setProperty('hdr-compute-peak', 'no');
    // Debanding is a full-screen GPU pass — unaffordable at 4K on Mali.
    await platform.setProperty('deband', 'no');

    // ── Live buffer (short = less drift, faster start) ────────────────────
    await platform.setProperty('cache', 'yes');
    // 2 s readahead: enough for one HLS segment, small enough that live
    // drift stays under ~3 s between sync corrections.
    await platform.setProperty('demuxer-readahead-secs', '2');
    await platform.setProperty('cache-secs', '2');
    // Don't wait for the cache to fill before starting — begin playing
    // immediately with what's available. Crucial on slow networks.
    await platform.setProperty('demuxer-cache-wait', 'no');
    // Play through cache underruns instead of pausing. On live IPTV a
    // brief stutter is better than a multi-second freeze.
    await platform.setProperty('cache-pause', 'no');

    // ── Memory bounds (1 GB boxes) ────────────────────────────────────────
    // Cap demuxer buffers so a fast CDN can't balloon RAM and wake the
    // Android low-memory killer mid-stream (which reads as a "freeze").
    await platform.setProperty('demuxer-max-bytes', '${32 * 1024 * 1024}');
    await platform.setProperty('demuxer-max-back-bytes', '${4 * 1024 * 1024}');
  } catch (_) {
    // Tuning is non-critical; playback still works with mpv defaults.
  }
}

/// Streams the demuxer download speed (bytes/s) into [speed], EMA-smoothed
/// (α = 0.25: slow enough to read, fast enough to track real changes).
/// Writes to the notifier directly so only its listeners rebuild — never the
/// whole player screen.
Future<void> observeCacheSpeed(
  Player player,
  ValueNotifier<double> speed,
) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  try {
    await platform.observeProperty('cache-speed', (String val) async {
      final raw = double.tryParse(val) ?? 0;
      speed.value = speed.value * 0.75 + raw * 0.25;
    });
  } catch (_) {}
}

/// ClearKey DRM: pass kid→key pairs as mpv's decryption-keys option so libmpv
/// can decrypt CENC DASH segments. Format: kid/key:kid/key...
Future<void> applyClearKeys(
  Player player,
  Map<String, String> clearKeys,
) async {
  final platform = player.platform;
  if (platform is! NativePlayer || clearKeys.isEmpty) return;
  final keyStr =
      clearKeys.entries.map((e) => '${e.key}/${e.value}').join(':');
  try {
    await platform.setProperty('decryption-keys', keyStr);
  } catch (_) {
    // mpv build doesn't support this option — ignore and try anyway.
  }
}

/// User-initiated live-edge snap. Reads the demuxer cache end position and
/// seeks there. Causes a brief re-buffer but the user explicitly asked for it.
Future<void> snapToLiveEdge(Player player) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  try {
    final end =
        double.tryParse(await platform.getProperty('demuxer-cache-end')) ?? 0;
    if (end > 0) {
      await platform.setProperty('time-pos', (end - 0.3).toStringAsFixed(3));
    }
  } catch (_) {}
}
