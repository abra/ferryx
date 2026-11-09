import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

const container =
    '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>';

String chapter(String title, int paragraphs, {String extra = ''}) =>
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head><body>'
    '<h1>$title</h1>'
    '${List.generate(paragraphs, (i) => '<p id="$title-$i">$title paragraph $i has words enough to wrap twice in a column.</p>').join()}'
    '$extra</body></html>';

Future<EpubTextSource> book({
  String language = 'en',
  String? secondChapter,
}) async => EpubTextSource(
  await EpubBook.load(
    MemoryEpubFiles({
      'META-INF/container.xml': utf8.encode(container),
      'OEBPS/content.opf': utf8.encode(
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:language>$language</dc:language></metadata>'
        '<manifest>'
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
        '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="notes" href="notes.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>'
        '</manifest><spine><itemref idref="a"/><itemref idref="notes" linear="no"/>'
        '<itemref idref="b"/></spine></package>',
      ),
      'OEBPS/nav.xhtml': utf8.encode(
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>'
        '<nav epub:type="toc"><ol><li><a href="a.xhtml">Part A</a></li>'
        '<li><a href="b.xhtml">Part B</a><ol><li><a href="b.xhtml#B-20">B twenty</a></li></ol></li>'
        '</ol></nav></body></html>',
      ),
      'OEBPS/a.xhtml': utf8.encode(chapter('A', 12)),
      'OEBPS/notes.xhtml': utf8.encode(chapter('N', 2)),
      'OEBPS/b.xhtml': utf8.encode(secondChapter ?? chapter('B', 30)),
    }),
  ),
);

const style = BookStyle(fontScale: 10 / 16, lineHeight: 1.5);
const settings = TextPageSettings(
  sideMarginPercent: 0,
  topMargin: 10,
  bottomMargin: 10,
);

void main() {
  late BookImageCache images;
  late TextPagesController controller;

  setUp(() => images = BookImageCache(read: (_) async => null));
  tearDown(() {
    controller.dispose();
    images.dispose();
  });

  /// Waits until [condition] holds, letting isolates and slices run.
  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 400 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), isTrue, reason: 'timed out (${controller.error})');
  }

  Future<TextPagesController> open({
    String? initialCfi,
    double? initialFraction,
    TextPageSettings pageSettings = settings,
    Size size = const Size(200, 140),
  }) async {
    controller = TextPagesController(
      source: await book(),
      style: style,
      fonts: const BookFonts(),
      images: images,
      settings: pageSettings,
      initialCfi: initialCfi,
      initialFraction: initialFraction,
    )..setViewport(size);
    await until(() => controller.position != null);
    return controller;
  }

  test('opens at the first page of the reading order', () async {
    await open();
    final position = controller.position!;
    expect(position.section, 0);
    expect(position.spread, 0);
    expect(position.reason, TextRelocationReason.navigation);
    // What is shown, as a range: from the heading to the page's end.
    expect(position.cfi, startsWith('epubcfi(/6/2!/4,/2/1:0,'));
    expect(controller.geometry!.columns, 1);
    expect(controller.spreadAt(0)!.pages, hasLength(1));
    // The rest of the section is laid out in the background.
    await until(() => controller.position!.spreadCount != null);
    expect(controller.position!.spreadCount, greaterThan(3));
    await until(() => controller.position!.tocItem != null);
    expect(controller.position!.tocItem!.label, 'Part A');
  });

  test(
    'resolves RTL before showing a Latin opening and keeps it on relayout',
    () async {
      final source = await book(
        language: 'ms',
        secondChapter:
            '<html><body>'
            '${List.filled(40, '<p>بسم الله الرحمن الرحيم الحمد لله رب العالمين</p>').join()}'
            '</body></html>',
      );
      addTearDown(source.close);
      expect(source.rtl, isFalse);
      controller = TextPagesController(
        source: source,
        style: style,
        fonts: const BookFonts(),
        images: images,
        settings: settings,
      )..setViewport(const Size(200, 140));
      await until(() => controller.position != null);
      expect(controller.position!.section, 0);
      expect(controller.rtl, isTrue);
      controller.setViewport(const Size(240, 140));
      await until(() => controller.isReady);
      expect(controller.rtl, isTrue);
    },
  );

  test('an explicit LTR override bypasses RTL language inference', () async {
    final source = await book(language: 'ar');
    addTearDown(source.close);
    controller = TextPagesController(
      source: source,
      style: style,
      fonts: const BookFonts(),
      images: images,
      settings: settings,
      rtl: false,
    )..setViewport(const Size(200, 140));
    await until(() => controller.position != null);
    expect(controller.rtl, isFalse);
  });

  test('turns through a section, skips non-linear ones, and back', () async {
    await open();
    await until(() => controller.position!.spreadCount != null);
    final spreads = controller.position!.spreadCount!;
    for (var i = 1; i < spreads; i++) {
      expect(await controller.next(), isTrue);
      expect(controller.position!.spread, i);
      expect(controller.position!.reason, TextRelocationReason.page);
    }
    expect(await controller.next(), isTrue);
    expect(controller.position!.section, 2, reason: 'notes are not linear');
    expect(controller.position!.spread, 0);
    expect(await controller.previous(), isTrue);
    expect(controller.position!.section, 0);
    expect(controller.position!.spread, spreads - 1);
    await controller.goToSection(0);
    expect(await controller.previous(), isFalse, reason: 'the start');
  });

  test('the end of the book does not turn', () async {
    await open(initialFraction: 1);
    expect(controller.position!.section, 2);
    expect(controller.position!.spreadCount, isNotNull);
    expect(
      controller.position!.spread,
      controller.position!.spreadCount! - 1,
    );
    expect(await controller.next(), isFalse);
  });

  test('a saved CFI opens its page, and survives a new page size', () async {
    await open();
    await controller.goToSection(2);
    await controller.next();
    await controller.next();
    final saved = controller.position!;
    controller.dispose();
    await open(initialCfi: saved.cfi);
    expect(controller.position!.section, 2);
    expect(controller.position!.spread, saved.spread);
    expect(controller.position!.cfi, saved.cfi);

    controller.setViewport(const Size(320, 240));
    await until(
      () => controller.position!.reason == TextRelocationReason.layout,
    );
    final relaid = controller.position!;
    expect(relaid.section, 2);
    expect(relaid.spread, lessThan(saved.spread), reason: 'bigger pages');
    // The text that was first is still on the page shown.
    final layout = controller.spreadAt(0)!.layout;
    final y = layout.locator.yOfCfi(saved.cfi)!;
    expect(controller.spreadAt(0)!.pages.single.contains(y), isTrue);
  });

  test('fractions, targets and links open where they point', () async {
    await open();
    await controller.goToFraction(0.75);
    final position = controller.position!;
    expect(position.section, 2);
    expect(position.fraction, closeTo(0.75, 0.1));
    expect(position.reason, TextRelocationReason.navigation);

    expect(await controller.goToHref('OEBPS/b.xhtml#B-20'), isTrue);
    final layout = controller.spreadAt(0)!.layout;
    final y = layout.locator.yOfAnchor(const TextAnchor.id('B-20'))!;
    expect(controller.spreadAt(0)!.pages.single.contains(y), isTrue);
    expect(controller.position!.tocItem?.label, 'B twenty');
    expect(await controller.goToHref('OEBPS/missing.xhtml'), isFalse);
  });

  test('neighbours are laid out ahead for the view to draw', () async {
    await open();
    await until(() => controller.spreadAt(1) != null);
    expect(controller.spreadAt(-1), isNull, reason: 'the start of the book');
    await until(() => controller.position!.spreadCount != null);
    await controller.goToSection(2);
    await until(() => controller.spreadAt(-1) != null);
    expect(controller.spreadAt(-1)!.section, 0, reason: 'the end of section A');
  });

  test('two columns make spreads of two pages', () async {
    await open(
      pageSettings: const TextPageSettings(
        sideMarginPercent: 2,
        topMargin: 10,
        bottomMargin: 10,
        maxColumnCount: 2,
      ),
      size: const Size(400, 140),
    );
    expect(controller.geometry!.columns, 2);
    await until(() => controller.position!.spreadCount != null);
    final spread = controller.spreadAt(0)!;
    expect(spread.pages, hasLength(2));
    final pages = spread.layout.pages.length;
    expect(controller.position!.spreadCount, (pages + 1) ~/ 2);
    await controller.next();
    expect(controller.spreadAt(0)!.pages.first, spread.layout.pages[2]);
  });

  test('a new style lays the book out again at the same text', () async {
    await open();
    await controller.goToSection(2);
    await controller.next();
    final before = controller.position!;
    controller.style = const BookStyle(fontScale: 14 / 16, lineHeight: 1.5);
    await until(
      () => controller.position!.reason == TextRelocationReason.layout,
    );
    expect(controller.position!.section, 2);
    final layout = controller.spreadAt(0)!.layout;
    final y = layout.locator.yOfCfi(before.cfi)!;
    expect(controller.spreadAt(0)!.pages.single.contains(y), isTrue);
  });
}
