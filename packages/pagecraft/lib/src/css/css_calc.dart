part of 'css_values.dart';

/// A math function over lengths (CSS Values 4 §10): `calc()`, `min()`,
/// `max()` and `clamp()`, nested and mixed with numbers. Relative units
/// resolve where the style is computed ([resolve]); percentages wait for
/// the layout, which knows what they are of ([evaluate]).
sealed class CssCalc {
  const CssCalc();

  /// Parses math function [value], or null when it is not one, is not
  /// well formed, or does not compute to a length (`calc(1 + 2)` is a
  /// number, `calc(1px * 2px)` nothing).
  static CssCalc? parse(CssComponentValue value) {
    if (value is! CssFunctionValue) return null;
    final node = _CalcParser._function(value);
    return node == null || node.isNumber ? null : node;
  }

  /// Whether the node is a plain number: what `*` and `/` take.
  bool get isNumber;

  /// Whether a percentage is in it: its value depends on the layout.
  bool get hasPercent;

  /// The value in px: relative units by [context] (none left after
  /// [resolve]), percentages of [percentOf].
  double evaluate(CssLengthContext? context, double percentOf);

  /// The same with relative units in px, percentages kept, and what can
  /// be added up added.
  CssCalc resolve(CssLengthContext context);
}

/// A dimension or a percentage.
class _CalcLength extends CssCalc {
  const _CalcLength(this.length);

  final CssLength length;

  @override
  bool get isNumber => false;

  @override
  bool get hasPercent => length.isPercent;

  @override
  double evaluate(CssLengthContext? context, double percentOf) {
    if (length.isPercent) return length.value * percentOf / 100;
    if (length.isPx || context == null) return length.value;
    return length.toPx(context);
  }

  @override
  CssCalc resolve(CssLengthContext context) => length.isPercent || length.isPx
      ? this
      : _CalcLength(CssLength.px(length.toPx(context)));

  @override
  bool operator ==(Object other) =>
      other is _CalcLength && other.length == length;

  @override
  int get hashCode => length.hashCode;

  @override
  String toString() => '$length';
}

class _CalcNumber extends CssCalc {
  const _CalcNumber(this.value);

  final double value;

  @override
  bool get isNumber => true;

  @override
  bool get hasPercent => false;

  @override
  double evaluate(CssLengthContext? context, double percentOf) => value;

  @override
  CssCalc resolve(CssLengthContext context) => this;

  @override
  bool operator ==(Object other) =>
      other is _CalcNumber && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '$value';
}

/// Terms added up; a subtracted term is scaled by -1.
class _CalcSum extends CssCalc {
  const _CalcSum(this.terms);

  final List<CssCalc> terms;

  @override
  bool get isNumber => terms.first.isNumber;

  @override
  bool get hasPercent => terms.any((t) => t.hasPercent);

  @override
  double evaluate(CssLengthContext? context, double percentOf) {
    var sum = 0.0;
    for (final term in terms) {
      sum += term.evaluate(context, percentOf);
    }
    return sum;
  }

  /// Lengths in px become one term, percentages another.
  @override
  CssCalc resolve(CssLengthContext context) {
    var px = 0.0;
    var percent = 0.0;
    final rest = <CssCalc>[];
    for (final term in terms) {
      switch (term.resolve(context)) {
        case _CalcLength(:final length) when length.isPercent:
          percent += length.value;
        case _CalcLength(:final length):
          px += length.value;
        case final other:
          rest.add(other);
      }
    }
    final out = [
      if (px != 0 || (percent == 0 && rest.isEmpty))
        _CalcLength(CssLength.px(px)),
      if (percent != 0) _CalcLength(CssLength.percent(percent)),
      ...rest,
    ];
    return out.length == 1 ? out.single : _CalcSum(out);
  }

  @override
  bool operator ==(Object other) =>
      other is _CalcSum && _listEquals(other.terms, terms);

  @override
  int get hashCode => Object.hashAll(terms);

  @override
  String toString() => '(${terms.join(' + ')})';
}

/// A node times a number: `*` and `/`, and `-` before a term.
class _CalcScaled extends CssCalc {
  const _CalcScaled(this.node, this.factor);

  final CssCalc node;
  final double factor;

  @override
  bool get isNumber => node.isNumber;

  @override
  bool get hasPercent => node.hasPercent;

  @override
  double evaluate(CssLengthContext? context, double percentOf) =>
      node.evaluate(context, percentOf) * factor;

  @override
  CssCalc resolve(CssLengthContext context) => switch (node.resolve(
    context,
  )) {
    _CalcLength(:final length) => _CalcLength(
      CssLength(length.value * factor, length.unit),
    ),
    final other => _CalcScaled(other, factor),
  };

  @override
  bool operator ==(Object other) =>
      other is _CalcScaled && other.node == node && other.factor == factor;

  @override
  int get hashCode => Object.hash(node, factor);

  @override
  String toString() => '$node * $factor';
}

/// `min()` or `max()`; `clamp(a, b, c)` is `max(a, min(b, c))`.
class _CalcMinMax extends CssCalc {
  const _CalcMinMax(this.arguments, {required this.isMax});

  final List<CssCalc> arguments;
  final bool isMax;

  @override
  bool get isNumber => arguments.first.isNumber;

  @override
  bool get hasPercent => arguments.any((a) => a.hasPercent);

  @override
  double evaluate(CssLengthContext? context, double percentOf) {
    var out = arguments.first.evaluate(context, percentOf);
    for (final argument in arguments.skip(1)) {
      final v = argument.evaluate(context, percentOf);
      if (isMax ? v > out : v < out) out = v;
    }
    return out;
  }

  @override
  CssCalc resolve(CssLengthContext context) {
    final resolved = [for (final a in arguments) a.resolve(context)];
    if (resolved.every((a) => a is _CalcLength && !a.hasPercent)) {
      return _CalcLength(
        CssLength.px(_CalcMinMax(resolved, isMax: isMax).evaluate(null, 0)),
      );
    }
    return _CalcMinMax(resolved, isMax: isMax);
  }

  @override
  bool operator ==(Object other) =>
      other is _CalcMinMax &&
      other.isMax == isMax &&
      _listEquals(other.arguments, arguments);

  @override
  int get hashCode => Object.hash(isMax, Object.hashAll(arguments));

  @override
  String toString() => '${isMax ? 'max' : 'min'}(${arguments.join(', ')})';
}

bool _listEquals(List<CssCalc> a, List<CssCalc> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The grammar of CSS Values 4 §10.1 over component values:
///
///     <calc-sum>     = <calc-product> [ [ '+' | '-' ] <calc-product> ]*
///     <calc-product> = <calc-value> [ [ '*' | '/' ] <calc-value> ]*
///     <calc-value>   = <number> | <dimension> | <percentage>
///                    | ( <calc-sum> ) | <math function>
///
/// Types are checked as it goes: a sum adds like with like, a product
/// takes a number on one side, a division a number on the right.
class _CalcParser {
  _CalcParser(Iterable<CssComponentValue> values)
    : _values = [
        for (final v in values)
          if (!(v is CssTokenValue && v.token.type == CssTokenType.whitespace))
            v,
      ];

  final List<CssComponentValue> _values;
  int _at = 0;

  /// A math function's node, or null.
  static CssCalc? _function(CssFunctionValue value) {
    final name = value.name.toLowerCase();
    if (name == 'calc') return _CalcParser(value.arguments)._whole();
    final arguments = _arguments(value.arguments);
    if (arguments == null) return null;
    return switch (name) {
      'min' || 'max' when arguments.isNotEmpty && _sameType(arguments) =>
        _CalcMinMax(arguments, isMax: name == 'max'),
      'clamp' when arguments.length == 3 && _sameType(arguments) => _CalcMinMax(
        [
          arguments[0],
          _CalcMinMax([arguments[1], arguments[2]], isMax: false),
        ],
        isMax: true,
      ),
      _ => null,
    };
  }

  /// Comma-separated sums, or null when one is not well formed.
  static List<CssCalc>? _arguments(List<CssComponentValue> values) {
    final out = <CssCalc>[];
    var start = 0;
    for (var i = 0; i <= values.length; i++) {
      if (i < values.length && !_isComma(values[i])) continue;
      final node = _CalcParser(values.sublist(start, i))._whole();
      if (node == null) return null;
      out.add(node);
      start = i + 1;
    }
    return out;
  }

  static bool _isComma(CssComponentValue value) =>
      value is CssTokenValue && value.token.type == CssTokenType.comma;

  static bool _sameType(List<CssCalc> nodes) =>
      nodes.every((n) => n.isNumber == nodes.first.isNumber);

  /// The values as one sum, nothing left over.
  CssCalc? _whole() {
    final node = _sum();
    return node == null || _at != _values.length ? null : node;
  }

  String? _delim() {
    if (_at >= _values.length) return null;
    final value = _values[_at];
    return value is CssTokenValue && value.token.type == CssTokenType.delim
        ? value.token.value
        : null;
  }

  CssCalc? _sum() {
    final first = _product();
    if (first == null) return null;
    final terms = [first];
    while (true) {
      final op = _delim();
      if (op != '+' && op != '-') break;
      _at++;
      final next = _product();
      if (next == null || next.isNumber != first.isNumber) return null;
      terms.add(op == '-' ? _CalcScaled(next, -1) : next);
    }
    return terms.length == 1 ? first : _CalcSum(terms);
  }

  CssCalc? _product() {
    var node = _value();
    if (node == null) return null;
    while (true) {
      final op = _delim();
      if (op != '*' && op != '/') break;
      _at++;
      final next = _value();
      if (next == null) return null;
      if (op == '/') {
        if (!next.isNumber) return null;
        final divisor = next.evaluate(null, 0);
        if (divisor == 0) return null;
        node = _scaled(node!, 1 / divisor);
      } else if (next.isNumber) {
        node = _scaled(node!, next.evaluate(null, 0));
      } else if (node!.isNumber) {
        node = _scaled(next, node.evaluate(null, 0));
      } else {
        return null;
      }
    }
    return node;
  }

  /// [node] times [factor]; numbers fold.
  static CssCalc _scaled(CssCalc node, double factor) => node.isNumber
      ? _CalcNumber(node.evaluate(null, 0) * factor)
      : _CalcScaled(node, factor);

  CssCalc? _value() {
    if (_at >= _values.length) return null;
    final value = _values[_at++];
    switch (value) {
      case CssTokenValue(:final token) when token.type == CssTokenType.number:
        return _CalcNumber(token.number);
      case CssTokenValue():
        final length = CssLength.parse(value);
        return length == null ? null : _CalcLength(length);
      case CssBlockValue(:final open, :final values)
          when open == CssTokenType.openParen:
        return _CalcParser(values)._whole();
      case CssFunctionValue():
        return _function(value);
      case CssBlockValue():
        return null;
    }
  }
}
