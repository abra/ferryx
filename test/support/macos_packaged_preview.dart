// Alternate release entry point for the macOS CI build. It exercises the
// native libraries bundled by Flutter without shipping test hooks in Ferryx.
import 'dart:io';

import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' show FerryxBackend;
import 'package:file_repository/file_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:monitoring/monitoring.dart';
import 'package:pagecraft/epub.dart';
import 'package:pagecraft/pdf.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final [epub, pdf, office] = arguments;
    final backend = await FerryxBackend.initialize();
    final logger = Logger();
    final files = FileRepository(backend: backend, logger: logger);
    try {
      await _readEpub(epub);
      await _renderPdf(pdf);
      final docx = Location.inArchive(archive: office, path: 'fixture.docx');
      final bytes = await files.readRange(docx, 0, await files.fileSize(docx));
      final html = await files.renderTextDocument(
        bytes,
        TextDocumentFormat.docx,
      );
      if (!html.contains('Ferryx office preview')) {
        throw StateError('The bundled Rust converter did not render DOCX.');
      }
    } finally {
      await files.dispose();
      await logger.destroy();
    }
    stdout.writeln('Packaged EPUB, PDF and DOCX checks passed.');
    exit(0);
  } on Object catch (error, stackTrace) {
    stderr.writeln('$error\n$stackTrace');
    exit(1);
  }
}

Future<void> _readEpub(String path) async {
  final book = await EpubBook.open(path);
  try {
    final chapter = await book.readSectionText(1);
    if (!chapter.contains('Chapter One')) {
      throw StateError('The packaged reader did not load the EPUB chapter.');
    }
  } finally {
    await book.close();
  }
}

Future<void> _renderPdf(String path) async {
  await initializePdfEngine();
  final metadata = await readPdfMetadata(path);
  if (metadata.cover == null) {
    throw StateError('The bundled PDF engine did not render the first page.');
  }
}
