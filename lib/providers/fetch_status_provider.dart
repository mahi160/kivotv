import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/playlist_repository.dart';

/// Bridges [PlaylistRepository.isFetching] ValueNotifier → Riverpod stream.
/// True while a background playlist download is in progress.
final isFetchingProvider = StreamProvider<bool>((ref) {
  final notifier = PlaylistRepository.instance.isFetching;
  final ctrl = StreamController<bool>.broadcast();
  ctrl.add(notifier.value);

  void listener() => ctrl.add(notifier.value);
  notifier.addListener(listener);
  ref.onDispose(() {
    notifier.removeListener(listener);
    ctrl.close();
  });

  return ctrl.stream;
});
