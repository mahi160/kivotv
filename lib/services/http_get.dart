import 'dart:convert';
import 'dart:io';

/// Performs a GET request using [client], decodes the response body as UTF-8,
/// and returns the full body string.
///
/// [connectTimeout] guards the response-header phase (TCP + server latency).
/// [bodyTimeout] guards the body-streaming phase independently so a stalled
/// download does not block the [connectTimeout] budget.
///
/// Throws [HttpException] unless the status code is 200, or is in
/// [extraOkStatuses] (some endpoints return a non-200 status while still
/// serving the HTML we need to scrape — see [StreamcrichdResolver]).
Future<String> httpGetString(
  HttpClient client,
  Uri url, {
  String? referer,
  String userAgent = 'Mozilla/5.0',
  Duration connectTimeout = const Duration(seconds: 15),
  Duration bodyTimeout = const Duration(seconds: 15),
  Set<int> extraOkStatuses = const {},
}) async {
  final req = await client.getUrl(url);
  req.headers.set(HttpHeaders.userAgentHeader, userAgent);
  if (referer != null) req.headers.set(HttpHeaders.refererHeader, referer);
  final resp = await req.close().timeout(connectTimeout);
  if (resp.statusCode != HttpStatus.ok &&
      !extraOkStatuses.contains(resp.statusCode)) {
    throw HttpException('HTTP ${resp.statusCode}', uri: url);
  }
  return resp.transform(utf8.decoder).join().timeout(bodyTimeout);
}
