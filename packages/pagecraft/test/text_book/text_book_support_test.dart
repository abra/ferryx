import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

const _container =
    '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>';

String _chapter(String title, {String style = ''}) =>
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title>'
    '${style.isEmpty ? '' : '<style>$style</style>'}</head><body>'
    '${List.generate(20, (i) => '<p>$title paragraph $i has words enough to wrap twice.</p>').join()}'
    '</body></html>';

/// Two chapters, the second styled with [secondStyle]; [metadata] goes
/// into the package document.
Future<EpubTextSource> _book({
  String firstStyle = '',
  String secondStyle = '',
  String metadata = '',
}) async => EpubTextSource(
  await EpubBook.load(
    MemoryEpubFiles({
      'META-INF/container.xml': utf8.encode(_container),
      'OEBPS/content.opf': utf8.encode(
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" prefix="rendition: http://www.idpf.org/vocab/rendition/#">'
        '<metadata>$metadata</metadata><manifest>'
        '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>'
        '</manifest><spine><itemref idref="a"/><itemref idref="b"/></spine></package>',
      ),
      'OEBPS/a.xhtml': utf8.encode(_chapter('A', style: firstStyle)),
      'OEBPS/b.xhtml': utf8.encode(_chapter('B', style: secondStyle)),
    }),
  ),
);

void main() {
  late BookImageCache images;
  late TextPagesController controller;

  setUp(() => images = BookImageCache(read: (_) async => null));
  tearDown(() {
    controller.dispose();
    images.dispose();
  });

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 400 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), isTrue, reason: 'timed out (${controller.error})');
  }

  void open(EpubTextSource source) {
    controller = TextPagesController(
      source: source,
      style: const BookStyle(fontScale: 10 / 16),
      fonts: const BookFonts(),
      images: images,
      settings: const TextPageSettings(
        sideMarginPercent: 0,
        topMargin: 10,
        bottomMargin: 10,
      ),
    )..setViewport(const Size(200, 140));
  }

  TextBookUnsupported? reason() => switch (controller.error) {
    UnsupportedTextBookException(:final reason) => reason,
    _ => null,
  };

  test('a horizontal book opens', () async {
    open(await _book());
    await until(() => controller.position != null);
    expect(controller.error, isNull);
  });

  test('a vertical book is not laid out', () async {
    open(await _book(firstStyle: 'body { -epub-writing-mode: vertical-rl }'));
    await until(() => controller.error != null);
    expect(reason(), TextBookUnsupported.verticalWriting);
    expect(controller.position, isNull);
  });

  test('vertical writing on html reaches the body', () async {
    open(await _book(firstStyle: 'html { writing-mode: tb-rl }'));
    await until(() => controller.error != null);
    expect(reason(), TextBookUnsupported.verticalWriting);
  });

  test('vertical text inside a horizontal body is laid out', () async {
    // A rotated table header, say: the section's lines stay horizontal.
    open(await _book(firstStyle: 'p { writing-mode: vertical-rl }'));
    await until(() => controller.position != null);
    expect(controller.error, isNull);
  });

  test('a vertical chapter is refused when the reader turns to it', () async {
    open(
      await _book(secondStyle: 'body { writing-mode: vertical-rl }'),
    );
    await until(() => controller.position != null);
    var turned = true;
    for (var i = 0; i < 20 && turned && controller.error == null; i++) {
      try {
        turned = await controller.next();
      } on UnsupportedTextBookException {
        break;
      }
    }
    expect(reason(), TextBookUnsupported.verticalWriting);
    expect(controller.position!.section, 0, reason: 'still on the first');
  });

  test('a fixed-layout book is not laid out', () async {
    final source = await _book(
      metadata: '<meta property="rendition:layout">pre-paginated</meta>',
    );
    expect(source.isFixedLayout, isTrue);
    open(source);
    await until(() => controller.error != null);
    expect(reason(), TextBookUnsupported.fixedLayout);
  });
}
