import 'iptvidn_resolver.dart';
import 'resolved_stream.dart';
import 'streamcrichd_resolver.dart';
import 'tflix_resolver.dart';

/// Routes a channel reference to the resolver that owns its scheme. Direct
/// (already-playable) URLs aren't resolvable and are played as-is.
class StreamResolver {
  StreamResolver._();

  /// One entry per resolver. Adding a resolver means adding one line here —
  /// [isResolvable] and [resolve] both dispatch off this single table so they
  /// can never drift out of sync with each other.
  static final _resolvers = <({
    bool Function(String reference) isResolvable,
    Future<ResolvedStream> Function(String reference) resolve,
  })>[
    (
      isResolvable: TflixResolver.isResolvable,
      resolve: TflixResolver.instance.resolve,
    ),
    (
      isResolvable: StreamcrichdResolver.isResolvable,
      resolve: StreamcrichdResolver.instance.resolve,
    ),
    (
      isResolvable: IptvidnResolver.isResolvable,
      resolve: IptvidnResolver.instance.resolve,
    ),
  ];

  static bool isResolvable(String reference) =>
      _resolvers.any((r) => r.isResolvable(reference));

  /// Throws [StateError] if [reference] doesn't match any resolver — callers
  /// must guard with [isResolvable] first (as [PlaybackSession] does).
  static Future<ResolvedStream> resolve(String reference) {
    for (final r in _resolvers) {
      if (r.isResolvable(reference)) return r.resolve(reference);
    }
    throw StateError('No resolver for reference: $reference');
  }
}
