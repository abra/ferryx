import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// One immutable archive, pinned to the official release's size and SHA-256.
final class PdfiumArchive {
  PdfiumArchive.fromJson(Map<String, dynamic> json)
    : url = Uri.parse(json['url'] as String),
      apiUrl = Uri.parse(json['api_url'] as String),
      digest = json['sha256'] as String,
      size = json['size'] as int;

  final Uri url;
  final Uri apiUrl;
  final String digest;
  final int size;

  bool accepts(List<int> bytes) =>
      bytes.length == size && sha256.convert(bytes).toString() == digest;
}

/// Installs only the requested member from a verified PDFium archive.
///
/// The archive cache survives `flutter clean`. Both it and the native asset are
/// published by rename, so concurrent hooks never read partially written files.
final class PdfiumDownloader {
  PdfiumDownloader({
    required this.cacheDirectory,
    http.Client Function()? clientFactory,
    this.attemptsPerEndpoint = 2,
    this.retryDelay = const Duration(seconds: 1),
    this.requestTimeout = const Duration(seconds: 30),
    void Function(String)? log,
  }) : assert(attemptsPerEndpoint > 0),
       _clientFactory = clientFactory ?? _createClient,
       _log = log ?? stderr.writeln;

  final Directory cacheDirectory;
  final int attemptsPerEndpoint;
  final Duration retryDelay;
  final Duration requestTimeout;
  final http.Client Function() _clientFactory;
  final void Function(String) _log;

  Future<void> install({
    required PdfiumArchive archive,
    required String libraryPath,
    required File output,
  }) async {
    final cache = File.fromUri(
      cacheDirectory.uri.resolve('${archive.digest}.tgz'),
    );
    Uint8List? bytes;
    if (await cache.exists()) {
      // Check the length before allocating a buffer for an untrusted cache file.
      if (await cache.length() == archive.size) {
        final cached = await cache.readAsBytes();
        if (archive.accepts(cached)) bytes = cached;
      }
      if (bytes == null) _log('PDFium: ignoring corrupt cache ${cache.path}');
    }

    final fromCache = bytes != null;
    bytes ??= await _download(archive);
    final contents = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
    final member = contents.findFile(libraryPath);
    if (member == null || !member.isFile || member.size == 0) {
      throw StateError('PDFium archive does not contain $libraryPath');
    }

    if (!fromCache) await _writeAtomically(cache, bytes);
    await _writeAtomically(output, member.content);
  }

  Future<Uint8List> _download(PdfiumArchive archive) async {
    final failures = <String>[];
    for (final endpoint in [archive.url, archive.apiUrl]) {
      for (var attempt = 1; attempt <= attemptsPerEndpoint; attempt++) {
        final client = _clientFactory();
        try {
          final bytes = await _fetch(
            client,
            endpoint,
            archive,
          ).timeout(requestTimeout);
          if (!archive.accepts(bytes)) {
            throw const FormatException(
              'PDFium archive size or SHA-256 mismatch',
            );
          }
          return bytes;
        } on Exception catch (error) {
          failures.add('$endpoint (attempt $attempt): $error');
          _log('PDFium: ${failures.last}');
          final retryable = switch (error) {
            _HttpFailure(:final status) =>
              status == 408 || status == 429 || status >= 500,
            SocketException() ||
            http.ClientException() ||
            TimeoutException() => true,
            _ => false,
          };
          if (!retryable || attempt == attemptsPerEndpoint) break;
        } finally {
          client.close();
        }
        await Future<void>.delayed(retryDelay * attempt);
      }
    }
    throw HttpException(
      'Failed to download verified PDFium from GitHub:\n${failures.join('\n')}',
    );
  }

  Future<Uint8List> _fetch(
    http.Client client,
    Uri endpoint,
    PdfiumArchive archive,
  ) async {
    final request = http.Request('GET', endpoint)
      ..headers['Accept'] = 'application/octet-stream'
      ..headers['User-Agent'] = 'pdfium_dart/0.2.5';
    final response = await client.send(request);
    if (response.statusCode != 200) throw _HttpFailure(response.statusCode);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > archive.size) {
        throw const FormatException('PDFium archive exceeds its pinned size');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }
}

http.Client _createClient() {
  final client = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
  return IOClient(client);
}

Directory pdfiumCacheDirectory() {
  final env = Platform.environment;
  final override = env['PDFIUM_DART_CACHE'];
  if (override != null && override.isNotEmpty) return Directory(override);
  final home = env['HOME'];
  final base = Platform.isWindows
      ? env['LOCALAPPDATA']
      : Platform.isMacOS && home != null
      ? '$home/Library/Caches'
      : env['XDG_CACHE_HOME'] ?? (home == null ? null : '$home/.cache');
  return Directory('${base ?? Directory.systemTemp.path}/pdfium_dart');
}

Future<void> _writeAtomically(File destination, List<int> bytes) async {
  await destination.parent.create(recursive: true);
  final temp = await destination.parent.createTemp('.pdfium-');
  try {
    final file = File.fromUri(temp.uri.resolve('download'));
    await file.writeAsBytes(bytes, flush: true);
    await file.rename(destination.path);
  } finally {
    await temp.delete(recursive: true);
  }
}

final class _HttpFailure implements Exception {
  const _HttpFailure(this.status);
  final int status;

  @override
  String toString() => 'HTTP $status';
}
