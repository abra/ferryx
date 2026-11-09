import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/testing.dart';
import 'package:pagecraft/all_formats.dart';

const fixtures = 'test/fixtures/pdf';

void main() {
  setUpAll(preparePdfEngineForTests);

  test('finds the printed area of a text page in points', () async {
    final book = await PdfBook.open('$fixtures/text_lines.pdf');
    addTearDown(book.close);
    final box = (await detectPdfPageContent(book, 0))!;
    // One sample pixel is 792 / 160 ≈ 5 pt; the ink starts at 72 pt.
    expect(box.left, closeTo(72, 10));
    expect(box.top, closeTo(792 - 730, 10));
    expect(box.bottom, closeTo(792 - 617, 10));
    expect(box.right, lessThan(430));
    expect(box.right, greaterThan(380));
  });

  test('plans the crop the reader draws', () async {
    final book = await PdfBook.open('$fixtures/text_lines.pdf');
    addTearDown(book.close);
    final page = book.pages[0];
    final crop = contentCrop(
      content: await detectPdfPageContent(book, 0),
      width: page.width,
      height: page.height,
      availableWidth: 390,
      availableHeight: 844,
    )!;
    expect(crop.left, greaterThan(50));
    expect(crop.left, lessThan(72));
    expect(crop.width, lessThan(page.width * 0.85));
    // The phone box wants more height than the page has: the crop runs to
    // the bottom edge and starts above the ink.
    expect(crop.bottom, closeTo(page.height, 1e-6));
    expect(crop.top, lessThan(792 - 730));
  });

  test('a lone title keeps the whole page', () async {
    final book = await PdfBook.open('$fixtures/many_pages.pdf');
    addTearDown(book.close);
    final page = book.pages[0];
    final box = await detectPdfPageContent(book, 0);
    expect(box, isNotNull);
    expect(box!.width, lessThan(page.width * 0.5));
    expect(
      contentCrop(
        content: box,
        width: page.width,
        height: page.height,
        availableWidth: 390,
        availableHeight: 844,
      ),
      isNull,
    );
  });
}
