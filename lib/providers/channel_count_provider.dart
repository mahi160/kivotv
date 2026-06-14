import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/playlist_repository.dart';

/// Bridges [PlaylistRepository.channelCount] ValueNotifier to Riverpod.
///
/// Widgets watch this to reactively display the total channel count
/// without a [ValueListenableBuilder] boilerplate.
final channelCountProvider = StreamProvider<int>((ref) {
  final notifier = PlaylistRepository.instance.channelCount;
  final ctrl = StreamController<int>.broadcast();
  ctrl.add(notifier.value);

  void listener() => ctrl.add(notifier.value);
  notifier.addListener(listener);
  ref.onDispose(() {
    notifier.removeListener(listener);
    ctrl.close();
  });

  return ctrl.stream;
});
