import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/services/hls_probe.dart';

// Minimal HTTP server spun up per test group.
HttpServer? _server;
int         _port = 0;

Future<void> _startServer(Future<void> Function(HttpRequest) handler) async {
  _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _port   = _server!.port;
  _server!.listen(handler);
}

Future<void> _stopServer() async {
  await _server?.close(force: true);
  _server = null;
}

void main() {
  group('isHlsManifest', () {
    tearDown(_stopServer);

    test('returns true for a valid #EXTM3U response', () async {
      await _startServer((req) async {
        req.response
          ..statusCode = HttpStatus.ok
          ..write('#EXTM3U\n#EXT-X-VERSION:3\n')
          ..close();
      });
      expect(await isHlsManifest('http://127.0.0.1:$_port/live.m3u8'), isTrue);
    });

    test('returns true when manifest has leading whitespace', () async {
      await _startServer((req) async {
        req.response
          ..statusCode = HttpStatus.ok
          ..write('   \n#EXTM3U\n')
          ..close();
      });
      expect(await isHlsManifest('http://127.0.0.1:$_port/live.m3u8'), isTrue);
    });

    test('returns false for a non-200 response', () async {
      await _startServer((req) async {
        req.response
          ..statusCode = HttpStatus.notFound
          ..close();
      });
      expect(await isHlsManifest('http://127.0.0.1:$_port/live.m3u8'), isFalse);
    });

    test('returns false for a 200 response that is not an HLS manifest', () async {
      await _startServer((req) async {
        req.response
          ..statusCode = HttpStatus.ok
          ..write('<html>Not a manifest</html>')
          ..close();
      });
      expect(await isHlsManifest('http://127.0.0.1:$_port/'), isFalse);
    });

    test('returns false for malformed UTF-8 bytes that are not #EXTM3U', () async {
      await _startServer((req) async {
        // Invalid UTF-8 sequence followed by unrelated content.
        req.response
          ..statusCode = HttpStatus.ok
          ..add([0xFF, 0xFE, 0x00, 0x01])
          ..close();
      });
      expect(await isHlsManifest('http://127.0.0.1:$_port/bad.m3u8'), isFalse);
    });

    test('returns true for a valid manifest sent as raw bytes (allowMalformed)', () async {
      await _startServer((req) async {
        // Prepend a valid manifest with a stray high byte to exercise
        // allowMalformed: the trimLeft + startsWith should still match.
        final bytes = [
          ...utf8.encode('#EXTM3U\n'),
          0xFF, // stray byte after the header line
        ];
        req.response
          ..statusCode = HttpStatus.ok
          ..add(bytes)
          ..close();
      });
      expect(await isHlsManifest('http://127.0.0.1:$_port/live.m3u8'), isTrue);
    });

    test('returns false when the server connection is refused', () async {
      // Port 1 is reserved and never listened on in tests.
      expect(await isHlsManifest('http://127.0.0.1:1/live.m3u8'), isFalse);
    });

    test('returns false on timeout', () async {
      await _startServer((req) async {
        // Never respond — triggers the timeout.
        await Future.delayed(const Duration(seconds: 10));
        req.response.close();
      });
      expect(
        await isHlsManifest(
          'http://127.0.0.1:$_port/slow.m3u8',
          timeout: const Duration(milliseconds: 100),
        ),
        isFalse,
      );
    });
  });
}
