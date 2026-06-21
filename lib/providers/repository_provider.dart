import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/playlist_repository.dart';

/// Single app-wide [PlaylistRepository]. Provided via Riverpod so it is
/// injectable in tests (override with an in-memory stub) and never accessed
/// via a hand-rolled singleton.
final repositoryProvider = Provider<PlaylistRepository>(
  (_) => PlaylistRepository(),
);
