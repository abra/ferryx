import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  PdfTextLayer layerOf(String text) => PdfTextLayer(
    pageIndex: 2,
    text: text,
    charBoxes: [
      for (var i = 0; i < text.length; i++)
        PdfBox(i * 10.0, 0, i * 10.0 + 10, 10),
    ],
  );

  test('writes the page step both readers read and its own range', () {
    final cfi = pdfTextCfi(2, const PdfTextRange(5, 11));
    expect(cfi, 'epubcfi(/6/6!/2[pagecraft],/1:5,/1:11)');
    expect(fakeCfiToIndex(cfi), 2);
    expect(
      pdfTextAnchorFromCfi(cfi),
      const PdfTextAnchor(pageIndex: 2, range: PdfTextRange(5, 11)),
    );
  });

  test('does not read other readers\' CFIs as ranges', () {
    const dom = 'epubcfi(/6/4!/4/4,/1:0,/1:3)';
    expect(pdfTextAnchorFromCfi(dom), isNull);
    expect(fakeCfiToIndex(dom), 1, reason: 'the page is still known');
    expect(pdfTextAnchorFromCfi('epubcfi(/6/6)'), isNull);
    expect(
      pdfTextAnchorFromCfi('epubcfi(/6/6!/2[pagecraft],/1:9,/1:3)'),
      isNull,
    );
    expect(
      pdfTextAnchorFromCfi('epubcfi(/6/5!/2[pagecraft],/1:1,/1:3)'),
      isNull,
    );
  });

  group('resolvePdfTextAnchor', () {
    final layer = layerOf('lazy\ndog. It was a bright day');

    test('trusts its own range while the text still matches', () {
      expect(
        resolvePdfTextAnchor(
          layer,
          text: 'It was',
          cfiRange: pdfTextCfi(2, const PdfTextRange(10, 16)),
        ),
        const PdfTextRange(10, 16),
      );
    });

    test('searches the text when the range is stale or foreign', () {
      expect(
        resolvePdfTextAnchor(
          layer,
          text: 'It was',
          cfiRange: pdfTextCfi(2, const PdfTextRange(0, 6)),
        ),
        const PdfTextRange(10, 16),
      );
      expect(
        resolvePdfTextAnchor(
          layer,
          text: 'lazy dog.',
          cfiRange: 'epubcfi(/6/6!/4/4,/1:0,/1:3)',
        ),
        const PdfTextRange(0, 9),
      );
      expect(
        resolvePdfTextAnchor(
          layer,
          text: 'bright',
          cfiRange: pdfTextCfi(1, const PdfTextRange(0, 6)),
        ),
        const PdfTextRange(19, 25),
        reason: 'another page\'s range',
      );
      expect(
        resolvePdfTextAnchor(layer, text: 'bright'),
        const PdfTextRange(19, 25),
      );
    });

    test('answers null when the text is gone', () {
      expect(
        resolvePdfTextAnchor(
          layer,
          text: 'vanished',
          cfiRange: pdfTextCfi(2, const PdfTextRange(90, 99)),
        ),
        isNull,
      );
    });
  });
}
