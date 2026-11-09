import 'dart:isolate';

import '../document/content_document.dart';
import '../document/text_point.dart';
import '../epubcfi/cfi.dart';
import '../epubcfi/cfi_resolve.dart';
import '../search/text_node_search.dart';
import 'section_preparer.dart';
import 'text_book_source.dart';

/// A match in a book: its full CFI range and its excerpt.
class TextSearchHit {
  const TextSearchHit({
    required this.cfi,
    required this.pre,
    required this.match,
    required this.post,
  });

  final String cfi;
  final String pre;
  final String match;
  final String post;

  @override
  String toString() => 'TextSearchHit($cfi "$pre[$match]$post")';
}

/// What a book search reports, in order: each section's hits (in batches
/// of at most 64), the fraction of sections searched after each one, and
/// [TextSearchDone] at the end, as foliate-js's `view.search` yields.
sealed class TextSearchEvent {
  const TextSearchEvent();
}

class TextSearchResults extends TextSearchEvent {
  const TextSearchResults(this.section, this.hits);

  final int section;
  final List<TextSearchHit> hits;
}

class TextSearchProgress extends TextSearchEvent {
  const TextSearchProgress(this.fraction);

  final double fraction;
}

class TextSearchDone extends TextSearchEvent {
  const TextSearchDone();
}

/// Searches [source] for [query]: the whole book, or only section
/// [section] (then without progress). Sections are parsed and searched
/// in background isolates, [parallel] at a time, and reported in order.
/// [locale] is the book's language, for documents that do not state
/// theirs. Cancelling the subscription stops the search after the
/// sections already started.
Stream<TextSearchEvent> searchTextBook(
  TextBookSource source,
  String query, {
  int? section,
  String locale = 'en',
  int parallel = 3,
}) async* {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    yield const TextSearchDone();
    return;
  }
  Future<List<TextSearchHit>> searchSection(int index) async {
    final text = await source.section(index);
    return _searchInIsolate(
      text.text,
      text.mediaType,
      trimmed,
      source.sectionCfi(index),
      locale,
    );
  }

  if (section != null) {
    final hits = await searchSection(section);
    for (var i = 0; i < hits.length; i += 64) {
      yield TextSearchResults(
        section,
        hits.sublist(i, _min(i + 64, hits.length)),
      );
    }
    yield const TextSearchDone();
    return;
  }
  final count = source.sectionCount;
  final pending = <Future<List<TextSearchHit>>>[];
  var next = 0;
  void fill() {
    while (next < count && pending.length < parallel) {
      pending.add(searchSection(next++));
    }
  }

  fill();
  for (var index = 0; index < count; index++) {
    final hits = await pending.removeAt(0);
    fill();
    for (var i = 0; i < hits.length; i += 64) {
      yield TextSearchResults(
        index,
        hits.sublist(i, _min(i + 64, hits.length)),
      );
    }
    yield TextSearchProgress((index + 1) / count);
  }
  yield const TextSearchDone();
}

int _min(int a, int b) => a < b ? a : b;

/// Top level, so the isolate's closure holds only these values, not the
/// search's state.
Future<List<TextSearchHit>> _searchInIsolate(
  String text,
  String? mediaType,
  String query,
  String sectionCfi,
  String locale,
) => Isolate.run(
  () => searchSectionText(
    text,
    query: query,
    sectionCfi: sectionCfi,
    mediaType: mediaType,
    locale: locale,
  ),
);

/// The hits of [query] in a section's markup [text], whose own CFI is
/// [sectionCfi]: what [searchTextBook] runs in an isolate.
List<TextSearchHit> searchSectionText(
  String text, {
  required String query,
  required String sectionCfi,
  String? mediaType,
  String locale = 'en',
}) {
  final doc = parseSectionDocument(text, mediaType: mediaType);
  return searchSectionDocument(
    doc,
    query: query,
    sectionCfi: sectionCfi,
    locale: locale,
  );
}

/// The hits of [query] in [doc]'s text, as foliate-js's text walker
/// gathers it: every text node under the body, in order, leaving out
/// scripts and styles.
List<TextSearchHit> searchSectionDocument(
  ContentDocument doc, {
  required String query,
  required String sectionCfi,
  String locale = 'en',
}) {
  final root = _bodyOf(doc);
  final nodes = <int>[];
  final end = doc.subtreeEndOf(root);
  for (var i = root; i < end; i++) {
    if (doc.isText(i)) {
      nodes.add(i);
    } else {
      final name = doc.localNameOf(i);
      if (name == 'script' || name == 'style') i = doc.subtreeEndOf(i) - 1;
    }
  }
  final matches = searchTextNodes(
    [for (final node in nodes) doc.textOf(node)],
    query,
    locale: _languageOf(doc, root) ?? locale,
  );
  return [
    for (final m in matches)
      TextSearchHit(
        cfi: joinCfiIndirections([
          sectionCfi,
          cfiFromRange(
            doc.cfiRangeOf(
              TextPointRange(
                TextPoint(nodes[m.startIndex], m.startOffset),
                TextPoint(nodes[m.endIndex], m.endOffset),
              ),
            ),
          ).toInnerString(),
        ]),
        pre: m.pre,
        match: m.match,
        post: m.post,
      ),
  ];
}

int _bodyOf(ContentDocument doc) {
  for (final child in doc.childrenOf(0)) {
    if (!doc.isText(child) && doc.localNameOf(child) == 'body') return child;
  }
  return 0;
}

/// `doc.body.lang || doc.documentElement.lang`.
String? _languageOf(ContentDocument doc, int body) {
  for (final element in [body, 0]) {
    final lang = doc.attributeOf(element, 'lang');
    if (lang != null && lang.isNotEmpty) return lang;
  }
  return null;
}
