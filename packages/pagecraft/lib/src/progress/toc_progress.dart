/// Which table of contents (or page list) entry the reader is in:
/// foliate-js's `TOCProgress` (`progress.js`), with anchors resolved in
/// pagecraft's documents instead of DOM ranges.
library;

import '../document/content_document.dart';
import '../document/text_point.dart';
import '../formats/book_navigation.dart';
import '../text_book/text_anchor.dart';

class TocProgress {
  TocProgress._(this._groups);

  /// Groups the entries of [toc] by the section they point into
  /// ([resolve] is the book's `resolveHref`). A section with no entries
  /// of its own belongs to the last entry of the section before it.
  static Future<TocProgress> build(
    List<BookNavItem> toc, {
    required int sectionCount,
    required Future<TextTarget?> Function(String href) resolve,
  }) async {
    final flat = <BookNavItem>[];
    void walk(List<BookNavItem> items) {
      for (final item in items) {
        flat.add(item);
        final sub = item.subitems;
        if (sub != null) walk(sub);
      }
    }

    walk(toc);
    final bySection = <int, _Group>{};
    for (var i = 0; i < flat.length; i++) {
      final item = flat[i];
      final href = item.href;
      if (href == null) continue;
      final target = await resolve(href);
      if (target == null) continue;
      final group = bySection.putIfAbsent(
        target.index,
        () => _Group(prev: i > 0 ? flat[i - 1] : null),
      );
      group.items.add((anchor: target.anchor, item: item));
    }
    final groups = List<_Group?>.filled(sectionCount, null);
    for (var i = 0; i < sectionCount; i++) {
      final own = bySection[i];
      if (own != null) {
        groups[i] = own;
      } else if (i > 0 && groups[i - 1] != null) {
        groups[i] = groups[i - 1]!.carried();
      }
    }
    return TocProgress._(groups);
  }

  final List<_Group?> _groups;

  /// The entry section [index] is in when what is shown of [document]
  /// ends at [end] (null for the section's start): the last entry whose
  /// anchor is not after it, so a heading on the page names the page.
  BookNavItem? itemAt(int index, {ContentDocument? document, TextPoint? end}) {
    if (index < 0 || index >= _groups.length) return null;
    final group = _groups[index];
    if (group == null) return null;
    final items = group.items;
    if (items.isEmpty) return group.prev;
    if (group.isCarried) return items.last.item;
    if (document == null ||
        end == null ||
        (items.length == 1 && items.first.anchor == null)) {
      return items.first.item;
    }
    final nodes = group.nodesIn(document);
    for (var i = 0; i < items.length; i++) {
      final el = nodes[i];
      if (el < 0) continue;
      if (document.comparePoints(TextPoint(el, 0), end) > 0) {
        return i > 0 ? items[i - 1].item : group.prev;
      }
    }
    return items.last.item;
  }
}

class _Group {
  _Group({this.prev, List<({TextAnchor? anchor, BookNavItem item})>? items})
    : items = items ?? [];

  final BookNavItem? prev;
  final List<({TextAnchor? anchor, BookNavItem item})> items;
  bool isCarried = false;

  /// Anchor nodes cached for the document they were found in.
  ContentDocument? _document;
  List<int> _nodes = const [];

  _Group carried() => _Group(prev: prev, items: items)..isCarried = true;

  List<int> nodesIn(ContentDocument document) {
    if (!identical(document, _document)) {
      _document = document;
      _nodes = [for (final i in items) i.anchor?.find(document) ?? -1];
    }
    return _nodes;
  }
}
