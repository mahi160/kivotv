import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repository_provider.dart';

/// Runs the one-time app bootstrap (DB open, schema migration, seed data).
///
/// The root widget watches this provider and shows a splash/loading screen
/// until it resolves. Errors are surfaced to the user instead of swallowed
/// by a fire-and-forget catchError().
final bootstrapProvider = FutureProvider<void>((ref) async {
  await ref.watch(repositoryProvider).bootstrap();
});
