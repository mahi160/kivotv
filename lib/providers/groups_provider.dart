import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/channel_group.dart';
import '../services/playlist_repository.dart';

/// All non-broken channel groups, sorted alphabetically.
/// Auto-refreshes when the dashboard version changes (new channels added etc.).
final groupsProvider =
    FutureProvider.autoDispose<List<ChannelGroup>>((ref) async {
  return PlaylistRepository.instance.groups();
});
