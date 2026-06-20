import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/playlist_repository.dart';
import 'notifier_stream.dart';

/// Bridges [PlaylistRepository.isFetching] ValueNotifier → Riverpod stream.
/// True while a background playlist download is in progress.
final isFetchingProvider = StreamProvider<bool>(
  (ref) => valueNotifierStream(ref, PlaylistRepository.instance.isFetching),
);
