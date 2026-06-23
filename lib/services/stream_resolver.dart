import 'bdix_resolver.dart';
import 'iptvidn_resolver.dart';
import 'resolved_stream.dart';
import 'streamcrichd_resolver.dart';
import 'tflix_resolver.dart';

/// Routes a channel reference to the resolver that owns its scheme. Direct
/// (already-playable) URLs aren't resolvable and are played as-is.
class StreamResolver {
  StreamResolver._();

  static bool isResolvable(String reference) =>
      IptvidnResolver.isResolvable(reference) ||
      TflixResolver.isResolvable(reference) ||
      BdixtvResolver.isResolvable(reference) ||
      StreamcrichdResolver.isResolvable(reference);

  static Future<ResolvedStream> resolve(String reference) {
    if (TflixResolver.isResolvable(reference)) {
      return TflixResolver.instance.resolve(reference);
    }
    if (BdixtvResolver.isResolvable(reference)) {
      return BdixtvResolver.instance.resolve(reference);
    }
    if (StreamcrichdResolver.isResolvable(reference)) {
      return StreamcrichdResolver.instance.resolve(reference);
    }
    return IptvidnResolver.instance.resolve(reference);
  }
}
