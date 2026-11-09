/// Liang's hyphenation (the TeX algorithm) over [HyphenationPatterns]:
/// where a word may break, as the patterns' odd values say, within the
/// language's limits and the caller's. Pure Dart.
library;

import 'dart:collection';
import 'dart:typed_data';

import 'hyphenation_patterns.dart';

/// The breaks of one language's words.
class Hyphenator {
  Hyphenator._(this.patterns, this._trie, this._exceptions);

  /// Builds a trie of [patterns] (`a1b2c`: letters `abc` and the values
  /// between them) in one pass over the text, into typed arrays: a
  /// section's isolate builds it in a few milliseconds, and lookups
  /// allocate nothing.
  factory Hyphenator(HyphenationPatterns patterns) {
    final exceptions = HashMap<String, List<int>>();
    for (final word in patterns.exceptions.split(_space)) {
      if (word.isEmpty) continue;
      final breaks = <int>[];
      final letters = StringBuffer();
      for (final rune in word.runes) {
        if (rune == 0x2D) {
          breaks.add(letters.length);
        } else {
          letters.writeCharCode(rune);
        }
      }
      exceptions[letters.toString()] = breaks;
    }
    return Hyphenator._(
      patterns,
      _PatternTrie.parse(patterns.patterns),
      exceptions,
    );
  }

  /// The hyphenator for [language], built once per isolate; null when the
  /// reader does not hyphenate it.
  static Hyphenator? forLanguage(String? language) {
    final patterns = hyphenationPatternsFor(language);
    return patterns == null
        ? null
        : _built.putIfAbsent(patterns, () => Hyphenator(patterns));
  }

  static final _built = HashMap<HyphenationPatterns, Hyphenator>.identity();

  static final _space = RegExp(r'\s+');

  final HyphenationPatterns patterns;
  final _PatternTrie _trie;
  final Map<String, List<int>> _exceptions;

  /// Words' breaks within the limits last asked for.
  final _cache = HashMap<String, List<int>>();
  var _cachedBefore = -1;
  var _cachedAfter = -1;
  static const _cacheSize = 4096;

  /// Where [word] (letters only) may break: offsets before which a hyphen
  /// may go, at least [minBefore] letters from its start and [minAfter]
  /// from its end, and never closer than the language allows.
  List<int> breaks(String word, {int minBefore = 2, int minAfter = 2}) {
    final before = minBefore > patterns.left ? minBefore : patterns.left;
    final after = minAfter > patterns.right ? minAfter : patterns.right;
    if (word.length < before + after) return const [];
    if (before != _cachedBefore || after != _cachedAfter) {
      _cache.clear();
      _cachedBefore = before;
      _cachedAfter = after;
    }
    final cached = _cache[word];
    if (cached != null) return cached;
    final lower = word.toLowerCase();
    final all = _exceptions[lower] ?? _trie.breaks(lower);
    final found = [
      for (final at in all)
        if (at >= before && word.length - at >= after) at,
    ];
    // Books repeat their words: a full cache starts over.
    if (_cache.length >= _cacheSize) _cache.clear();
    return _cache[word] = found.isEmpty ? const [] : found;
  }
}

/// Liang patterns as a trie over UTF-16 code units: per node its unit,
/// first child, next sibling and the offset of its pattern's values
/// (-1: no pattern ends there).
class _PatternTrie {
  _PatternTrie._(
    this._unit,
    this._child,
    this._sibling,
    this._value,
    this._values,
  );

  factory _PatternTrie.parse(String text) {
    var capacity = 1024;
    var unit = Uint16List(capacity);
    var child = Int32List(capacity)..fillRange(0, capacity, -1);
    var sibling = Int32List(capacity)..fillRange(0, capacity, -1);
    var value = Int32List(capacity)..fillRange(0, capacity, -1);
    var nodes = 1;
    // Copies each pattern's digits: the buffer is reused.
    final values = BytesBuilder();
    final digits = Uint8List(64);

    int add(int parent, int code) {
      if (nodes == capacity) {
        final grown = capacity * 2;
        unit = Uint16List(grown)..setRange(0, capacity, unit);
        child = (Int32List(grown)..fillRange(0, grown, -1))
          ..setRange(0, capacity, child);
        sibling = (Int32List(grown)..fillRange(0, grown, -1))
          ..setRange(0, capacity, sibling);
        value = (Int32List(grown)..fillRange(0, grown, -1))
          ..setRange(0, capacity, value);
        capacity = grown;
      }
      final node = nodes++;
      unit[node] = code;
      sibling[node] = child[parent];
      child[parent] = node;
      return node;
    }

    var node = 0;
    var letters = 0;
    void finish() {
      if (letters == 0) return;
      value[node] = values.length;
      values.add(Uint8List.sublistView(digits, 0, letters + 1));
      digits.fillRange(0, letters + 1, 0);
      node = 0;
      letters = 0;
    }

    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code == 0x20 || code == 0x0A || code == 0x0D || code == 0x09) {
        finish();
      } else if (code >= 0x30 && code <= 0x39) {
        digits[letters] = code - 0x30;
      } else {
        var next = child[node];
        while (next >= 0 && unit[next] != code) {
          next = sibling[next];
        }
        node = next >= 0 ? next : add(node, code);
        letters++;
      }
    }
    finish();
    return _PatternTrie._(unit, child, sibling, value, values.takeBytes());
  }

  final Uint16List _unit;
  final Int32List _child;
  final Int32List _sibling;
  final Int32List _value;
  final Uint8List _values;

  /// Every pattern that occurs in `.word.` raises the values where it
  /// sits; an odd value between two letters is a break.
  List<int> breaks(String word) {
    final length = word.length + 2;
    int codeAt(int i) =>
        i == 0 || i == length - 1 ? 0x2E : word.codeUnitAt(i - 1);
    final points = Uint8List(length + 1);
    for (var i = 0; i < length; i++) {
      var node = 0;
      for (var j = i; j < length; j++) {
        final code = codeAt(j);
        var next = _child[node];
        while (next >= 0 && _unit[next] != code) {
          next = _sibling[next];
        }
        if (next < 0) break;
        node = next;
        final at = _value[node];
        if (at < 0) continue;
        for (var k = 0; k <= j - i + 1; k++) {
          final v = _values[at + k];
          if (v > points[i + k]) points[i + k] = v;
        }
      }
    }
    // points[k + 1] is the value before word[k] (the leading dot is 0).
    return [
      for (var k = 1; k < word.length; k++)
        if (points[k + 1].isOdd) k,
    ];
  }
}
