/// Media queries (Media Queries Level 4) and `@supports` conditions
/// (CSS Conditional Rules Level 3), evaluated against the window a
/// section is read in.
///
/// The environment is the reader's as the WebView reader presented it:
/// foliate-js's paginated iframe is stretched to the width of all of a
/// section's pages, so width queries see a window wider than any
/// breakpoint (`min-width` holds, `max-width` does not) and the window
/// is landscape, while the device queries see the screen. Unknown media
/// types (`amzn-kf8`, `handheld`) and features do not match, as in a
/// browser. Pure Dart.
library;

import 'package:meta/meta.dart';

import 'css_properties.dart';
import 'css_selector.dart';
import 'css_syntax.dart';
import 'css_tokenizer.dart';
import 'css_values.dart';

/// The window media queries and viewport units are evaluated against,
/// in CSS px.
@immutable
class CssMediaEnvironment {
  const CssMediaEnvironment({
    this.viewportWidth = 390,
    this.viewportHeight = 844,
    this.deviceWidth = 390,
    this.deviceHeight = 844,
    this.devicePixelRatio = 3,
    this.darkColorScheme = false,
    this.reducedMotion = false,
  });

  /// The reader's view: what `vw` and `vh` resolve against and what
  /// height queries see.
  final double viewportWidth;
  final double viewportHeight;

  /// The screen, for `device-width` and `device-height`.
  final double deviceWidth;
  final double deviceHeight;
  final double devicePixelRatio;
  final bool darkColorScheme;
  final bool reducedMotion;

  /// The width width queries see: the paginated section's, wider than
  /// any breakpoint.
  double get queryWidth => double.infinity;

  @override
  bool operator ==(Object other) =>
      other is CssMediaEnvironment &&
      other.viewportWidth == viewportWidth &&
      other.viewportHeight == viewportHeight &&
      other.deviceWidth == deviceWidth &&
      other.deviceHeight == deviceHeight &&
      other.devicePixelRatio == devicePixelRatio &&
      other.darkColorScheme == darkColorScheme &&
      other.reducedMotion == reducedMotion;

  @override
  int get hashCode => Object.hash(
    viewportWidth,
    viewportHeight,
    deviceWidth,
    deviceHeight,
    devicePixelRatio,
    darkColorScheme,
    reducedMotion,
  );

  @override
  String toString() =>
      'CssMediaEnvironment(${viewportWidth}x$viewportHeight, device '
      '${deviceWidth}x$deviceHeight@${devicePixelRatio}x'
      '${darkColorScheme ? ', dark' : ''}${reducedMotion ? ', reduced motion' : ''})';
}

/// Whether the media query list [values] (an `@media` prelude, an
/// `@import`'s media or a `media` attribute) matches [environment]. An
/// empty list matches; a malformed query is `not all`.
bool cssMediaQueryListMatches(
  List<CssComponentValue> values,
  CssMediaEnvironment environment,
) {
  final queries = cssSplitOnCommas(values);
  if (queries.length == 1 && cssWithoutWhitespace(queries.single).isEmpty) {
    return true;
  }
  for (final query in queries) {
    if (_MediaQuery(cssWithoutWhitespace(query), environment).matches()) {
      return true;
    }
  }
  return false;
}

/// [cssMediaQueryListMatches] for the text of a `media` attribute; no
/// attribute matches.
bool cssMediaTextMatches(String? text, CssMediaEnvironment environment) {
  if (text == null || text.trim().isEmpty) return true;
  return cssMediaQueryListMatches(parseCssComponentValues(text), environment);
}

/// Whether the `@supports` condition [values] holds for pagecraft: a
/// declaration holds when pagecraft parses it, `selector()` when pagecraft
/// parses the selector. Anything else is false.
bool cssSupportsConditionHolds(List<CssComponentValue> values) =>
    _SupportsCondition(cssWithoutWhitespace(values)).holds() ?? false;

/// One media query: `[not | only]? <type> [and <condition>]?` or a
/// condition alone. Evaluates to true, false or unknown (null); unknown
/// does not match.
class _MediaQuery {
  _MediaQuery(this.values, this.environment);

  final List<CssComponentValue> values;
  final CssMediaEnvironment environment;
  int _i = 0;

  bool matches() {
    if (values.isEmpty) return false;
    final first = _ident(values.first);
    if (first == null || (first == 'not' && _isParens(_at(1)))) {
      final result = _condition(allowOr: true);
      return _i == values.length && (result ?? false);
    }
    var negated = false;
    var type = first;
    _i = 1;
    if (first == 'not' || first == 'only') {
      final next = _ident(_at(1));
      if (next == null) return false;
      negated = first == 'not';
      type = next;
      _i = 2;
    }
    if (const {'and', 'or', 'not', 'only', 'layer'}.contains(type)) {
      return false;
    }
    var result = _typeMatches(type);
    if (_i < values.length) {
      if (_ident(_at(_i)) != 'and') return false;
      _i++;
      final condition = _condition(allowOr: false);
      if (_i != values.length || condition == null) return false;
      result = result && condition;
    }
    return negated ? !result : result;
  }

  static bool _typeMatches(String type) => type == 'all' || type == 'screen';

  CssComponentValue? _at(int i) => i < values.length ? values[i] : null;

  /// `not <in-parens>`, or `<in-parens>` joined by `and` (or, with
  /// [allowOr], by `or`, never both).
  bool? _condition({required bool allowOr}) {
    if (_ident(_at(_i)) == 'not') {
      _i++;
      final inner = _inParens();
      return inner == null ? null : !inner;
    }
    var result = _inParens();
    String? joiner;
    while (_i < values.length) {
      final word = _ident(_at(_i));
      if (word != 'and' && !(allowOr && word == 'or')) break;
      if (joiner != null && joiner != word) return null;
      joiner = word;
      _i++;
      final next = _inParens();
      result = word == 'and' ? _and(result, next) : _or(result, next);
    }
    return result;
  }

  bool? _inParens() {
    final value = _at(_i);
    if (!_isParens(value)) {
      _i = values.length;
      return null;
    }
    _i++;
    final inside = cssWithoutWhitespace((value! as CssBlockValue).values);
    final first = _ident(inside.firstOrNull);
    // A nested condition: `((width > 1px) and (height > 1px))`, `(not …)`.
    if (inside.isNotEmpty && (_isParens(inside.first) || first == 'not')) {
      final nested = _MediaQuery(inside, environment);
      final result = nested._condition(allowOr: true);
      return nested._i == inside.length ? result : null;
    }
    return _MediaFeature(inside, environment).evaluate();
  }
}

bool? _and(bool? a, bool? b) => a == false || b == false
    ? false
    : a == null || b == null
    ? null
    : true;

bool? _or(bool? a, bool? b) => a == true || b == true
    ? true
    : a == null || b == null
    ? null
    : false;

bool _isParens(CssComponentValue? value) =>
    value is CssBlockValue && value.open == CssTokenType.openParen;

String? _ident(CssComponentValue? value) =>
    value is CssTokenValue && value.token.type == CssTokenType.ident
    ? value.token.value.toLowerCase()
    : null;

/// A media feature in parentheses: `(color)`, `(min-width: 40em)` or a
/// range, `(400px <= width < 60em)`.
class _MediaFeature {
  _MediaFeature(this.values, this.environment);

  final List<CssComponentValue> values;
  final CssMediaEnvironment environment;

  bool? evaluate() {
    if (values.isEmpty) return null;
    final colon = values.indexWhere(
      (v) => v is CssTokenValue && v.token.type == CssTokenType.colon,
    );
    if (colon == 1) {
      final name = _ident(values.first);
      if (name == null) return null;
      return _plain(name, values.sublist(2));
    }
    if (values.length == 1) {
      final name = _ident(values.single);
      return name == null ? null : _boolean(name);
    }
    return _range();
  }

  /// `(name)`: true unless the feature's value is zero or `none`.
  bool? _boolean(String name) {
    final value = _featureValue(name);
    return switch (value) {
      null => null,
      _Number(:final number) => number != 0,
      _Keyword(:final keyword) =>
        keyword != 'none' && keyword != 'no-preference',
    };
  }

  bool? _plain(String name, List<CssComponentValue> rest) {
    var feature = name;
    var compare = _Compare.equal;
    if (name.startsWith('min-')) {
      feature = name.substring(4);
      compare = _Compare.atLeast;
    } else if (name.startsWith('max-')) {
      feature = name.substring(4);
      compare = _Compare.atMost;
    } else if (name.startsWith('-webkit-min-')) {
      feature = '-webkit-${name.substring(12)}';
      compare = _Compare.atLeast;
    } else if (name.startsWith('-webkit-max-')) {
      feature = '-webkit-${name.substring(12)}';
      compare = _Compare.atMost;
    }
    final actual = _featureValue(feature);
    if (actual == null) return null;
    final wanted = _parseValue(rest, keyword: actual is _Keyword);
    if (wanted == null) return null;
    return _holds(actual, compare, wanted);
  }

  /// `(name op value)`, `(value op name)` or `(a op name op b)`.
  bool? _range() {
    final parts = <List<CssComponentValue>>[[]];
    final operators = <String>[];
    var i = 0;
    while (i < values.length) {
      final op = _operatorAt(i);
      if (op != null) {
        operators.add(op.$1);
        parts.add([]);
        i += op.$2;
      } else {
        parts.last.add(values[i]);
        i++;
      }
    }
    if (operators.isEmpty || operators.length > 2) return null;
    if (operators.length == 2) {
      final name = parts[1].length == 1 ? _ident(parts[1].single) : null;
      if (name == null) return null;
      final actual = _featureValue(name);
      final low = _parseValue(parts[0]);
      final high = _parseValue(parts[2]);
      if (actual == null || low == null || high == null) return null;
      return _and(
        _holds(actual, _flip(_compareOf(operators[0])), low),
        _holds(actual, _compareOf(operators[1]), high),
      );
    }
    final leftName = parts[0].length == 1 ? _ident(parts[0].single) : null;
    final rightName = parts[1].length == 1 ? _ident(parts[1].single) : null;
    if (leftName != null && _featureValue(leftName) != null) {
      final wanted = _parseValue(parts[1]);
      if (wanted == null) return null;
      return _holds(
        _featureValue(leftName)!,
        _compareOf(operators.single),
        wanted,
      );
    }
    if (rightName != null && _featureValue(rightName) != null) {
      final wanted = _parseValue(parts[0]);
      if (wanted == null) return null;
      return _holds(
        _featureValue(rightName)!,
        _flip(_compareOf(operators.single)),
        wanted,
      );
    }
    return null;
  }

  /// A comparison operator at [i] and how many tokens it takes.
  (String, int)? _operatorAt(int i) {
    String? delim(int at) {
      if (at >= values.length) return null;
      final v = values[at];
      return v is CssTokenValue && v.token.type == CssTokenType.delim
          ? v.token.value
          : null;
    }

    final first = delim(i);
    if (first == null || !const {'<', '>', '='}.contains(first)) return null;
    if (first != '=' && delim(i + 1) == '=') return ('$first=', 2);
    return (first, 1);
  }

  static _Compare _compareOf(String op) => switch (op) {
    '<' => _Compare.less,
    '<=' => _Compare.atMost,
    '>' => _Compare.greater,
    '>=' => _Compare.atLeast,
    _ => _Compare.equal,
  };

  /// `value op feature` read as `feature op' value`.
  static _Compare _flip(_Compare compare) => switch (compare) {
    _Compare.less => _Compare.greater,
    _Compare.atMost => _Compare.atLeast,
    _Compare.greater => _Compare.less,
    _Compare.atLeast => _Compare.atMost,
    _Compare.equal => _Compare.equal,
  };

  static bool? _holds(
    _FeatureValue actual,
    _Compare compare,
    _FeatureValue wanted,
  ) {
    switch ((actual, wanted)) {
      case (_Keyword(keyword: final a), _Keyword(keyword: final b)):
        return compare == _Compare.equal ? a == b : null;
      case (_Number(number: final a), _Number(number: final b)):
        // A little tolerance, as browsers round lengths.
        const epsilon = 1e-6;
        return switch (compare) {
          _Compare.equal => (a - b).abs() < epsilon,
          _Compare.less => a < b - epsilon,
          _Compare.atMost => a <= b + epsilon,
          _Compare.greater => a > b + epsilon,
          _Compare.atLeast => a >= b - epsilon,
        };
      default:
        return null;
    }
  }

  /// A length (in px, `em` as 16px), a number, a ratio (`16/9`), a
  /// resolution (in dppx) or, with [keyword], an identifier.
  static _FeatureValue? _parseValue(
    List<CssComponentValue> values, {
    bool keyword = false,
  }) {
    final parts = cssWithoutWhitespace(values);
    if (parts.length == 3) {
      final slash = parts[1];
      if (slash is CssTokenValue &&
          slash.token.type == CssTokenType.delim &&
          slash.token.value == '/') {
        final a = _number(parts[0]);
        final b = _number(parts[2]);
        if (a == null || b == null || b == 0) return null;
        return _Number(a / b);
      }
      return null;
    }
    if (parts.length != 1) return null;
    final value = parts.single;
    if (keyword) {
      final ident = _ident(value);
      return ident == null ? null : _Keyword(ident);
    }
    if (value is CssTokenValue && value.token.type == CssTokenType.dimension) {
      final resolution = switch (value.token.unit) {
        'dppx' || 'x' => value.token.number,
        'dpi' => value.token.number / 96,
        'dpcm' => value.token.number * 2.54 / 96,
        _ => null,
      };
      if (resolution != null) return _Number(resolution);
    }
    final length = CssLength.parse(value, allowPercent: false);
    if (length != null) {
      return _Number(
        length.toPx(
          const CssLengthContext(fontSize: 16, rootFontSize: 16),
        ),
      );
    }
    final number = _number(value);
    if (number != null) return _Number(number);
    final ident = _ident(value);
    return ident == null ? null : _Keyword(ident);
  }

  static double? _number(CssComponentValue value) =>
      value is CssTokenValue && value.token.type == CssTokenType.number
      ? value.token.number
      : null;

  /// The environment's value of [name], or null for an unknown feature.
  _FeatureValue? _featureValue(String name) {
    final env = environment;
    final width = env.queryWidth;
    final height = env.viewportHeight;
    return switch (name) {
      'width' => _Number(width),
      'height' => _Number(height),
      'aspect-ratio' => _Number(height == 0 ? double.infinity : width / height),
      'orientation' => _Keyword(height >= width ? 'portrait' : 'landscape'),
      'device-width' => _Number(env.deviceWidth),
      'device-height' => _Number(env.deviceHeight),
      'device-aspect-ratio' => _Number(
        env.deviceHeight == 0 ? 0 : env.deviceWidth / env.deviceHeight,
      ),
      'resolution' ||
      '-webkit-device-pixel-ratio' ||
      'device-pixel-ratio' => _Number(env.devicePixelRatio),
      'color' => const _Number(8),
      'color-index' || 'monochrome' || 'grid' => const _Number(0),
      'color-gamut' => const _Keyword('srgb'),
      'scan' => const _Keyword('progressive'),
      'update' => const _Keyword('fast'),
      'hover' || 'any-hover' => const _Keyword('none'),
      'pointer' || 'any-pointer' => const _Keyword('coarse'),
      'prefers-color-scheme' => _Keyword(
        env.darkColorScheme ? 'dark' : 'light',
      ),
      'prefers-reduced-motion' => _Keyword(
        env.reducedMotion ? 'reduce' : 'no-preference',
      ),
      'prefers-contrast' ||
      'prefers-reduced-transparency' ||
      'prefers-reduced-data' => const _Keyword('no-preference'),
      'forced-colors' || 'inverted-colors' => const _Keyword('none'),
      'display-mode' => const _Keyword('browser'),
      _ => null,
    };
  }
}

enum _Compare { less, atMost, equal, atLeast, greater }

sealed class _FeatureValue {
  const _FeatureValue();
}

class _Number extends _FeatureValue {
  const _Number(this.number);

  final double number;
}

class _Keyword extends _FeatureValue {
  const _Keyword(this.keyword);

  final String keyword;
}

/// An `@supports` condition over component values without whitespace.
class _SupportsCondition {
  _SupportsCondition(this.values);

  final List<CssComponentValue> values;
  int _i = 0;

  bool? holds() {
    final result = _condition();
    return _i == values.length ? result : null;
  }

  bool? _condition() {
    if (_ident(_at(_i)) == 'not') {
      _i++;
      final inner = _inParens();
      return inner == null ? null : !inner;
    }
    var result = _inParens();
    String? joiner;
    while (_i < values.length) {
      final word = _ident(_at(_i));
      if (word != 'and' && word != 'or') break;
      if (joiner != null && joiner != word) return null;
      joiner = word;
      _i++;
      final next = _inParens();
      result = word == 'and' ? _and(result, next) : _or(result, next);
    }
    return result;
  }

  CssComponentValue? _at(int i) => i < values.length ? values[i] : null;

  bool? _inParens() {
    final value = _at(_i);
    _i++;
    if (value is CssFunctionValue && value.name.toLowerCase() == 'selector') {
      final selectors = CssSelectorList.parse(value.arguments);
      return selectors != null;
    }
    if (!_isParens(value)) return null;
    final inside = cssWithoutWhitespace((value! as CssBlockValue).values);
    if (inside.isEmpty) return null;
    if (_isParens(inside.first) ||
        _ident(inside.first) == 'not' ||
        (inside.first is CssFunctionValue &&
            (inside.first as CssFunctionValue).name.toLowerCase() ==
                'selector')) {
      final nested = _SupportsCondition(inside);
      return nested.holds();
    }
    // A declaration: `name: value`.
    final name = _ident(inside.first);
    if (name == null ||
        inside.length < 3 ||
        inside[1] is! CssTokenValue ||
        (inside[1] as CssTokenValue).token.type != CssTokenType.colon) {
      return null;
    }
    return parseCssDeclaration(
      CssDeclaration(name, inside.sublist(2)),
    ).isNotEmpty;
  }
}
