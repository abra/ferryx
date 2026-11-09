/// The slice of a document tree that CFIs address.
///
/// `epubcfi.js` walks the browser's DOM; pagecraft walks whatever tree a
/// format produced, so the CFI code sees documents only through this
/// contract. A tree of elements and character data is enough: CFI steps
/// count children ("content other than element and character data is
/// ignored"), offsets count characters, assertions read ids.
library;

/// A node a CFI step can land on: an element or character data.
///
/// Implementations expose only element and text children in [children];
/// comments and processing instructions are left out, as the CFI
/// indexing ignores them anyway. [parent] is null for the root.
abstract interface class CfiNode {
  bool get isElement;

  /// Whether this is character data (text or CDATA).
  bool get isText => !isElement;

  /// The element's `id`, or null for text and elements without one.
  String? get id;

  /// The element's attribute [name], or null when absent or on text.
  /// Filters read the markers a format sets on nodes to skip.
  String? attribute(String name);

  /// Character data of a text node, or null for an element.
  String? get text;

  List<CfiNode> get children;

  CfiNode? get parent;
}

/// A document: a root element and id lookup.
abstract interface class CfiDocument {
  CfiNode get root;

  /// The element with [id], or null.
  CfiNode? elementById(String id);
}

/// What a node filter decides for a node (`NodeFilter` in the DOM):
/// [reject] drops the node with its subtree, [skip] drops the node but
/// keeps its children as if they were its parent's, [accept] keeps it.
enum CfiNodeFilterResult { accept, reject, skip }

/// A node filter, applied to every element and text node a CFI step could
/// name, as `epubcfi.js` applies the `filter` argument.
typedef CfiNodeFilter = CfiNodeFilterResult Function(CfiNode node);

/// A boundary point in a document: [node] with a character [offset] for
/// text, or a child [offset] for an element, as a DOM `Range` boundary.
class CfiPoint {
  const CfiPoint(this.node, this.offset);

  final CfiNode node;
  final int offset;

  @override
  bool operator ==(Object other) =>
      other is CfiPoint &&
      identical(other.node, node) &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(identityHashCode(node), offset);

  @override
  String toString() => 'CfiPoint($node, $offset)';
}

/// A resolved range: two boundary points in the same document.
class CfiNodeRange {
  const CfiNodeRange(this.start, this.end);

  final CfiPoint start;
  final CfiPoint end;

  bool get isCollapsed => start == end;

  @override
  bool operator ==(Object other) =>
      other is CfiNodeRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'CfiNodeRange($start, $end)';
}
