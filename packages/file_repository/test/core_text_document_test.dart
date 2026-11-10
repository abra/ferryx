import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' show FerryxBackend;
import 'package:file_repository/file_repository.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoring/monitoring.dart';

void main() {
  final library = File(
    '../../rust/target/debug/${Platform.isMacOS
        ? 'libferryx_api.dylib'
        : Platform.isWindows
        ? 'ferryx_api.dll'
        : 'libferryx_api.so'}',
  );
  final skip = library.existsSync() ? null : 'run make core first';
  late FileRepository files;
  setUpAll(() async {
    if (skip != null) return;
    final backend = await FerryxBackend.initialize(
      externalLibrary: ExternalLibrary.open(library.path),
    );
    files = FileRepository(backend: backend, logger: Logger());
  });
  tearDownAll(() async {
    if (skip == null) await files.dispose();
  });
  for (final (format, text, expected) in [
    (
      TextDocumentFormat.rtf,
      r'{\rtf1\ansi {\b Bold} \u1055?\u1088?\u1080?\u1074?\u1077?\u1090?}',
      '<strong>Bold</strong>',
    ),
    (
      TextDocumentFormat.asciiDoc,
      '= Guide\n\n* *Bold*\n* Next',
      '<strong>Bold</strong>',
    ),
    (
      TextDocumentFormat.reStructuredText,
      'Guide\n=====\n\n**Bold**',
      '<strong>Bold</strong>',
    ),
  ]) {
    test('$format converts over the real Dart/Rust bridge', () async {
      final html = await files.renderTextDocument(
        Uint8List.fromList(utf8.encode(text)),
        format,
      );
      expect(html, contains(expected));
      if (format == TextDocumentFormat.rtf) expect(html, contains('Привет'));
    }, skip: skip);
  }
  test(
    'native malformed document errors retain a typed domain error',
    () async {
      await expectLater(
        files.renderTextDocument(
          Uint8List.fromList(utf8.encode('bad')),
          TextDocumentFormat.rtf,
        ),
        throwsA(
          isA<FerryxException>().having(
            (e) => e.kind,
            'kind',
            FerryxErrorKind.unsupported,
          ),
        ),
      );
    },
    skip: skip,
  );
}
