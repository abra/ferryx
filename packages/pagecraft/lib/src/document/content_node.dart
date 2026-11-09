part of 'content_document.dart';

/// An object view of one node of a [ContentDocument]: the [CfiNode] the
/// CFI code walks. Identity is per node, so [CfiPoint] comparisons hold.
class ContentNode implements CfiNode {
  ContentNode._(this.document, this.index);

  final ContentDocument document;
  final int index;

  ContentNodeKind get kind => document.kindOf(index);

  @override
  bool get isElement => document.isElement(index);

  @override
  bool get isText => document.isText(index);

  @override
  String? get id => isElement ? document.idOf(index) : null;

  @override
  String? attribute(String name) =>
      isElement ? document.attributeOf(index, name) : null;

  @override
  String? get text => isElement ? null : document.textOf(index);

  /// The element's local name, or null for text.
  String? get localName => isElement ? document.localNameOf(index) : null;

  @override
  ContentNode? get parent {
    final parent = document.parentOf(index);
    return parent == ContentDocument.none ? null : document.node(parent);
  }

  late final List<ContentNode> _children = List.unmodifiable([
    for (final child in document.childrenOf(index)) document.node(child),
  ]);

  @override
  List<ContentNode> get children => _children;

  @override
  String toString() {
    if (isElement) {
      final id = this.id;
      return '<${document.localNameOf(index)}${id == null ? '' : ' id="$id"'}>';
    }
    return '"${document.textOf(index)}"';
  }
}
