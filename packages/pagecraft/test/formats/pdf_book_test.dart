import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart'
    show PdfDest, PdfDestCommand, PdfOutlineNode;
import 'package:pagecraft/testing.dart';
import 'package:pagecraft/all_formats.dart';

const fixtures = 'test/fixtures/pdf';

void main() {
  setUpAll(preparePdfEngineForTests);

  group('PdfBook.open', () {
    test('reads page sizes, the Info dictionary and the outline', () async {
      final book = await PdfBook.open('$fixtures/text_outline.pdf');
      addTearDown(book.close);

      expect(book.pageCount, 3);
      expect(book.pages.map((p) => p.index), [0, 1, 2]);
      expect(book.pages[0].width, 612);
      expect(book.pages[0].height, 792);
      expect(book.pages[0].rotation, 0);
      // `/Rotate 90` turns the page: the displayed size is landscape.
      expect(book.pages[1].width, 792);
      expect(book.pages[1].height, 612);
      expect(book.pages[1].rotation, 1);
      expect(book.pages[2].width, 400);
      expect(book.pages[2].height, 600);
      expect(book.pages[2].aspectRatio, closeTo(2 / 3, 1e-9));

      expect(book.title, 'Vellum Fixture');
      expect(book.author, 'Fixture Author');

      expect(book.outline.map((e) => e.title), ['Chapter One', 'Chapter Two']);
      expect(book.outline[0].pageIndex, 0);
      expect(book.outline[0].children.single.title, 'Section 1.1');
      expect(book.outline[0].children.single.pageIndex, 1);
      expect(book.outline[1].pageIndex, 2);
      expect(book.outline[1].children, isEmpty);
    });

    test('a plain document has no outline and no title', () async {
      final book = await PdfBook.open('$fixtures/plain.pdf');
      addTearDown(book.close);
      expect(book.pageCount, 1);
      expect(book.title, isNull);
      expect(book.author, isNull);
      expect(book.outline, isEmpty);
    });

    test('loads every page size of a long document', () async {
      final stopwatch = Stopwatch()..start();
      final book = await PdfBook.open('$fixtures/many_pages.pdf');
      stopwatch.stop();
      addTearDown(book.close);
      expect(book.pageCount, 200);
      expect(
        book.pages.every((p) => p.width == 612 && p.height == 792),
        isTrue,
      );
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 5)),
        reason: 'page sizes are read in one pass in the worker isolate',
      );
    });

    test('an encrypted file needs its password', () async {
      await expectLater(
        PdfBook.open('$fixtures/locked.pdf'),
        throwsA(isA<PdfPasswordRequiredException>()),
      );
      await expectLater(
        PdfBook.open('$fixtures/locked.pdf', password: 'wrong'),
        throwsA(isA<PdfPasswordRequiredException>()),
      );
      final book = await PdfBook.open(
        '$fixtures/locked.pdf',
        password: 'secret',
      );
      addTearDown(book.close);
      expect(book.pageCount, 3);
      expect(book.title, 'Vellum Fixture');
    });

    test('a password is not needed for an unencrypted file', () async {
      final book = await PdfBook.open('$fixtures/plain.pdf', password: 'x');
      addTearDown(book.close);
      expect(book.pageCount, 1);
    });

    test('rejects damaged, foreign and missing files', () async {
      final tempDir = await Directory.systemTemp.createTemp('pdf_book_');
      addTearDown(() => tempDir.delete(recursive: true));
      final whole = await File('$fixtures/text_outline.pdf').readAsBytes();
      final truncated = File('${tempDir.path}/truncated.pdf');
      await truncated.writeAsBytes(whole.sublist(0, whole.length ~/ 2));
      final junk = File('${tempDir.path}/junk.pdf');
      await junk.writeAsString('not a pdf at all');

      for (final path in [
        truncated.path,
        junk.path,
        '${tempDir.path}/missing.pdf',
      ]) {
        await expectLater(
          PdfBook.open(path),
          throwsA(
            isA<PagecraftException>()
                .having((e) => e.message, 'message', contains(path))
                .having(
                  (e) => e,
                  'type',
                  isNot(isA<PdfPasswordRequiredException>()),
                ),
          ),
          reason: path,
        );
      }
    });
  });

  group('PdfBook.close', () {
    test('is idempotent and bars the document afterwards', () async {
      final book = await PdfBook.open('$fixtures/plain.pdf');
      expect(book.document, isNotNull);
      await book.close();
      await book.close();
      expect(() => book.document, throwsStateError);
      expect(book.pageCount, 1, reason: 'the page list stays readable');
    });
  });

  group('pdfOutlineEntriesFrom', () {
    const dest = PdfDest(2, PdfDestCommand.xyz, null);

    test('converts 1-based destinations and nests children', () {
      final entries = pdfOutlineEntriesFrom(const [
        PdfOutlineNode(
          title: 'Part',
          dest: PdfDest(1, PdfDestCommand.fit, null),
          children: [
            PdfOutlineNode(title: 'Chapter', dest: dest, children: []),
          ],
        ),
      ], pageCount: 3);
      expect(entries.single.title, 'Part');
      expect(entries.single.pageIndex, 0);
      expect(entries.single.children.single.pageIndex, 1);
    });

    test('leaves entries without a usable destination unlinked', () {
      final entries = pdfOutlineEntriesFrom(const [
        PdfOutlineNode(title: 'No dest', dest: null, children: []),
        PdfOutlineNode(
          title: 'Past the end',
          dest: PdfDest(4, PdfDestCommand.xyz, null),
          children: [],
        ),
        PdfOutlineNode(
          title: 'Zero',
          dest: PdfDest(0, PdfDestCommand.xyz, null),
          children: [],
        ),
      ], pageCount: 3);
      expect(entries.map((e) => e.pageIndex), [null, null, null]);
    });
  });
}
