import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../hook/src/download.dart';

void main() {
  const libraryPath = 'lib/libpdfium.dylib';
  final library = utf8.encode('test native library');
  final tar = Archive()..addFile(ArchiveFile.bytes(libraryPath, library));
  final bytes = GZipEncoder().encode(TarEncoder().encode(tar));
  final artifact = PdfiumArchive.fromJson({
    'url': 'https://github.com/example/pdfium.tgz',
    'api_url': 'https://api.github.com/repos/example/releases/assets/123',
    'sha256': sha256.convert(bytes).toString(),
    'size': bytes.length,
  });
  late Directory temp;
  late Directory cache;
  late File output;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pdfium-download-test-');
    cache = Directory.fromUri(temp.uri.resolve('cache/'));
    output = File.fromUri(temp.uri.resolve('build/libpdfium.dylib'));
  });
  tearDown(() => temp.delete(recursive: true));

  PdfiumDownloader downloader(
    Future<http.Response> Function(http.Request) respond, {
    Duration timeout = const Duration(seconds: 2),
  }) => PdfiumDownloader(
    cacheDirectory: cache,
    clientFactory: () => MockClient(respond),
    retryDelay: Duration.zero,
    requestTimeout: timeout,
    log: (_) {},
  );

  Future<void> install(PdfiumDownloader loader, {String path = libraryPath}) =>
      loader.install(archive: artifact, libraryPath: path, output: output);

  test('retries HTTP 504 then uses the official binary API', () async {
    final requests = <Uri>[];
    await install(
      downloader((request) async {
        requests.add(request.url);
        if (request.url == artifact.url) return http.Response('', 504);
        expect(request.headers['Accept'], 'application/octet-stream');
        return http.Response.bytes(bytes, 200);
      }),
    );
    expect(requests, [artifact.url, artifact.url, artifact.apiUrl]);
    expect(await output.readAsBytes(), library);
  });

  test('recovers from a transient error without using the API', () async {
    var requests = 0;
    await install(
      downloader((request) async {
        expect(request.url, artifact.url);
        if (++requests == 1) throw const SocketException('reset');
        return http.Response.bytes(bytes, 200);
      }),
    );
    expect(requests, 2);
    expect(await output.readAsBytes(), library);
  });

  test('reuses the verified archive after build output is deleted', () async {
    await install(downloader((_) async => http.Response.bytes(bytes, 200)));
    await output.parent.delete(recursive: true);
    await install(
      downloader((_) async => fail('Cache must avoid the network')),
    );
    expect(await output.readAsBytes(), library);
  });

  test('replaces a corrupt cache even when its size is correct', () async {
    await cache.create();
    final file = File.fromUri(cache.uri.resolve('${artifact.digest}.tgz'));
    await file.writeAsBytes(List<int>.filled(bytes.length, 0));
    await install(downloader((_) async => http.Response.bytes(bytes, 200)));
    expect(await file.readAsBytes(), bytes);
    expect(await output.readAsBytes(), library);
  });

  test('rejects bad checksums without changing an existing output', () async {
    await output.parent.create();
    await output.writeAsString('previous working library');
    final badBytes = List<int>.of(bytes)..[0] ^= 1;
    await expectLater(
      install(downloader((_) async => http.Response.bytes(badBytes, 200))),
      throwsA(
        isA<HttpException>().having(
          (e) => e.message,
          'diagnostic',
          contains('SHA-256 mismatch'),
        ),
      ),
    );
    expect(await output.readAsString(), 'previous working library');
    expect(await cache.exists(), isFalse);
  });

  test('rejects an oversized response before publishing files', () async {
    await expectLater(
      install(downloader((_) async => http.Response.bytes([...bytes, 0], 200))),
      throwsA(
        isA<HttpException>().having(
          (e) => e.message,
          'diagnostic',
          contains('exceeds its pinned size'),
        ),
      ),
    );
    expect(await output.exists(), isFalse);
    expect(await cache.exists(), isFalse);
  });

  test('reports HTTP status and skips retries for permanent errors', () async {
    var requests = 0;
    await expectLater(
      install(
        downloader((_) async {
          requests++;
          return http.Response('', 404);
        }),
      ),
      throwsA(
        isA<HttpException>().having(
          (e) => e.message,
          'diagnostic',
          allOf(contains('HTTP 404'), contains(artifact.apiUrl.toString())),
        ),
      ),
    );
    expect(requests, 2);
    expect(await output.exists(), isFalse);
  });

  test('a request deadline allows fallback instead of hanging', () async {
    await install(
      downloader((request) async {
        if (request.url == artifact.url) {
          return Completer<http.Response>().future;
        }
        return http.Response.bytes(bytes, 200);
      }, timeout: const Duration(milliseconds: 10)),
    );
    expect(await output.readAsBytes(), library);
  });

  test('does not publish an archive without the requested library', () async {
    await expectLater(
      install(
        downloader((_) async => http.Response.bytes(bytes, 200)),
        path: 'missing/library',
      ),
      throwsStateError,
    );
    expect(await output.exists(), isFalse);
    expect(await cache.exists(), isFalse);
  });

  test(
    'concurrent hooks publish complete files without leftover temporaries',
    () async {
      final loader = downloader((_) async => http.Response.bytes(bytes, 200));
      await Future.wait([install(loader), install(loader)]);
      expect(await output.readAsBytes(), library);
      expect(
        (await cache.list().toList()).map((f) => f.uri.pathSegments.last),
        ['${artifact.digest}.tgz'],
      );
      expect((await output.parent.list().toList()).length, 1);
    },
  );

  test('every supported archive has a pinned official source and checksum', () {
    final manifest =
        jsonDecode(File('hook/pdfium_binaries.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(manifest['release'], 'chromium/7811');
    final assets = manifest['assets'] as Map<String, dynamic>;
    expect(
      assets.keys,
      containsAll(['pdfium-mac-arm64.tgz', 'pdfium-mac-x64.tgz']),
    );
    for (final value in assets.values) {
      final pinned = PdfiumArchive.fromJson(value as Map<String, dynamic>);
      expect(pinned.url.host, 'github.com');
      expect(pinned.apiUrl.host, 'api.github.com');
      expect(pinned.digest, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(pinned.size, greaterThan(0));
    }
  });
}
