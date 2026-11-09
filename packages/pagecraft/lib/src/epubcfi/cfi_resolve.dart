/// CFIs to and from positions in a document: the `fromRange`, `toRange`,
/// `fromElements` and `toElement` of `epubcfi.js` over [CfiNode] trees.
///
/// The spec's step indexing drives everything: a parent's children are
/// seen as `[element, text, element, text, ..., element]`, so adjacent
/// text nodes merge into one odd-indexed chunk, a missing chunk between
/// two elements still counts, and index 0 and n+2 name the virtual
/// positions before the first and after the last child.
library;

import 'cfi.dart';
import 'cfi_node.dart';

/// The CFI of a point or range in a document.
///
/// With [filter], nodes the filter skips are transparent (their children
/// count as the parent's, foliate-js#100) and rejected ones are not
/// counted, both for the path and for the merged text offsets. The
/// result has no indirection: prefix it with the section's CFI through
/// [joinCfiIndirections].
Cfi cfiFromRange(CfiNodeRange range, {CfiNodeFilter? filter}) {
  final start = CfiLocation([_nodeToPath(range.start, filter)]);
  if (range.isCollapsed) return start;
  final end = CfiLocation([_nodeToPath(range.end, filter)]);
  return buildCfiRange(start, end);
}

/// The CFI of a point in a document; see [cfiFromRange].
Cfi cfiFromPoint(CfiPoint point, {CfiNodeFilter? filter}) =>
    cfiFromRange(CfiNodeRange(point, point), filter: filter);

/// Resolves the local path of [cfi] in [document].
///
/// A CFI with indirections resolves its last path; the earlier ones name
/// the package document and the spine, which the caller has already used
/// to pick [document]. Throws [CfiResolveException] when a step points
/// past the children that exist.
CfiNodeRange cfiToRange(
  CfiDocument document,
  Cfi cfi, {
  CfiNodeFilter? filter,
}) {
  final start = _pathToPoint(document, cfi.collapse().localPath, filter);
  final end = cfi is CfiRange
      ? _pathToPoint(document, cfi.collapse(toEnd: true).localPath, filter)
      : start;
  return CfiNodeRange(start, end);
}

/// The element the local path of [cfi] names, or the node its point is
/// in (`toElement`).
CfiNode cfiToElement(CfiDocument document, Cfi cfi, {CfiNodeFilter? filter}) =>
    _pathToPoint(document, cfi.collapse().localPath, filter).node;

/// CFIs for [elements], all children of one parent in document order
/// (`fromElements`): one walk of the parent instead of one per element.
List<Cfi> cfisFromElements(List<CfiNode> elements) {
  if (elements.isEmpty) return const [];
  final parent = elements.first.parent;
  if (parent == null) {
    throw ArgumentError('Elements need a parent to be indexed in');
  }
  final prefix = parent.parent == null
      ? const <CfiStep>[]
      : _nodeToPath(CfiPoint(parent, 0), null, keepOffset: false);
  final results = <Cfi>[];
  final indexed = _indexChildren(parent, null);
  for (var index = 0; index < indexed.length; index++) {
    if (results.length == elements.length) break;
    final entry = indexed[index];
    if (entry is _Element && identical(entry.node, elements[results.length])) {
      results.add(
        CfiLocation([
          [...prefix, CfiStep(index, id: _idOf(entry.node))],
        ]),
      );
    }
  }
  return results;
}

/// Thrown when a CFI names a child that the document does not have.
class CfiResolveException implements Exception {
  const CfiResolveException(this.message, this.cfiPath);

  final String message;
  final CfiPath cfiPath;

  @override
  String toString() => 'CfiResolveException: $message in $cfiPath';
}

// Indexing children the spec's way.

/// An entry in a parent's indexed children.
sealed class _Entry {
  const _Entry();
}

class _Element extends _Entry {
  const _Element(this.node);
  final CfiNode node;
}

/// One text chunk: the adjacent text nodes between two elements.
class _Chunk extends _Entry {
  const _Chunk(this.nodes);
  final List<CfiNode> nodes;

  int get length => nodes.fold(0, (sum, n) => sum + n.text!.length);
}

/// Index 0, the virtual position before the first child.
class _Before extends _Entry {
  const _Before();
}

/// Index n+2, the virtual position after the last child.
class _After extends _Entry {
  const _After();
}

/// A missing chunk: between two elements, or before the first element,
/// or after the last one.
class _Gap extends _Entry {
  const _Gap();
}

/// The nodes a CFI step counts under [node], flattening skipped ones.
List<CfiNode> _countedChildren(CfiNode node, CfiNodeFilter? filter) {
  if (filter == null) return node.children;
  final out = <CfiNode>[];
  for (final child in node.children) {
    switch (filter(child)) {
      case CfiNodeFilterResult.accept:
        out.add(child);
      case CfiNodeFilterResult.reject:
        break;
      case CfiNodeFilterResult.skip:
        out.addAll(_countedChildren(child, filter));
    }
  }
  return out;
}

/// `indexChildNodes`: `[before, (first gap), element, chunk-or-gap, ...,
/// element, (last gap), after]`, so an entry's position is its CFI step.
List<_Entry> _indexChildren(CfiNode node, CfiNodeFilter? filter) {
  final entries = <_Entry>[const _Before()];
  _Entry? last;
  for (final child in _countedChildren(node, filter)) {
    if (child.isElement) {
      if (last == null || last is _Element) entries.add(const _Gap());
      last = _Element(child);
      entries.add(last);
    } else {
      if (last is _Chunk) {
        last.nodes.add(child);
      } else {
        last = _Chunk([child]);
        entries.add(last);
      }
    }
  }
  if (last is _Element) entries.add(const _Gap());
  entries.add(const _After());
  return entries;
}

/// The nearest ancestor a step can name: skipped parents are
/// transparent, as in `logicalParentNode`.
CfiNode? _logicalParent(CfiNode node, CfiNodeFilter? filter) {
  var parent = node.parent;
  while (parent != null &&
      parent.parent != null &&
      filter != null &&
      filter(parent) == CfiNodeFilterResult.skip) {
    parent = parent.parent;
  }
  return parent;
}

String? _idOf(CfiNode node) {
  final id = node.id;
  return id == null || id.isEmpty ? null : id;
}

/// `nodeToParts`: the steps from the root down to [point]'s node, with
/// the offset merged across the chunk's text nodes.
CfiPath _nodeToPath(
  CfiPoint point,
  CfiNodeFilter? filter, {
  bool keepOffset = true,
}) {
  final steps = <CfiStep>[];
  var node = point.node;
  int? offset = keepOffset ? point.offset : null;
  while (true) {
    final parent = _logicalParent(node, filter);
    if (parent == null) break; // the root is never a step
    final indexed = _indexChildren(parent, filter);
    var index = -1;
    _Entry? entry;
    for (var i = 0; i < indexed.length; i++) {
      final e = indexed[i];
      if (e is _Element && identical(e.node, node) ||
          e is _Chunk && e.nodes.any((n) => identical(n, node))) {
        index = i;
        entry = e;
        break;
      }
    }
    if (index >= 0) {
      // "adjust offset as if merging the text nodes in the chunk"
      if (entry is _Chunk && offset != null) {
        var sum = 0;
        for (final n in entry.nodes) {
          if (identical(n, node)) {
            sum += offset;
            break;
          }
          sum += n.text!.length;
        }
        offset = sum;
      }
      steps.add(CfiStep(index, id: _idOf(node), offset: offset));
    }
    // Rejected nodes have no index and no step (epubcfi.js drops them).
    offset = null;
    node = parent;
  }
  return steps.reversed.toList(growable: false);
}

/// `partsToNode`: walks [path] down from the root. An id assertion on the
/// last step wins when the document has that element, as in epubcfi.js.
CfiPoint _pathToPoint(
  CfiDocument document,
  CfiPath path,
  CfiNodeFilter? filter,
) {
  if (path.isEmpty) return CfiPoint(document.root, 0);
  final lastId = path.last.id;
  if (lastId != null) {
    final element = document.elementById(lastId);
    if (element != null) return CfiPoint(element, 0);
  }
  CfiNode node = document.root;
  _Entry? landed;
  for (final step in path) {
    final indexed = _indexChildren(node, filter);
    if (step.index < 0 || step.index >= indexed.length) {
      throw CfiResolveException(
        'Step ${step.index} of ${indexed.length} entries',
        path,
      );
    }
    final entry = indexed[step.index];
    switch (entry) {
      case _Before():
        // Index 0: before the node, as a DOM range set before it.
        return _beside(node, after: false);
      case _After():
        return _beside(node, after: true);
      case _Gap():
        // A chunk that does not exist. At the edges epubcfi.js lands on
        // the first or last child; between two elements the point is
        // between them.
        final children = node.children;
        if (children.isEmpty) return CfiPoint(node, 0);
        if (step.index == 1) return CfiPoint(children.first, 0);
        if (step.index == indexed.length - 2) {
          return CfiPoint(children.last, 0);
        }
        final next = (indexed[step.index + 1] as _Element).node;
        return CfiPoint(node, children.indexOf(next));
      case _Element():
        node = entry.node;
        landed = entry;
      case _Chunk():
        landed = entry;
        node = entry.nodes.first;
        // A step below a text chunk cannot exist; stop here.
        if (!identical(step, path.last)) {
          throw CfiResolveException('Step below character data', path);
        }
    }
  }
  final offset = path.last.offset ?? 0;
  if (landed is _Chunk) {
    var sum = 0;
    for (final n in landed.nodes) {
      final length = n.text!.length;
      if (sum + length >= offset) return CfiPoint(n, offset - sum);
      sum += length;
    }
    final last = landed.nodes.last;
    return CfiPoint(last, last.text!.length);
  }
  return CfiPoint(node, offset);
}

/// The boundary just before or after [node] in its parent, as a DOM
/// range's `setStartBefore`/`setStartAfter`; the root has no parent, so
/// its own edges stand in.
CfiPoint _beside(CfiNode node, {required bool after}) {
  final parent = node.parent;
  if (parent == null) return CfiPoint(node, after ? node.children.length : 0);
  final index = parent.children.indexOf(node);
  return CfiPoint(parent, after ? index + 1 : index);
}
