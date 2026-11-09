import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

/// Ports of `article_highlight_merge.test.mjs` (the WebView reader's
/// browser tests) on an EPUB section, and the selection payload fields.
const container =
    '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>';

const content =
    '<p id="block-0"><span data-rf-sentence="0">The power bank keeps <em>devices</em> running. </span>'
    '<span data-rf-sentence="1">A second sentence follows here.</span></p>'
    '<p id="block-1"><span data-rf-sentence="0">Another paragraph stays apart.</span></p>';

Future<EpubBook> book() => EpubBook.load(
  MemoryEpubFiles({
    'META-INF/container.xml': utf8.encode(container),
    'OEBPS/content.opf': utf8.encode(
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata/>'
      '<manifest>'
      '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine><itemref idref="c1"/><itemref idref="c2"/></spine></package>',
    ),
    'OEBPS/c1.xhtml': utf8.encode(
      '<html xmlns="http://www.w3.org/1999/xhtml"><body>$content</body></html>',
    ),
    'OEBPS/c2.xhtml': utf8.encode(
      '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Other.</p></body></html>',
    ),
  }),
);

void main() {
  late EpubTextSource source;
  late PreparedSection section;
  late String sectionCfi;
  late ContentDocument doc;

  setUp(() async {
    source = EpubTextSource(await book());
    section = await SectionPreparer(source).prepare(0, const BookStyle());
    sectionCfi = source.sectionCfi(0);
    doc = section.document;
  });

  /// The range of the first [text] in the body's text nodes.
  TextPointRange rangeFor(String text) {
    final nodes = <(int, int)>[];
    final full = StringBuffer();
    for (var i = 0; i < doc.nodeCount; i++) {
      if (!doc.isText(i)) continue;
      nodes.add((i, full.length));
      full.write(doc.textOf(i));
    }
    final start = full.toString().indexOf(text);
    expect(start, isNonNegative, reason: text);
    final end = start + text.length;
    final first = nodes.lastWhere((n) => n.$2 <= start);
    final last = nodes.firstWhere(
      (n) => end > n.$2 && end <= n.$2 + doc.textOf(n.$1).length,
    );
    return TextPointRange(
      TextPoint(first.$1, start - first.$2),
      TextPoint(last.$1, end - last.$2),
    );
  }

  TextSelectionDetails select(
    String text, {
    List<SavedTextHighlight> highlights = const [],
  }) => TextSelectionDetails.of(
    section,
    rangeFor(text),
    sectionCfi: sectionCfi,
    text: text,
    highlights: highlights,
  );

  List<SavedTextHighlight> save(List<(String, String)> list) => [
    for (final (id, text) in list)
      SavedTextHighlight(id: id, cfi: select(text).cfi, text: text),
  ];

  /// The text a CFI restores to.
  String restored(String cfi) =>
      doc.textOfRange(doc.textRangeOf(cfiToRange(doc, Cfi.parse(cfi))));

  test('the payload has full CFIs, words and the sentence around', () {
    final details = select('ower ban');
    // No <head>: the body is the first child, /2, with the id step.
    expect(details.cfi, 'epubcfi(/6/2!/2/2[block-0]/2,/1:5,/1:13)');
    expect(restored(details.cfi), 'ower ban');
    expect(details.kind, SelectionKind.partialSpan);
    expect(details.normalizedText, 'power bank');
    expect(restored(details.normalizedCfi), 'power bank');
    expect(details.contextText, 'The power bank keeps devices running.');
    expect(
      details.markedContextText,
      'The p[[ower ban]]k keeps devices running.',
    );
    expect(
      details.normalizedMarkedContextText,
      'The [[power bank]] keeps devices running.',
    );
    expect(details.highlightMerge, isNull);

    final whole = select('power bank');
    expect(whole.kind, SelectionKind.exact);
    expect(whole.normalizedText, 'power bank');
    expect(whole.normalizedCfi, whole.cfi);
  });

  test('a partial overlap across an inline element merges exactly', () {
    final merge = select(
      'devices running',
      highlights: save([('phrase', 'power bank keeps devices')]),
    ).highlightMerge!;
    expect(merge.highlightIds, ['phrase']);
    expect(merge.text, 'power bank keeps devices running');
    expect(restored(merge.cfi), 'power bank keeps devices running');
  });

  test('a merge across sentences anchors the union', () {
    final merge = select(
      'second sentence',
      highlights: save([('tail', 'running. A second')]),
    ).highlightMerge!;
    expect(merge.highlightIds, ['tail']);
    expect(merge.text, 'running. A second sentence');
    expect(restored(merge.cfi), 'running. A second sentence');
  });

  test('a chain of overlaps is absorbed whole, in document order', () {
    final merge = select(
      'keeps devices',
      highlights: save([('newer', 'bank keeps'), ('older', 'power bank')]),
    ).highlightMerge!;
    expect(merge.highlightIds, ['older', 'newer']);
    expect(merge.text, 'power bank keeps devices');
    expect(restored(merge.cfi), 'power bank keeps devices');
  });

  test('highlights in other paragraphs or sections are never absorbed', () {
    final merge = select(
      'The power',
      highlights: [
        ...save([('phrase', 'power bank'), ('apart', 'Another paragraph')]),
        const SavedTextHighlight(
          id: 'elsewhere',
          cfi: 'epubcfi(/6/4!/4/2,/1:0,/1:5)',
        ),
        const SavedTextHighlight(id: 'broken', cfi: 'not a cfi'),
        const SavedTextHighlight(id: 'missing', cfi: 'epubcfi(/6/2!/4/99/1:0)'),
      ],
    ).highlightMerge!;
    expect(merge.highlightIds, ['phrase']);
  });

  test('a selection inside a highlight keeps its identity', () {
    final saved = save([('phrase', 'power bank keeps')]);
    final merge = select('bank', highlights: saved).highlightMerge!;
    expect(merge.highlightIds, ['phrase']);
    expect(merge.cfi, saved.single.cfi);
    expect(merge.text, 'power bank keeps');
    final untitled = select(
      'bank',
      highlights: [
        SavedTextHighlight(id: 'phrase', cfi: saved.single.cfi, text: ''),
      ],
    ).highlightMerge!;
    expect(untitled.text, 'power bank keeps', reason: 'read from the book');
  });

  test('a selection over a whole highlight keeps the selected text', () {
    final merge = select(
      'power bank keeps devices',
      highlights: save([('inner', 'bank')]),
    ).highlightMerge!;
    expect(merge.highlightIds, ['inner']);
    expect(merge.text, 'power bank keeps devices');
  });

  test('merged text breaks lines between paragraphs', () {
    expect(
      textWithBlockBreaks(section, rangeFor('here.Another')),
      'here.\nAnother',
    );
    expect(
      textWithBlockBreaks(section, rangeFor('keeps devices running')),
      'keeps devices running',
      reason: 'inline elements do not break',
    );
  });

  test('the plan ignores empty selections and entries', () {
    final range = rangeFor('power');
    final collapsed = TextPointRange(range.start, range.start);
    final entry = (id: 'a', range: range);
    expect(planHighlightMerge(doc, collapsed, [entry]), isNull);
    expect(planHighlightMerge(doc, range, const []), isNull);
    expect(planHighlightMerge(doc, range, [(id: '', range: range)]), isNull);
    expect(
      planHighlightMerge(doc, range, [(id: 'b', range: collapsed)]),
      isNull,
    );
    final plan = planHighlightMerge(doc, range, [entry])!;
    expect(plan.sameAs, entry);
    expect(plan.range, range);
  });
}
