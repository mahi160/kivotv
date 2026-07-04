import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Purges both the in-memory Flutter image cache and the flutter_cache_manager
/// disk cache so stale channel logos load fresh after a playlist refresh.
///
/// UI-layer concern — lives in core/widgets territory, not the data layer, so
/// [PlaylistRepository] can stay free of Flutter painting imports.
Future<void> clearImageCache() async {
  // In-memory: Flutter's own painting cache (holds decoded bitmaps).
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
  // Disk: flutter_cache_manager's HTTP cache (stores raw network bytes).
  await DefaultCacheManager().emptyCache();
}
