part of 'content_document.dart';

/// Builds the arena in document order. Growable lists while parsing, one
/// copy into typed arrays at the end.
class _ContentDocumentBuilder {
  final _kinds = <int>[];
  final _parents = <int>[];
  final _firstChildren = <int>[];
  final _lastChildren = <int>[];
  final _nextSiblings = <int>[];
  final _previousSiblings = <int>[];
  final _childCounts = <int>[];
  final _names = <int>[];
  final _attributeStarts = <int>[];
  final _attributeCounts = <int>[];
  final _qualifiedNames = <String>[];
  final _localNames = <String>[];
  final _nameIds = <String, int>{};
  final _attributeNames = <String>[];
  final _attributeValues = <String>[];
  final _texts = <String>[];
  final _ids = <String, int>{};

  /// The element being filled, or [ContentDocument.none] before the root.
  int _open = ContentDocument.none;

  bool get hasRoot => _kinds.isNotEmpty;

  bool get isOpen => _open != ContentDocument.none;

  int _nameId(String qualified) => _nameIds.putIfAbsent(qualified, () {
    _qualifiedNames.add(qualified);
    final colon = qualified.indexOf(':');
    _localNames.add(colon < 0 ? qualified : qualified.substring(colon + 1));
    return _qualifiedNames.length - 1;
  });

  int _append(int kind, int name) {
    final index = _kinds.length;
    _kinds.add(kind);
    _parents.add(_open);
    _firstChildren.add(ContentDocument.none);
    _lastChildren.add(ContentDocument.none);
    _nextSiblings.add(ContentDocument.none);
    _previousSiblings.add(ContentDocument.none);
    _childCounts.add(0);
    _names.add(name);
    _attributeStarts.add(_attributeNames.length);
    _attributeCounts.add(0);
    if (_open != ContentDocument.none) {
      final last = _lastChildren[_open];
      if (last == ContentDocument.none) {
        _firstChildren[_open] = index;
      } else {
        _nextSiblings[last] = index;
        _previousSiblings[index] = last;
      }
      _lastChildren[_open] = index;
      _childCounts[_open]++;
    }
    return index;
  }

  /// Opens an element; [attributes] are name–value pairs in document
  /// order, already normalized by the parser.
  void startElement(String qualified, Iterable<(String, String)> attributes) {
    final index = _append(0, _nameId(qualified));
    for (final (name, value) in attributes) {
      _attributeNames.add(name);
      _attributeValues.add(value);
      _attributeCounts[index]++;
      if (name == 'id') _ids.putIfAbsent(value, () => index);
    }
    _open = index;
  }

  void endElement() {
    _open = _parents[_open];
  }

  void text(String data, {bool cdata = false}) {
    if (_open == ContentDocument.none) return;
    _texts.add(data);
    _append(cdata ? 2 : 1, _texts.length - 1);
  }

  ContentDocument build() => ContentDocument._(
    kinds: Uint8List.fromList(_kinds),
    parents: Int32List.fromList(_parents),
    firstChildren: Int32List.fromList(_firstChildren),
    lastChildren: Int32List.fromList(_lastChildren),
    nextSiblings: Int32List.fromList(_nextSiblings),
    previousSiblings: Int32List.fromList(_previousSiblings),
    childCounts: Int32List.fromList(_childCounts),
    names: Int32List.fromList(_names),
    attributeStarts: Int32List.fromList(_attributeStarts),
    attributeCounts: Int32List.fromList(_attributeCounts),
    qualifiedNames: _qualifiedNames,
    localNames: _localNames,
    attributeNames: _attributeNames,
    attributeValues: _attributeValues,
    texts: _texts,
    ids: _ids,
  );
}
