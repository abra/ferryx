/// CSS parsing (CSS Syntax Module Level 3, §5): tokens become a
/// stylesheet of rules and declarations, with the spec's error recovery
/// (a bad declaration is dropped, a bad rule is skipped to its end) and
/// never an exception. Selectors and property values stay as component
/// values here; `css_selector.dart` and `css_values.dart` read them.
library;

import 'css_tokenizer.dart';

/// A token, a function with its arguments, or a `[]`/`()`/`{}` block.
sealed class CssComponentValue {
  const CssComponentValue();
}

class CssTokenValue extends CssComponentValue {
  const CssTokenValue(this.token);

  final CssToken token;

  @override
  String toString() => token.toString();
}

class CssFunctionValue extends CssComponentValue {
  const CssFunctionValue(this.name, this.arguments);

  /// The function name as written; compare lowercased.
  final String name;
  final List<CssComponentValue> arguments;

  @override
  String toString() => '$name(${arguments.join()})';
}

class CssBlockValue extends CssComponentValue {
  const CssBlockValue(this.open, this.values);

  /// `[`, `(` or `{`.
  final CssTokenType open;
  final List<CssComponentValue> values;

  @override
  String toString() {
    final (a, b) = switch (open) {
      CssTokenType.openSquare => ('[', ']'),
      CssTokenType.openParen => ('(', ')'),
      _ => ('{', '}'),
    };
    return '$a${values.join()}$b';
  }
}

/// `name: value !important`.
class CssDeclaration {
  const CssDeclaration(this.name, this.value, {this.isImportant = false});

  /// Lowercased.
  final String name;

  /// The value's component values, leading and trailing whitespace
  /// removed.
  final List<CssComponentValue> value;
  final bool isImportant;

  @override
  String toString() =>
      '$name: ${value.join()}${isImportant ? ' !important' : ''};';
}

sealed class CssRule {
  const CssRule();
}

/// `prelude { declarations }`: a style rule before selector parsing.
class CssQualifiedRule extends CssRule {
  const CssQualifiedRule(this.prelude, this.declarations);

  final List<CssComponentValue> prelude;
  final List<CssDeclaration> declarations;

  @override
  String toString() => '${prelude.join()} { ${declarations.join(' ')} }';
}

/// `@name prelude;` or `@name prelude { block }`. Rules nested in a
/// `@media` block are parsed as rules; `@font-face` and `@page` blocks
/// as declarations.
class CssAtRule extends CssRule {
  const CssAtRule(this.name, this.prelude, {this.rules, this.declarations});

  /// Lowercased.
  final String name;
  final List<CssComponentValue> prelude;
  final List<CssRule>? rules;
  final List<CssDeclaration>? declarations;

  @override
  String toString() =>
      '@$name ${prelude.join()}${rules == null && declarations == null ? ';' : ' {…}'}';
}

/// A parsed stylesheet: its rules in source order.
class CssStyleSheet {
  const CssStyleSheet(this.rules);

  final List<CssRule> rules;

  /// Parses [source]. Never throws: what is not CSS is skipped.
  factory CssStyleSheet.parse(String source) =>
      CssStyleSheet(_CssParser(tokenizeCss(source)).parseStyleSheet());
}

/// Parses a `style=""` attribute: declarations without braces.
List<CssDeclaration> parseCssDeclarations(String source) =>
    _CssParser(tokenizeCss(source)).parseDeclarationList();

/// Parses component values, for a selector or a value out of context.
List<CssComponentValue> parseCssComponentValues(String source) =>
    _CssParser(tokenizeCss(source)).parseComponentValues();

/// At-rules whose block holds rules rather than declarations.
const _ruleBlockAtRules = {'media', 'supports', 'document', 'layer'};

class _CssParser {
  _CssParser(this._tokens);

  final List<CssToken> _tokens;
  int _i = 0;

  CssToken get _peek => _i < _tokens.length ? _tokens[_i] : CssToken.eof;

  CssToken _consume() => _i < _tokens.length ? _tokens[_i++] : CssToken.eof;

  bool get _atEnd => _i >= _tokens.length;

  List<CssRule> parseStyleSheet() => _consumeRules(topLevel: true);

  List<CssComponentValue> parseComponentValues() {
    final out = <CssComponentValue>[];
    while (!_atEnd) {
      out.add(_consumeComponentValue());
    }
    return out;
  }

  /// §5.4.1.
  List<CssRule> _consumeRules({required bool topLevel}) {
    final rules = <CssRule>[];
    while (true) {
      final t = _peek;
      switch (t.type) {
        case CssTokenType.whitespace:
          _consume();
        case CssTokenType.eof:
          return rules;
        case CssTokenType.closeBrace when !topLevel:
          return rules;
        case CssTokenType.cdo || CssTokenType.cdc:
          _consume();
          if (!topLevel) {
            _i--;
            final rule = _consumeQualifiedRule();
            if (rule != null) rules.add(rule);
          }
        case CssTokenType.atKeyword:
          rules.add(_consumeAtRule());
        default:
          final rule = _consumeQualifiedRule();
          if (rule != null) rules.add(rule);
      }
    }
  }

  /// §5.4.2.
  CssAtRule _consumeAtRule() {
    final name = _consume().value.toLowerCase();
    final prelude = <CssComponentValue>[];
    while (true) {
      final t = _peek;
      switch (t.type) {
        case CssTokenType.semicolon || CssTokenType.eof:
          _consume();
          return CssAtRule(name, _trim(prelude));
        case CssTokenType.openBrace:
          _consume();
          if (_ruleBlockAtRules.contains(name)) {
            final rules = _consumeRules(topLevel: false);
            _expectCloseBrace();
            return CssAtRule(name, _trim(prelude), rules: rules);
          }
          final declarations = _consumeDeclarations();
          _expectCloseBrace();
          return CssAtRule(name, _trim(prelude), declarations: declarations);
        default:
          prelude.add(_consumeComponentValue());
      }
    }
  }

  /// §5.4.3. Null when the input ends before the block: a parse error,
  /// the rule is dropped.
  CssQualifiedRule? _consumeQualifiedRule() {
    final prelude = <CssComponentValue>[];
    while (true) {
      final t = _peek;
      switch (t.type) {
        case CssTokenType.eof:
          return null;
        case CssTokenType.openBrace:
          _consume();
          final declarations = _consumeDeclarations();
          _expectCloseBrace();
          return CssQualifiedRule(_trim(prelude), declarations);
        default:
          prelude.add(_consumeComponentValue());
      }
    }
  }

  void _expectCloseBrace() {
    if (_peek.type == CssTokenType.closeBrace) _consume();
  }

  List<CssDeclaration> parseDeclarationList() {
    final out = _consumeDeclarations();
    return out;
  }

  /// §5.4.4, inside a block: declarations until the closing brace or
  /// the end; at-rules inside a declaration block are consumed and
  /// dropped, as are malformed declarations.
  List<CssDeclaration> _consumeDeclarations() {
    final out = <CssDeclaration>[];
    while (true) {
      final t = _peek;
      switch (t.type) {
        case CssTokenType.whitespace || CssTokenType.semicolon:
          _consume();
        case CssTokenType.eof || CssTokenType.closeBrace:
          return out;
        case CssTokenType.atKeyword:
          _consumeAtRule();
        case CssTokenType.ident:
          final parts = <CssComponentValue>[];
          while (_peek.type != CssTokenType.semicolon &&
              _peek.type != CssTokenType.eof &&
              _peek.type != CssTokenType.closeBrace) {
            parts.add(_consumeComponentValue());
          }
          final declaration = _declarationFrom(parts);
          if (declaration != null) out.add(declaration);
        default:
          // Parse error: skip to the next declaration.
          while (_peek.type != CssTokenType.semicolon &&
              _peek.type != CssTokenType.eof &&
              _peek.type != CssTokenType.closeBrace) {
            _consumeComponentValue();
          }
      }
    }
  }

  /// §5.4.6 over the component values of one declaration.
  CssDeclaration? _declarationFrom(List<CssComponentValue> parts) {
    final name = (parts.first as CssTokenValue).token.value.toLowerCase();
    var i = 1;
    while (i < parts.length && _isWhitespace(parts[i])) {
      i++;
    }
    if (i >= parts.length ||
        parts[i] is! CssTokenValue ||
        (parts[i] as CssTokenValue).token.type != CssTokenType.colon) {
      return null;
    }
    i++;
    var value = _trim(parts.sublist(i));
    var important = false;
    if (value.length >= 2) {
      final last = value[value.length - 1];
      final bang = value[value.length - 2];
      if (last is CssTokenValue &&
          last.token.isIdent('important') &&
          bang is CssTokenValue &&
          bang.token.isDelim('!')) {
        important = true;
        value = _trim(value.sublist(0, value.length - 2));
      }
    }
    if (value.any(_isBad)) return null;
    return CssDeclaration(name, value, isImportant: important);
  }

  static bool _isBad(CssComponentValue v) => switch (v) {
    CssTokenValue(:final token) =>
      token.type == CssTokenType.badString || token.type == CssTokenType.badUrl,
    CssFunctionValue(:final arguments) => arguments.any(_isBad),
    CssBlockValue(:final values) => values.any(_isBad),
  };

  /// §5.4.7.
  CssComponentValue _consumeComponentValue() {
    final t = _consume();
    switch (t.type) {
      case CssTokenType.openBrace ||
          CssTokenType.openSquare ||
          CssTokenType.openParen:
        return _consumeBlock(t.type);
      case CssTokenType.function:
        return _consumeFunction(t.value);
      default:
        return CssTokenValue(t);
    }
  }

  /// §5.4.8.
  CssBlockValue _consumeBlock(CssTokenType open) {
    final close = switch (open) {
      CssTokenType.openBrace => CssTokenType.closeBrace,
      CssTokenType.openSquare => CssTokenType.closeSquare,
      _ => CssTokenType.closeParen,
    };
    final values = <CssComponentValue>[];
    while (true) {
      final t = _peek;
      if (t.type == close || t.type == CssTokenType.eof) {
        _consume();
        return CssBlockValue(open, values);
      }
      values.add(_consumeComponentValue());
    }
  }

  /// §5.4.9.
  CssFunctionValue _consumeFunction(String name) {
    final arguments = <CssComponentValue>[];
    while (true) {
      final t = _peek;
      if (t.type == CssTokenType.closeParen || t.type == CssTokenType.eof) {
        _consume();
        return CssFunctionValue(name, arguments);
      }
      arguments.add(_consumeComponentValue());
    }
  }

  static bool _isWhitespace(CssComponentValue v) =>
      v is CssTokenValue && v.token.isWhitespace;

  static List<CssComponentValue> _trim(List<CssComponentValue> values) {
    var start = 0;
    var end = values.length;
    while (start < end && _isWhitespace(values[start])) {
      start++;
    }
    while (end > start && _isWhitespace(values[end - 1])) {
      end--;
    }
    return values.sublist(start, end);
  }
}
