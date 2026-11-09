/// CSS tokenization (CSS Syntax Module Level 3, §4): the input stream
/// becomes tokens, never an error. Comments are dropped, escapes are
/// decoded, numbers are typed, and a bad string or URL yields a
/// bad-token that the parser then discards with its declaration.
library;

/// The kinds of token.
enum CssTokenType {
  ident,

  /// An identifier followed by `(`; [CssToken.value] is the name.
  function,

  /// `@name`; [CssToken.value] is the name.
  atKeyword,

  /// `#name`; [CssToken.value] is the name, [CssToken.isId] whether it
  /// is a valid identifier (so `#1a` is a hash but not an id selector).
  hash,
  string,
  badString,

  /// `url(…)` with an unquoted argument; [CssToken.value] is the URL.
  url,
  badUrl,

  /// A single code point; [CssToken.value] holds it.
  delim,
  number,
  percentage,

  /// A number with a unit; [CssToken.unit] is lowercased.
  dimension,
  whitespace,
  cdo,
  cdc,
  colon,
  semicolon,
  comma,
  openSquare,
  closeSquare,
  openParen,
  closeParen,
  openBrace,
  closeBrace,
  eof,
}

/// One token. [value] is the identifier, string, URL, name or delimiter;
/// [number] the numeric value of a number, percentage or dimension.
class CssToken {
  const CssToken(
    this.type, {
    this.value = '',
    this.number = 0,
    this.isInteger = false,
    this.unit = '',
    this.isId = false,
  });

  static const eof = CssToken(CssTokenType.eof);
  static const whitespace = CssToken(CssTokenType.whitespace);

  final CssTokenType type;
  final String value;
  final double number;
  final bool isInteger;
  final String unit;
  final bool isId;

  bool get isWhitespace => type == CssTokenType.whitespace;

  bool isDelim(String char) => type == CssTokenType.delim && value == char;

  bool isIdent(String name) =>
      type == CssTokenType.ident && value.toLowerCase() == name;

  @override
  String toString() => switch (type) {
    CssTokenType.ident => value,
    CssTokenType.function => '$value(',
    CssTokenType.atKeyword => '@$value',
    CssTokenType.hash => '#$value',
    CssTokenType.string => '"$value"',
    CssTokenType.url => 'url($value)',
    CssTokenType.delim => value,
    CssTokenType.number => _formatNumber(number),
    CssTokenType.percentage => '${_formatNumber(number)}%',
    CssTokenType.dimension => '${_formatNumber(number)}$unit',
    CssTokenType.whitespace => ' ',
    CssTokenType.cdo => '<!--',
    CssTokenType.cdc => '-->',
    CssTokenType.colon => ':',
    CssTokenType.semicolon => ';',
    CssTokenType.comma => ',',
    CssTokenType.openSquare => '[',
    CssTokenType.closeSquare => ']',
    CssTokenType.openParen => '(',
    CssTokenType.closeParen => ')',
    CssTokenType.openBrace => '{',
    CssTokenType.closeBrace => '}',
    CssTokenType.badString => '<bad-string>',
    CssTokenType.badUrl => '<bad-url>',
    CssTokenType.eof => '<eof>',
  };

  static String _formatNumber(double n) =>
      n == n.truncateToDouble() ? n.toInt().toString() : n.toString();
}

/// Tokenizes [source] completely. Tokens are cheap; a stylesheet of a
/// few hundred kilobytes is a few hundred thousand of them, made once.
List<CssToken> tokenizeCss(String source) => _CssTokenizer(source).run();

class _CssTokenizer {
  _CssTokenizer(String source) : _s = _preprocess(source);

  final String _s;
  int _i = 0;

  /// §3.3: CR, FF and CRLF become LF; NUL becomes U+FFFD.
  static String _preprocess(String source) => source
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\f', '\n')
      .replaceAll('\u0000', '�');

  int _peek([int offset = 0]) {
    final i = _i + offset;
    return i < _s.length ? _s.codeUnitAt(i) : -1;
  }

  List<CssToken> run() {
    final out = <CssToken>[];
    while (true) {
      final token = _next();
      if (token.type == CssTokenType.eof) return out;
      out.add(token);
    }
  }

  CssToken _next() {
    _skipComments();
    final c = _peek();
    if (c < 0) return CssToken.eof;
    if (_isWhitespace(c)) {
      while (_isWhitespace(_peek())) {
        _i++;
      }
      return CssToken.whitespace;
    }
    switch (c) {
      case 0x22 || 0x27: // " '
        return _string(c);
      case 0x23: // #
        if (_isNameChar(_peek(1)) || _isValidEscape(_peek(1), _peek(2))) {
          final isId = _wouldStartIdent(_peek(1), _peek(2), _peek(3));
          _i++;
          return CssToken(CssTokenType.hash, value: _name(), isId: isId);
        }
        return _delim();
      case 0x28:
        _i++;
        return const CssToken(CssTokenType.openParen);
      case 0x29:
        _i++;
        return const CssToken(CssTokenType.closeParen);
      case 0x2B: // +
        if (_wouldStartNumber(c, _peek(1), _peek(2))) return _numeric();
        return _delim();
      case 0x2C:
        _i++;
        return const CssToken(CssTokenType.comma);
      case 0x2D: // -
        if (_wouldStartNumber(c, _peek(1), _peek(2))) return _numeric();
        if (_peek(1) == 0x2D && _peek(2) == 0x3E) {
          _i += 3;
          return const CssToken(CssTokenType.cdc);
        }
        if (_wouldStartIdent(c, _peek(1), _peek(2))) return _identLike();
        return _delim();
      case 0x2E: // .
        if (_wouldStartNumber(c, _peek(1), _peek(2))) return _numeric();
        return _delim();
      case 0x3A:
        _i++;
        return const CssToken(CssTokenType.colon);
      case 0x3B:
        _i++;
        return const CssToken(CssTokenType.semicolon);
      case 0x3C: // <
        if (_peek(1) == 0x21 && _peek(2) == 0x2D && _peek(3) == 0x2D) {
          _i += 4;
          return const CssToken(CssTokenType.cdo);
        }
        return _delim();
      case 0x40: // @
        if (_wouldStartIdent(_peek(1), _peek(2), _peek(3))) {
          _i++;
          return CssToken(CssTokenType.atKeyword, value: _name());
        }
        return _delim();
      case 0x5B:
        _i++;
        return const CssToken(CssTokenType.openSquare);
      case 0x5C: // \
        if (_isValidEscape(c, _peek(1))) return _identLike();
        return _delim();
      case 0x5D:
        _i++;
        return const CssToken(CssTokenType.closeSquare);
      case 0x7B:
        _i++;
        return const CssToken(CssTokenType.openBrace);
      case 0x7D:
        _i++;
        return const CssToken(CssTokenType.closeBrace);
    }
    if (_isDigit(c)) return _numeric();
    if (_isNameStart(c)) return _identLike();
    return _delim();
  }

  CssToken _delim() {
    final start = _i;
    _i += _isSurrogateLead(_peek()) ? 2 : 1;
    return CssToken(CssTokenType.delim, value: _s.substring(start, _i));
  }

  void _skipComments() {
    while (_peek() == 0x2F && _peek(1) == 0x2A) {
      final end = _s.indexOf('*/', _i + 2);
      _i = end < 0 ? _s.length : end + 2;
    }
  }

  /// §4.3.5. The quote has been peeked, not consumed.
  CssToken _string(int quote) {
    _i++;
    final buffer = StringBuffer();
    while (true) {
      final c = _peek();
      if (c < 0 || c == quote) {
        if (c == quote) _i++;
        return CssToken(CssTokenType.string, value: buffer.toString());
      }
      if (c == 0x0A) {
        // An unescaped newline: the string is bad and the newline stays.
        return const CssToken(CssTokenType.badString);
      }
      if (c == 0x5C) {
        final next = _peek(1);
        if (next < 0) {
          _i++;
          continue;
        }
        if (next == 0x0A) {
          _i += 2;
          continue;
        }
        _i++;
        buffer.writeCharCode(_escape());
        continue;
      }
      buffer.writeCharCode(c);
      _i++;
    }
  }

  /// §4.3.7, after the backslash: the escaped code point.
  int _escape() {
    final c = _peek();
    if (_isHexDigit(c)) {
      var value = 0;
      var digits = 0;
      while (digits < 6 && _isHexDigit(_peek())) {
        value = value * 16 + _hexValue(_peek());
        _i++;
        digits++;
      }
      if (_isWhitespace(_peek())) _i++;
      if (value == 0 ||
          value > 0x10FFFF ||
          (value >= 0xD800 && value <= 0xDFFF)) {
        return 0xFFFD;
      }
      return value;
    }
    if (c < 0) return 0xFFFD;
    _i += _isSurrogateLead(c) ? 2 : 1;
    return _isSurrogateLead(c) ? _combine(c, _s.codeUnitAt(_i - 1)) : c;
  }

  /// §4.3.11: a name, escapes decoded.
  String _name() {
    final buffer = StringBuffer();
    while (true) {
      final c = _peek();
      if (_isNameChar(c)) {
        buffer.writeCharCode(c);
        _i++;
      } else if (_isValidEscape(c, _peek(1))) {
        _i++;
        final code = _escape();
        if (code > 0xFFFF) {
          buffer.write(String.fromCharCode(code));
        } else {
          buffer.writeCharCode(code);
        }
      } else {
        return buffer.toString();
      }
    }
  }

  /// §4.3.4: an ident, a function or a URL.
  CssToken _identLike() {
    final name = _name();
    if (_peek() == 0x28) {
      _i++;
      if (name.toLowerCase() == 'url') {
        var j = _i;
        while (_isWhitespace(_peek(j - _i))) {
          j++;
        }
        final q = j < _s.length ? _s.codeUnitAt(j) : -1;
        if (q == 0x22 || q == 0x27) {
          return CssToken(CssTokenType.function, value: name);
        }
        return _url();
      }
      return CssToken(CssTokenType.function, value: name);
    }
    return CssToken(CssTokenType.ident, value: name);
  }

  /// §4.3.6, after `url(`: an unquoted URL.
  CssToken _url() {
    while (_isWhitespace(_peek())) {
      _i++;
    }
    final buffer = StringBuffer();
    while (true) {
      final c = _peek();
      if (c == 0x29) {
        _i++;
        return CssToken(CssTokenType.url, value: buffer.toString());
      }
      if (c < 0) return CssToken(CssTokenType.url, value: buffer.toString());
      if (_isWhitespace(c)) {
        while (_isWhitespace(_peek())) {
          _i++;
        }
        if (_peek() == 0x29 || _peek() < 0) {
          if (_peek() == 0x29) _i++;
          return CssToken(CssTokenType.url, value: buffer.toString());
        }
        return _badUrlRemnants();
      }
      if (c == 0x22 || c == 0x27 || c == 0x28 || _isNonPrintable(c)) {
        return _badUrlRemnants();
      }
      if (c == 0x5C) {
        if (_isValidEscape(c, _peek(1))) {
          _i++;
          buffer.writeCharCode(_escape());
          continue;
        }
        return _badUrlRemnants();
      }
      buffer.writeCharCode(c);
      _i++;
    }
  }

  /// §4.3.14: skip to the closing paren.
  CssToken _badUrlRemnants() {
    while (true) {
      final c = _peek();
      if (c < 0) return const CssToken(CssTokenType.badUrl);
      if (c == 0x29) {
        _i++;
        return const CssToken(CssTokenType.badUrl);
      }
      if (_isValidEscape(c, _peek(1))) {
        _i++;
        _escape();
      } else {
        _i++;
      }
    }
  }

  /// §4.3.3: a number, percentage or dimension.
  CssToken _numeric() {
    final start = _i;
    var isInteger = true;
    if (_peek() == 0x2B || _peek() == 0x2D) _i++;
    while (_isDigit(_peek())) {
      _i++;
    }
    if (_peek() == 0x2E && _isDigit(_peek(1))) {
      isInteger = false;
      _i += 2;
      while (_isDigit(_peek())) {
        _i++;
      }
    }
    final e = _peek();
    if (e == 0x45 || e == 0x65) {
      final sign = _peek(1) == 0x2B || _peek(1) == 0x2D ? 1 : 0;
      if (_isDigit(_peek(1 + sign))) {
        isInteger = false;
        _i += 2 + sign;
        while (_isDigit(_peek())) {
          _i++;
        }
      }
    }
    final value = double.parse(_s.substring(start, _i));
    if (_wouldStartIdent(_peek(), _peek(1), _peek(2))) {
      return CssToken(
        CssTokenType.dimension,
        number: value,
        isInteger: isInteger,
        unit: _name().toLowerCase(),
      );
    }
    if (_peek() == 0x25) {
      _i++;
      return CssToken(
        CssTokenType.percentage,
        number: value,
        isInteger: isInteger,
      );
    }
    return CssToken(CssTokenType.number, number: value, isInteger: isInteger);
  }

  static bool _isWhitespace(int c) => c == 0x20 || c == 0x09 || c == 0x0A;

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static bool _isHexDigit(int c) =>
      _isDigit(c) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66);

  static int _hexValue(int c) => _isDigit(c)
      ? c - 0x30
      : c >= 0x61
      ? c - 0x61 + 10
      : c - 0x41 + 10;

  static bool _isNameStart(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      c >= 0x80;

  static bool _isNameChar(int c) => _isNameStart(c) || _isDigit(c) || c == 0x2D;

  static bool _isNonPrintable(int c) =>
      (c >= 0 && c <= 0x08) ||
      c == 0x0B ||
      (c >= 0x0E && c <= 0x1F) ||
      c == 0x7F;

  static bool _isValidEscape(int c, int next) =>
      c == 0x5C && next != 0x0A && next >= 0;

  static bool _wouldStartIdent(int a, int b, int c) {
    if (a == 0x2D) {
      return _isNameStart(b) || b == 0x2D || _isValidEscape(b, c);
    }
    if (_isNameStart(a)) return true;
    return _isValidEscape(a, b);
  }

  static bool _wouldStartNumber(int a, int b, int c) {
    if (a == 0x2B || a == 0x2D) {
      return _isDigit(b) || (b == 0x2E && _isDigit(c));
    }
    if (a == 0x2E) return _isDigit(b);
    return _isDigit(a);
  }

  static bool _isSurrogateLead(int c) => c >= 0xD800 && c <= 0xDBFF;

  static int _combine(int lead, int trail) =>
      0x10000 + ((lead - 0xD800) << 10) + (trail - 0xDC00);
}
