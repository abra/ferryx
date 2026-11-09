import '../css/css_selector.dart';
import '../document/content_document.dart';

/// Where in a section a link or a table of contents entry points: what
/// foliate-js's `resolveHref` returns as an `anchor` function, as data.
sealed class TextAnchor {
  const TextAnchor();

  /// An element by `id` (EPUB fragments, MOBI 6 `filepos` anchors).
  const factory TextAnchor.id(String id) = IdAnchor;

  /// The first element a selector matches (KF8 `kindle:pos` targets).
  const factory TextAnchor.selector(String selector) = SelectorAnchor;

  /// The first element with an attribute value (FB2 title ids).
  const factory TextAnchor.attribute(String name, String value) =
      AttributeAnchor;

  /// The element's node in [document], or -1.
  int find(ContentDocument document);
}

class IdAnchor extends TextAnchor {
  const IdAnchor(this.id);

  final String id;

  @override
  int find(ContentDocument document) => document.elementIndexById(id);

  @override
  String toString() => '#$id';
}

class SelectorAnchor extends TextAnchor {
  const SelectorAnchor(this.selector);

  final String selector;

  @override
  int find(ContentDocument document) {
    final list = CssSelectorList.parseText(selector);
    if (list == null) return -1;
    for (var n = 0; n < document.nodeCount; n++) {
      if (!document.isElement(n)) continue;
      for (final s in list.selectors) {
        if (s.matches(document, n)) return n;
      }
    }
    return -1;
  }

  @override
  String toString() => selector;
}

class AttributeAnchor extends TextAnchor {
  const AttributeAnchor(this.name, this.value);

  final String name;
  final String value;

  @override
  int find(ContentDocument document) {
    for (var n = 0; n < document.nodeCount; n++) {
      if (document.isElement(n) && document.attributeOf(n, name) == value) {
        return n;
      }
    }
    return -1;
  }

  @override
  String toString() => '[$name="$value"]';
}

/// A section and, inside it, an anchor (null: the section's start).
class TextTarget {
  const TextTarget(this.index, [this.anchor]);

  final int index;
  final TextAnchor? anchor;

  @override
  String toString() => 'TextTarget($index, $anchor)';
}
