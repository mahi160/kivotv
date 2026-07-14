import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notifier_stream.dart';
import 'repository_provider.dart';

/// Bridges [PlaylistRepository.isFetching] ValueNotifier → Riverpod stream.
/// True while a background playlist download is in progress.
final isFetchingProvider = StreamProvider<bool>(
  (ref) => valueNotifierStream(ref, ref.watch(repositoryProvider).isFetching),
);
