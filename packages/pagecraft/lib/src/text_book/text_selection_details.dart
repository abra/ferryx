import '../document/text_point.dart';
import '../epubcfi/cfi.dart';
import '../epubcfi/cfi_resolve.dart';
import '../text/selection_normalizer.dart';
import 'highlight_merge.dart';
import 'section_preparer.dart';
import 'selection_context.dart';

/// A saved highlight of the book, as the app stores it.
class SavedTextHighlight {
  const SavedTextHighlight({required this.id, required this.cfi, this.text});

  final String id;

  /// Its full book CFI range.
  final String cfi;

  /// Its stored text, when the app has it.
  final String? text;
}

/// The highlight saving a selection makes: the CFI and text of the union
/// of the selection and the saved highlights it shares text with, and
/// those highlights' ids in document order.
class TextHighlightMerge {
  const TextHighlightMerge({
    required this.cfi,
    required this.text,
    required this.highlightIds,
  });

  final String cfi;
  final String text;
  final List<String> highlightIds;
}

/// Everything the reader tells text actions about a selection, with the
/// fields and rules of the WebView reader's selection payload
/// (`textSelectionPayloadForRange` in `book.js`).
class TextSelectionDetails {
  const TextSelectionDetails({
    required this.range,
    required this.text,
    required this.cfi,
    required this.normalizedCfi,
    required this.normalizedText,
    required this.kind,
    required this.contextText,
    required this.markedContextText,
    required this.normalizedMarkedContextText,
    this.highlightMerge,
  });

  /// Builds the details of [range] in [section], whose own CFI is
  /// [sectionCfi]. [text] is the selected text as shown (the selection's
  /// `SelectedContent`), [highlights] the book's saved highlights; those
  /// of other sections are skipped.
  factory TextSelectionDetails.of(
    PreparedSection section,
    TextPointRange range, {
    required String sectionCfi,
    required String text,
    List<SavedTextHighlight> highlights = const [],
  }) {
    final doc = section.document;
    String cfiOf(TextPointRange r) => joinCfiIndirections([
      sectionCfi,
      cfiFromRange(doc.cfiRangeOf(r)).toInnerString(),
    ]);
    final normalized = normalizeSelectionRange(doc, range);
    final exact = normalized == null || normalized.kind == SelectionKind.exact;
    final normalizedRange = normalized?.range ?? range;
    final context = buildSelectionContext(doc, range);
    final normalizedContext = exact
        ? context
        : buildSelectionContext(doc, normalizedRange);
    return TextSelectionDetails(
      range: range,
      text: text,
      cfi: cfiOf(range),
      normalizedCfi: cfiOf(normalizedRange),
      normalizedText: exact ? text : normalized.normalizedText,
      kind: normalized?.kind ?? SelectionKind.exact,
      contextText: normalizedContext.contextText,
      markedContextText: context.markedContextText,
      normalizedMarkedContextText: normalizedContext.markedContextText,
      highlightMerge: _merge(
        section,
        range,
        text,
        sectionCfi,
        highlights,
        cfiOf,
      ),
    );
  }

  final TextPointRange range;

  /// The selected text as shown.
  final String text;

  /// The selection's full book CFI range.
  final String cfi;

  /// The CFI of the selection grown to whole words.
  final String normalizedCfi;

  /// The selection grown to whole words; [text] when it was whole.
  final String normalizedText;

  final SelectionKind kind;

  /// The sentence around the selection grown to whole words.
  final String contextText;

  /// The sentence around the exact selection, the selection `[[marked]]`.
  final String markedContextText;

  /// [contextText] with the grown selection `[[marked]]`.
  final String normalizedMarkedContextText;

  /// What saving the selection as a highlight replaces; null when it
  /// shares no text with a saved highlight.
  final TextHighlightMerge? highlightMerge;
}

TextHighlightMerge? _merge(
  PreparedSection section,
  TextPointRange selection,
  String selectedText,
  String sectionCfi,
  List<SavedTextHighlight> highlights,
  String Function(TextPointRange) cfiOf,
) {
  if (highlights.isEmpty) return null;
  final doc = section.document;
  final spine = Cfi.tryParse(sectionCfi)?.collapse().paths.first;
  final byId = <String, SavedTextHighlight>{};
  final entries = <HighlightRangeEntry>[];
  for (final highlight in highlights) {
    if (highlight.id.isEmpty || highlight.cfi.trim().isEmpty) continue;
    final parsed = Cfi.tryParse(highlight.cfi);
    if (parsed == null || spine == null) continue;
    final paths = parsed.collapse().paths;
    if (paths.length < 2 ||
        CfiLocation([paths.first]) != CfiLocation([spine])) {
      continue;
    }
    try {
      entries.add((
        id: highlight.id,
        range: doc.textRangeOf(cfiToRange(doc, parsed)),
      ));
      byId[highlight.id] = highlight;
    } on CfiResolveException {
      continue;
    }
  }
  final plan = planHighlightMerge(doc, selection, entries);
  if (plan == null) return null;
  final ids = [for (final entry in plan.absorbed) entry.id];
  final sameAs = plan.sameAs;
  if (sameAs != null) {
    final saved = byId[sameAs.id]!;
    final text = saved.text;
    return TextHighlightMerge(
      cfi: saved.cfi,
      text: text != null && text.isNotEmpty
          ? text
          : textWithBlockBreaks(section, plan.range),
      highlightIds: ids,
    );
  }
  final same =
      doc.comparePoints(plan.range.start, selection.start) == 0 &&
      doc.comparePoints(plan.range.end, selection.end) == 0;
  return TextHighlightMerge(
    cfi: cfiOf(plan.range),
    text: same ? selectedText : textWithBlockBreaks(section, plan.range),
    highlightIds: ids,
  );
}

/// The text of [range] with a line break where it crosses into another
/// paragraph, as `rangeTextWithBlockBreaks` renders merged highlights:
/// the document's characters, not the shown ones. Raised text belongs to
/// its paragraph; text that is not shown joins the paragraph before it.
String textWithBlockBreaks(PreparedSection section, TextPointRange range) {
  final doc = section.document;
  final blocks = <int, int>{};
  var block = 0;
  for (final paragraph in section.boxes.paragraphs) {
    for (final node in paragraph.sourceMap.nodes) {
      blocks[node] ??= block;
    }
    for (final nested in paragraph.nestedParagraphs) {
      for (final node in nested.sourceMap.nodes) {
        blocks[node] ??= block;
      }
    }
    block++;
  }
  final out = StringBuffer();
  int? previous;
  doc.forEachTextIn(range, (node, from, to) {
    final here = blocks[node] ?? previous;
    if (previous != null && here != previous) out.write('\n');
    previous = here;
    out.write(doc.textOf(node).substring(from, to));
  });
  return out.toString();
}
