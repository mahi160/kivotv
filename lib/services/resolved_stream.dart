/// A currently-playable stream URL produced by a resolver.
///
/// [expiresAt] is the moment a token in the URL expires (null when there's no
/// parseable expiry). [httpHeaders] are headers the player must send to fetch
/// the stream (e.g. a User-Agent some CDNs require); null when none are needed.
class ResolvedStream {
  const ResolvedStream({required this.url, this.expiresAt, this.httpHeaders});

  final String url;
  final DateTime? expiresAt;
  final Map<String, String>? httpHeaders;
}
