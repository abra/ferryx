/// The document tree of a section: what the browser's DOM was to
/// foliate-js, for the layout, CFI, search and highlight code.
///
/// The tree is an arena: every node is an index into parallel typed
/// arrays (kind, parent, first child, next sibling, name, attributes),
/// so a 100 KB chapter costs a few hundred kilobytes and a walk
/// allocates nothing. [ContentNode] views are made on demand and cached,
/// one per node at most, for callers that want objects, such as the CFI
/// code through [CfiNode].
///
/// Only elements and character data are kept, as CFI indexing sees them:
/// comments and processing instructions are dropped, namespace
/// declarations are not attributes, adjacent text and CDATA stay
/// separate nodes as the browser keeps them. Parsing applies what the
/// browser's parsers apply: line breaks fold to `\n`, XML attribute
/// values fold line breaks and tabs to spaces, and XHTML knows the HTML
/// named entities (`&nbsp;`).
library;

import 'dart:typed_data';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart'
    show XmlDefaultEntityMapping, XmlException, XmlNullEntityMapping;
import 'package:xml/xml_events.dart' as xml_events;

import '../epubcfi/cfi_node.dart';
import '../pagecraft_exception.dart';

part 'content_document_builder.dart';
part 'content_document_parser.dart';
part 'content_node.dart';

/// The kind of a node.
enum ContentNodeKind {
  element,

  /// A text node.
  text,

  /// A CDATA section: character data the CFI code treats as text, kept
  /// apart because the browser keeps it apart.
  cdata,
}

/// A parse failure: the markup was not well formed.
class ContentParseException extends PagecraftException {
  const ContentParseException(super.message);
}

/// A parsed section. See the library comment.
class ContentDocument implements CfiDocument {
  ContentDocument._({
    required Uint8List kinds,
    required Int32List parents,
    required Int32List firstChildren,
    required Int32List lastChildren,
    required Int32List nextSiblings,
    required Int32List previousSiblings,
    required Int32List childCounts,
    required Int32List names,
    required Int32List attributeStarts,
    required Int32List attributeCounts,
    required List<String> qualifiedNames,
    required List<String> localNames,
    required List<String> attributeNames,
    required List<String> attributeValues,
    required List<String> texts,
    required Map<String, int> ids,
  }) : _kinds = kinds,
       _parents = parents,
       _firstChildren = firstChildren,
       _lastChildren = lastChildren,
       _nextSiblings = nextSiblings,
       _previousSiblings = previousSiblings,
       _childCounts = childCounts,
       _names = names,
       _attributeStarts = attributeStarts,
       _attributeCounts = attributeCounts,
       _qualifiedNames = qualifiedNames,
       _localNames = localNames,
       _attributeNames = attributeNames,
       _attributeValues = attributeValues,
       _texts = texts,
       _ids = ids,
       _views = List<ContentNode?>.filled(kinds.length, null);

  /// Parses XML (XHTML sections, FB2 output, package documents). Throws
  /// [ContentParseException] when it is not well formed.
  factory ContentDocument.parseXml(String source) => _parseXml(source);

  /// Parses HTML with the HTML5 algorithm, as the browser parses
  /// `text/html` sections and MOBI 6 text: the tree gains the implied
  /// `html`, `head` and `body`, and never fails.
  factory ContentDocument.parseHtml(String source) => _parseHtml(source);

  /// Parses by [mediaType]: `text/html` with the HTML parser, anything
  /// else as XML.
  factory ContentDocument.parse(String source, {String? mediaType}) =>
      mediaType == 'text/html'
      ? ContentDocument.parseHtml(source)
      : ContentDocument.parseXml(source);

  /// The index that means "no node": no parent, child or sibling.
  static const int none = -1;

  final Uint8List _kinds;
  final Int32List _parents;
  final Int32List _firstChildren;
  final Int32List _lastChildren;
  final Int32List _nextSiblings;
  final Int32List _previousSiblings;

  /// Each element's 1-based position among its parent's element
  /// children, and each node's element child count: built on first use,
  /// for structural selectors.
  Int32List? _elementIndices;
  Int32List? _elementChildCounts;
  final Int32List _childCounts;

  /// Elements: an index into [_qualifiedNames]; text: into [_texts].
  final Int32List _names;
  final Int32List _attributeStarts;
  final Int32List _attributeCounts;
  final List<String> _qualifiedNames;
  final List<String> _localNames;
  final List<String> _attributeNames;
  final List<String> _attributeValues;
  final List<String> _texts;
  final Map<String, int> _ids;
  final List<ContentNode?> _views;

  /// The root element's index: always 0.
  static const int rootIndex = 0;

  int get nodeCount => _kinds.length;

  ContentNodeKind kindOf(int node) => ContentNodeKind.values[_kinds[node]];

  bool isElement(int node) => _kinds[node] == 0;

  /// Text or CDATA.
  bool isText(int node) => _kinds[node] != 0;

  int parentOf(int node) => _parents[node];

  int firstChildOf(int node) => _firstChildren[node];

  int lastChildOf(int node) => _lastChildren[node];

  int nextSiblingOf(int node) => _nextSiblings[node];

  int previousSiblingOf(int node) => _previousSiblings[node];

  /// The element sibling before [node], or [none].
  int previousElementSiblingOf(int node) {
    var s = _previousSiblings[node];
    while (s != none && _kinds[s] != 0) {
      s = _previousSiblings[s];
    }
    return s;
  }

  /// The element sibling after [node], or [none].
  int nextElementSiblingOf(int node) {
    var s = _nextSiblings[node];
    while (s != none && _kinds[s] != 0) {
      s = _nextSiblings[s];
    }
    return s;
  }

  /// [element]'s 1-based position among its parent's element children
  /// (`:nth-child`); 1 for the root.
  int elementIndexOf(int element) {
    _indexElements();
    return _elementIndices![element];
  }

  /// How many element children [node] has (`:nth-last-child`).
  int elementChildCountOf(int node) {
    _indexElements();
    return _elementChildCounts![node];
  }

  void _indexElements() {
    if (_elementIndices != null) return;
    final indices = Int32List(_kinds.length);
    final counts = Int32List(_kinds.length);
    for (var n = 0; n < _kinds.length; n++) {
      if (_kinds[n] != 0) continue;
      final parent = _parents[n];
      if (parent == none) {
        indices[n] = 1;
      } else {
        indices[n] = ++counts[parent];
      }
    }
    _elementIndices = indices;
    _elementChildCounts = counts;
  }

  int childCountOf(int node) => _childCounts[node];

  /// The [index]th child of [node]; a walk along the siblings.
  int childAt(int node, int index) {
    var child = _firstChildren[node];
    for (var i = 0; i < index && child != none; i++) {
      child = _nextSiblings[child];
    }
    return child;
  }

  /// The children of [node], in order.
  Iterable<int> childrenOf(int node) sync* {
    for (var c = _firstChildren[node]; c != none; c = _nextSiblings[c]) {
      yield c;
    }
  }

  /// [node] and everything below it, in document order.
  ///
  /// Nodes are stored in document (pre-)order, so a subtree is the index
  /// range from [node] to [subtreeEndOf]: no recursion, no allocation
  /// per node.
  Iterable<int> descendantsOf(int node) {
    final end = subtreeEndOf(node);
    return Iterable<int>.generate(end - node, (i) => node + i);
  }

  /// The index just past the last node of [node]'s subtree.
  int subtreeEndOf(int node) {
    var last = node;
    for (var c = _lastChildren[last]; c != none; c = _lastChildren[last]) {
      last = c;
    }
    return last + 1;
  }

  /// The element's name as written, with its prefix (`svg:rect`).
  String qualifiedNameOf(int node) => _qualifiedNames[_names[node]];

  /// The element's name without a prefix: what CSS selectors match.
  String localNameOf(int node) => _localNames[_names[node]];

  /// The character data of a text or CDATA node.
  String textOf(int node) => _texts[_names[node]];

  int attributeCountOf(int node) => _attributeCounts[node];

  /// The element's attribute [name] (qualified, as written: `epub:type`),
  /// or null when absent or on text. Attributes the reader added
  /// ([addClass], [addAttributeIfAbsent]) count.
  String? attributeOf(int node, String name) {
    if (_added.isNotEmpty) {
      final added = _added[node]?[name];
      if (added != null) return added;
    }
    final start = _attributeStarts[node];
    final end = start + _attributeCounts[node];
    for (var i = start; i < end; i++) {
      if (_attributeNames[i] == name) return _attributeValues[i];
    }
    return null;
  }

  /// The element's attributes in document order, then those the reader
  /// added.
  Iterable<(String name, String value)> attributesOf(int node) sync* {
    final added = _added.isEmpty ? null : _added[node];
    final start = _attributeStarts[node];
    final end = start + _attributeCounts[node];
    for (var i = start; i < end; i++) {
      final name = _attributeNames[i];
      yield (name, added?[name] ?? _attributeValues[i]);
    }
    if (added == null) return;
    for (final MapEntry(:key, :value) in added.entries) {
      if (!_hasOwnAttribute(node, key)) yield (key, value);
    }
  }

  /// What the reader adds for presentation, as the WebView reader's
  /// normalizer does to a loaded section: a class, the book's language
  /// and direction. Never part of the text, ids or CFIs.
  final _added = <int, Map<String, String>>{};

  bool _hasOwnAttribute(int node, String name) {
    final start = _attributeStarts[node];
    final end = start + _attributeCounts[node];
    for (var i = start; i < end; i++) {
      if (_attributeNames[i] == name) return true;
    }
    return false;
  }

  /// Adds class [name] to [element]'s classes.
  void addClass(int element, String name) {
    final classes = attributeOf(element, 'class');
    if (classes != null && classes.split(RegExp(r'\s+')).contains(name)) {
      return;
    }
    (_added[element] ??= {})['class'] = classes == null || classes.isEmpty
        ? name
        : '$classes $name';
  }

  /// Gives [element] attribute [name] unless it has one.
  void addAttributeIfAbsent(int element, String name, String value) {
    if (attributeOf(element, name) != null) return;
    (_added[element] ??= {})[name] = value;
  }

  String? idOf(int node) => attributeOf(node, 'id');

  /// The first element with [id], or [none].
  int elementIndexById(String id) => _ids[id] ?? none;

  /// The concatenated character data below [node].
  String textContentOf(int node) {
    final buffer = StringBuffer();
    for (final n in descendantsOf(node)) {
      if (_kinds[n] != 0) buffer.write(_texts[_names[n]]);
    }
    return buffer.toString();
  }

  /// The object view of [node], the same object every time.
  ContentNode node(int index) => _views[index] ??= ContentNode._(this, index);

  @override
  ContentNode get root => node(rootIndex);

  @override
  ContentNode? elementById(String id) {
    final index = _ids[id];
    return index == null ? null : node(index);
  }
}
