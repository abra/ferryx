/// [CfiDocument] over a `package:xml` tree, for XML content: EPUB XHTML
/// sections, FB2 and package documents. The adapter keeps the XML nodes
/// untouched and indexes ids once; it is what the format parsers and the
/// CFI tests resolve against.
library;

import 'package:xml/xml.dart';

import 'cfi_node.dart';

/// A CFI view of an [XmlDocument].
class XmlCfiDocument implements CfiDocument {
  XmlCfiDocument(this.document)
    : root = XmlCfiNode._(document.rootElement, null) {
    _index(root);
  }

  /// Parses [source] as XML and wraps it.
  factory XmlCfiDocument.parse(String source) =>
      XmlCfiDocument(XmlDocument.parse(source));

  final XmlDocument document;

  @override
  final XmlCfiNode root;

  final _byId = <String, XmlCfiNode>{};

  @override
  XmlCfiNode? elementById(String id) => _byId[id];

  /// The wrapper of [xml], an element or text node of [document], or
  /// null when it is not part of the tree CFIs see. A walk of the tree:
  /// cheap for package documents, not meant for every node of a section.
  XmlCfiNode? nodeFor(XmlNode xml) {
    XmlCfiNode? find(XmlCfiNode node) {
      if (identical(node.xml, xml)) return node;
      for (final child in node.children) {
        final found = find(child);
        if (found != null) return found;
      }
      return null;
    }

    return find(root);
  }

  void _index(XmlCfiNode node) {
    final id = node.id;
    if (id != null) _byId.putIfAbsent(id, () => node);
    for (final child in node.children) {
      if (child.isElement) _index(child);
    }
  }
}

/// A node of an [XmlCfiDocument]: the element or character data it wraps.
///
/// Children are built once per node and shared: a tree walk allocates one
/// wrapper per element or text node, nothing per step.
class XmlCfiNode implements CfiNode {
  XmlCfiNode._(this.xml, this.parent);

  /// The wrapped [XmlElement], [XmlText] or [XmlCDATA].
  final XmlNode xml;

  @override
  final XmlCfiNode? parent;

  @override
  bool get isElement => xml is XmlElement;

  @override
  bool get isText => !isElement;

  @override
  String? get id {
    final xml = this.xml;
    return xml is XmlElement ? xml.getAttribute('id') : null;
  }

  @override
  String? attribute(String name) {
    final xml = this.xml;
    return xml is XmlElement ? xml.getAttribute(name) : null;
  }

  @override
  String? get text {
    final xml = this.xml;
    return xml is XmlElement ? null : xml.value;
  }

  late final List<XmlCfiNode> _children = [
    for (final child in xml.children)
      if (child is XmlElement || child is XmlText || child is XmlCDATA)
        XmlCfiNode._(child, this),
  ];

  @override
  List<XmlCfiNode> get children => _children;

  @override
  String toString() {
    final xml = this.xml;
    if (xml is XmlElement) {
      final id = this.id;
      return '<${xml.name.local}${id == null ? '' : ' id="$id"'}>';
    }
    return '"${xml.value}"';
  }
}
