import 'iptvidn_resolver.dart';
import 'resolved_stream.dart';
import 'tflix_resolver.dart';

/// Routes a channel reference to the resolver that owns its scheme. Direct
/// (already-playable) URLs aren't resolvable and are played as-is.
class StreamResolver {
  StreamResolver._();

  static bool isResolvable(String reference) =>
      IptvidnResolver.isResolvable(reference) ||
      TflixResolver.isResolvable(reference);

  static Future<ResolvedStream> resolve(String reference) {
    if (TflixResolver.isResolvable(reference)) {
      return TflixResolver.instance.resolve(reference);
    }
    return IptvidnResolver.instance.resolve(reference);
  }
}
