/// EPUB canonical fragment identifiers: the strings the reader saves for
/// positions, bookmarks and highlights (`epubcfi(/6/14!/4/290,/1:175,/3:88)`).
///
/// A port of `epubcfi.js`: the same grammar, the same canonical strings,
/// the same ordering, so anything either reader wrote resolves in the
/// other. The model is immutable; parsing is one pass over the string.
/// Resolving a CFI against a document lives in `cfi_resolve.dart`.
library;

import 'package:meta/meta.dart';

/// One step of a CFI path: a child index with its optional assertions.
///
/// Even indices name elements, odd ones character data, as in the spec.
/// [offset] is a character offset into that data, [temporal] and
/// [spatial] address media, [textAssertions] carry the text before and
/// after a point, [side] is the side bias (`;s=a` or `;s=b`).
@immutable
class CfiStep {
  const CfiStep(
    this.index, {
    this.id,
    this.offset,
    this.temporal,
    this.spatial,
    this.textAssertions,
    this.side,
  });

  final int index;
  final String? id;
  final int? offset;
  final double? temporal;
  final List<double>? spatial;
  final List<String>? textAssertions;
  final String? side;

  CfiStep copyWith({
    int? index,
    Object? id = _unset,
    Object? offset = _unset,
  }) => CfiStep(
    index ?? this.index,
    id: identical(id, _unset) ? this.id : id as String?,
    offset: identical(offset, _unset) ? this.offset : offset as int?,
    temporal: temporal,
    spatial: spatial,
    textAssertions: textAssertions,
    side: side,
  );

  @override
  bool operator ==(Object other) =>
      other is CfiStep &&
      other.index == index &&
      other.id == id &&
      other.offset == offset &&
      other.temporal == temporal &&
      _listEquals(other.spatial, spatial) &&
      _listEquals(other.textAssertions, textAssertions) &&
      other.side == side;

  @override
  int get hashCode => Object.hash(
    index,
    id,
    offset,
    temporal,
    spatial == null ? null : Object.hashAll(spatial!),
    textAssertions == null ? null : Object.hashAll(textAssertions!),
    side,
  );

  /// The step as it appears inside a CFI, with assertions escaped.
  @override
  String toString() {
    final buffer = StringBuffer('/$index');
    final sideParam = side == null ? '' : ';s=$side';
    final id = this.id;
    if (id != null && id.isNotEmpty) {
      buffer.write('[${escapeCfi(id)}$sideParam]');
    }
    // "CFI expressions [..] SHOULD include an explicit character offset":
    // only character data (odd) steps carry one.
    final offset = this.offset;
    if (offset != null && index.isOdd) buffer.write(':$offset');
    final temporal = this.temporal;
    if (temporal != null && temporal != 0) {
      buffer.write('~${_number(temporal)}');
    }
    final spatial = this.spatial;
    if (spatial != null && spatial.isNotEmpty) {
      buffer.write('@${spatial.map(_number).join(':')}');
    }
    final text = textAssertions;
    final hasText = text != null && text.isNotEmpty;
    if (hasText || ((id == null || id.isEmpty) && side != null)) {
      buffer
        ..write('[')
        ..write(text?.map(escapeCfi).join(',') ?? '')
        ..write(sideParam)
        ..write(']');
    }
    return buffer.toString();
  }
}

const _unset = Object();

/// A path through one document: the steps from its root down to a node.
typedef CfiPath = List<CfiStep>;

/// A CFI, either a point or a range.
///
/// [Cfi.parse] reads the string forms both readers write; [toString]
/// writes the canonical form back. Points and ranges order with
/// [compareTo], as `epubcfi.js` orders them.
@immutable
sealed class Cfi implements Comparable<Cfi> {
  const Cfi();

  /// Parses [text], with or without the `epubcfi(...)` wrapper.
  ///
  /// Throws [CfiFormatException] when the string is not a CFI.
  factory Cfi.parse(String text) => _CfiParser(text).parse();

  /// [Cfi.parse], or null when [text] is not a CFI.
  static Cfi? tryParse(String text) {
    try {
      return Cfi.parse(text);
    } on CfiFormatException {
      return null;
    }
  }

  /// Whether [text] looks like a wrapped CFI (`epubcfi(...)`).
  static bool isCfi(String text) =>
      text.startsWith('epubcfi(') && text.endsWith(')');

  /// The point this CFI collapses to: itself for a point, the start or,
  /// with [toEnd], the end of a range.
  CfiLocation collapse({bool toEnd = false});

  /// The path to the first document the CFI addresses: the spine step for
  /// a book, or the whole path when there are no indirections. For a
  /// range it is the parent's first path, as `epub.js` reads it
  /// (`(parts.parent ?? parts).shift()`), empty when the range shares no
  /// parent steps.
  CfiPath get firstPath => switch (this) {
    CfiLocation(:final paths) => paths.first,
    CfiRange(:final parent) => parent.paths.first,
  };

  /// The string inside the wrapper.
  String toInnerString();

  @override
  String toString() => 'epubcfi(${toInnerString()})';

  /// Orders CFIs as `epubcfi.js` does: step by step along each path,
  /// a missing step sorting first, offsets deciding only at the last
  /// step; ranges compare by their starts, then by their ends.
  @override
  int compareTo(Cfi other) => compareCfi(this, other);
}

/// A point: one or more paths, each after a step indirection (`!`).
class CfiLocation extends Cfi {
  const CfiLocation(this.paths);

  /// The paths, one per document crossed; the last is the local path.
  final List<CfiPath> paths;

  CfiPath get localPath => paths.last;

  @override
  CfiLocation collapse({bool toEnd = false}) => this;

  @override
  String toInnerString() =>
      paths.map((path) => path.map((s) => s.toString()).join()).join('!');

  @override
  bool operator ==(Object other) =>
      other is CfiLocation && _pathsEqual(other.paths, paths);

  @override
  int get hashCode => Object.hashAll(paths.map(Object.hashAll));
}

/// A range: a shared parent location, then the start and end below it.
class CfiRange extends Cfi {
  const CfiRange({
    required this.parent,
    required this.start,
    required this.end,
  });

  final CfiLocation parent;
  final CfiLocation start;
  final CfiLocation end;

  @override
  CfiLocation collapse({bool toEnd = false}) =>
      _concat(parent, toEnd ? end : start);

  @override
  String toInnerString() =>
      [parent, start, end].map((l) => l.toInnerString()).join(',');

  @override
  bool operator ==(Object other) =>
      other is CfiRange &&
      other.parent == parent &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(parent, start, end);
}

/// Joins [parent]'s last path with [tail]'s first path, as `collapse`
/// does: the tail continues the parent's local path.
CfiLocation _concat(CfiLocation parent, CfiLocation tail) {
  if (parent.paths.isEmpty) return tail;
  if (tail.paths.isEmpty) return parent;
  return CfiLocation([
    ...parent.paths.take(parent.paths.length - 1),
    [...parent.paths.last, ...tail.paths.first],
    ...tail.paths.skip(1),
  ]);
}

/// Joins [parts] with step indirections into one CFI string, unwrapping
/// each (`CFI.joinIndir`).
String joinCfiIndirections(Iterable<String> parts) =>
    'epubcfi(${parts.map(unwrapCfi).join('!')})';

/// [text] without its `epubcfi(...)` wrapper, if it has one.
String unwrapCfi(String text) =>
    Cfi.isCfi(text) ? text.substring(8, text.length - 1) : text;

/// Escapes the characters a CFI assertion reserves (`^[](),;=`).
String escapeCfi(String text) =>
    text.replaceAllMapped(_reserved, (m) => '^${m[0]}');

final _reserved = RegExp(r'[\^\[\](),;=]');

/// The order of [a] and [b]; see [Cfi.compareTo].
int compareCfi(Cfi a, Cfi b) {
  if (a is CfiRange || b is CfiRange) {
    final byStart = compareCfi(a.collapse(), b.collapse());
    if (byStart != 0) return byStart;
    return compareCfi(a.collapse(toEnd: true), b.collapse(toEnd: true));
  }
  final p = (a as CfiLocation).paths;
  final q = (b as CfiLocation).paths;
  final count = p.length > q.length ? p.length : q.length;
  for (var i = 0; i < count; i++) {
    final x = i < p.length ? p[i] : const <CfiStep>[];
    final y = i < q.length ? q[i] : const <CfiStep>[];
    final last = (x.length > y.length ? x.length : y.length) - 1;
    for (var j = 0; j <= last; j++) {
      if (j >= x.length) return -1;
      if (j >= y.length) return 1;
      final s = x[j], t = y[j];
      if (s.index != t.index) return s.index > t.index ? 1 : -1;
      if (j == last) {
        // As in epubcfi.js: a missing offset compares as nothing, which
        // JavaScript's `undefined > n` makes neither greater nor smaller.
        final so = s.offset, to = t.offset;
        if (so != null && to != null && so != to) return so > to ? 1 : -1;
      }
    }
  }
  return 0;
}

/// Builds the range CFI from [from] to [to], both points in the same
/// document (`buildRange`): the steps they share go to the parent, the
/// rest to the start and the end.
CfiRange buildCfiRange(Cfi from, Cfi to) {
  final start = from.collapse();
  final end = to.collapse(toEnd: true);
  final localFrom = start.localPath;
  final localTo = end.localPath;
  final parent = <CfiStep>[];
  final localStart = <CfiStep>[];
  final localEnd = <CfiStep>[];
  var shared = true;
  final count = localFrom.length > localTo.length
      ? localFrom.length
      : localTo.length;
  for (var i = 0; i < count; i++) {
    final a = i < localFrom.length ? localFrom[i] : null;
    final b = i < localTo.length ? localTo[i] : null;
    shared =
        shared &&
        a != null &&
        b != null &&
        a.index == b.index &&
        (a.offset ?? 0) == 0 &&
        (b.offset ?? 0) == 0;
    if (shared) {
      parent.add(a);
    } else {
      if (a != null) localStart.add(a);
      if (b != null) localEnd.add(b);
    }
  }
  return CfiRange(
    parent: CfiLocation([
      ...start.paths.take(start.paths.length - 1),
      parent,
    ]),
    start: CfiLocation([localStart]),
    end: CfiLocation([localEnd]),
  );
}

/// Thrown by [Cfi.parse] for a string that is not a CFI.
class CfiFormatException extends FormatException {
  const CfiFormatException(super.message, [super.source, super.offset]);
}

// Parsing: a tokenizer over code units, then a parser over tokens, as in
// epubcfi.js. `^` escapes the next character inside assertions.

enum _TokenType {
  step,
  offset,
  temporal,
  spatial,
  assertion,
  param,
  indirection,
  comma,
}

class _Token {
  const _Token(this.type, [this.number, this.text, this.name]);

  final _TokenType type;
  final double? number;
  final String? text;

  /// For [_TokenType.param]: the parameter name (`s` for side bias).
  final String? name;
}

class _CfiParser {
  _CfiParser(String text) : _source = unwrapCfi(text).trim();

  final String _source;

  Cfi parse() {
    if (_source.isEmpty) throw CfiFormatException('Empty CFI', _source);
    final tokens = _tokenize();
    final commas = <int>[];
    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i].type == _TokenType.comma) commas.add(i);
    }
    if (commas.isEmpty) {
      final paths = _parsePaths(tokens);
      if (paths.every((path) => path.isEmpty)) {
        throw CfiFormatException('A CFI needs a step', _source);
      }
      return CfiLocation(paths);
    }
    if (commas.length != 2) {
      throw CfiFormatException('A range CFI has two commas', _source);
    }
    return CfiRange(
      parent: CfiLocation(_parsePaths(tokens.sublist(0, commas[0]))),
      start: CfiLocation(_parsePaths(tokens.sublist(commas[0] + 1, commas[1]))),
      end: CfiLocation(_parsePaths(tokens.sublist(commas[1] + 1))),
    );
  }

  List<CfiPath> _parsePaths(List<_Token> tokens) {
    final paths = <CfiPath>[];
    var from = 0;
    for (var i = 0; i <= tokens.length; i++) {
      if (i == tokens.length || tokens[i].type == _TokenType.indirection) {
        paths.add(_parsePath(tokens.sublist(from, i)));
        from = i + 1;
      }
    }
    return paths;
  }

  CfiPath _parsePath(List<_Token> tokens) {
    final steps = <CfiStep>[];
    int? index;
    String? id;
    int? offset;
    double? temporal;
    List<double>? spatial;
    List<String>? text;
    String? side;
    var afterStep = false;

    void flush() {
      if (index == null) return;
      steps.add(
        CfiStep(
          index!,
          id: id,
          offset: offset,
          temporal: temporal,
          spatial: spatial,
          textAssertions: text,
          side: side,
        ),
      );
      index = null;
      id = null;
      offset = null;
      temporal = null;
      spatial = null;
      text = null;
      side = null;
    }

    for (final token in tokens) {
      switch (token.type) {
        case _TokenType.step:
          flush();
          index = token.number!.toInt();
        case _TokenType.offset:
          if (index == null) {
            throw CfiFormatException('Offset before a step', _source);
          }
          offset = token.number!.toInt();
        case _TokenType.temporal:
          if (index == null) {
            throw CfiFormatException('Temporal offset before a step', _source);
          }
          temporal = token.number;
        case _TokenType.spatial:
          if (index == null) {
            throw CfiFormatException('Spatial offset before a step', _source);
          }
          spatial = [...?spatial, token.number!];
        case _TokenType.assertion:
          if (index == null) {
            throw CfiFormatException('Assertion before a step', _source);
          }
          // An assertion right after the step is an id; after an offset
          // (or a second one on the step) it is text.
          if (afterStep &&
              token.text!.isNotEmpty &&
              text == null &&
              id == null) {
            id = token.text;
          } else {
            text = [...?text, token.text!];
          }
        case _TokenType.param:
          if (index == null) {
            throw CfiFormatException('Parameter before a step', _source);
          }
          if (token.name == 's') side = token.text;
        case _TokenType.indirection:
        case _TokenType.comma:
          throw StateError('split before parsing');
      }
      afterStep = token.type == _TokenType.step;
    }
    flush();
    // A path may be empty: the start or end of a range that begins at
    // its parent, or a trailing indirection, as epubcfi.js allows.
    return steps;
  }

  List<_Token> _tokenize() {
    final tokens = <_Token>[];
    final s = _source;
    var i = 0;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      switch (c) {
        case _slash:
          final (value, next) = _readInt(i + 1);
          tokens.add(_Token(_TokenType.step, value.toDouble()));
          i = next;
        case _colon:
          final (value, next) = _readInt(i + 1);
          tokens.add(_Token(_TokenType.offset, value.toDouble()));
          i = next;
        case _tilde:
          final (value, next) = _readNumber(i + 1);
          tokens.add(_Token(_TokenType.temporal, value));
          i = next;
        case _at:
          var next = i + 1;
          while (true) {
            final (value, after) = _readNumber(next);
            tokens.add(_Token(_TokenType.spatial, value));
            next = after;
            if (next < s.length && s.codeUnitAt(next) == _colon) {
              next++;
              continue;
            }
            break;
          }
          i = next;
        case _bang:
          tokens.add(const _Token(_TokenType.indirection));
          i++;
        case _comma:
          tokens.add(const _Token(_TokenType.comma));
          i++;
        case _open:
          i = _readAssertion(i + 1, tokens);
        default:
          throw CfiFormatException('Unexpected character', s, i);
      }
    }
    return tokens;
  }

  /// Reads `[...]` from [start] (after the bracket): comma-separated
  /// values, then `;name=value` parameters. Returns the index after `]`.
  int _readAssertion(int start, List<_Token> tokens) {
    final s = _source;
    final value = StringBuffer();
    var i = start;
    var escape = false;
    String? paramName;
    var inParams = false;
    void pushValue() {
      if (inParams) {
        tokens.add(_Token(_TokenType.param, null, value.toString(), paramName));
      } else {
        tokens.add(_Token(_TokenType.assertion, null, value.toString()));
      }
      value.clear();
      paramName = null;
    }

    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (escape) {
        value.writeCharCode(c);
        escape = false;
      } else if (c == _caret) {
        escape = true;
      } else if (c == _close) {
        pushValue();
        return i + 1;
      } else if (c == _semicolon) {
        pushValue();
        inParams = true;
      } else if (c == _comma && !inParams) {
        pushValue();
      } else if (c == _equals && inParams && paramName == null) {
        paramName = value.toString();
        value.clear();
      } else {
        value.writeCharCode(c);
      }
      i++;
    }
    throw CfiFormatException('Unterminated assertion', s, start - 1);
  }

  (int, int) _readInt(int start) {
    final s = _source;
    var i = start;
    while (i < s.length && _isDigit(s.codeUnitAt(i))) {
      i++;
    }
    if (i == start) throw CfiFormatException('Expected a number', s, start);
    return (int.parse(s.substring(start, i)), i);
  }

  (double, int) _readNumber(int start) {
    final s = _source;
    var i = start;
    while (i < s.length &&
        (_isDigit(s.codeUnitAt(i)) || s.codeUnitAt(i) == _dot)) {
      i++;
    }
    if (i == start) throw CfiFormatException('Expected a number', s, start);
    final value = double.tryParse(s.substring(start, i));
    if (value == null) throw CfiFormatException('Malformed number', s, start);
    return (value, i);
  }
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

const _slash = 0x2F;
const _colon = 0x3A;
const _tilde = 0x7E;
const _at = 0x40;
const _bang = 0x21;
const _comma = 0x2C;
const _open = 0x5B;
const _close = 0x5D;
const _caret = 0x5E;
const _semicolon = 0x3B;
const _equals = 0x3D;
const _dot = 0x2E;

/// Numbers as `epubcfi.js` prints them: integers without a fraction.
String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _pathsEqual(List<CfiPath> a, List<CfiPath> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!_listEquals(a[i], b[i])) return false;
  }
  return true;
}
