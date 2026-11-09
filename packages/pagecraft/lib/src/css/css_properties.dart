/// The properties the layout understands: each with its grammar, its
/// inheritance and its initial value, plus the shorthands that expand
/// into them. A declaration whose value fails its grammar is dropped,
/// as the cascade requires; unknown properties are dropped too.
library;

import 'css_custom_properties.dart';
import 'css_syntax.dart';
import 'css_tokenizer.dart';
import 'css_values.dart';

/// A specified value: what a declaration says before the cascade.
sealed class CssValue {
  const CssValue();
}

/// A keyword, lowercased. The CSS-wide keywords `inherit`, `initial`
/// and `unset` are keywords too; the cascade treats them.
class CssKeyword extends CssValue {
  const CssKeyword(this.name);

  final String name;

  static const inherit = CssKeyword('inherit');
  static const initial = CssKeyword('initial');
  static const unset = CssKeyword('unset');

  bool get isCssWide =>
      name == 'inherit' || name == 'initial' || name == 'unset';

  @override
  bool operator ==(Object other) => other is CssKeyword && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

/// A custom property's value (`--name: value`): its tokens as written,
/// white space and all, for `var()` to substitute.
class CssCustomPropertyValue extends CssValue {
  const CssCustomPropertyValue(this.values);

  final List<CssComponentValue> values;

  @override
  String toString() => values.join();
}

/// A declaration that references a custom property: parsed once the
/// element's custom properties are known ([resolveCssPendingValue]).
/// [shorthand] is the shorthand it was written as, whose longhand this
/// is.
class CssPendingValue extends CssValue {
  const CssPendingValue(this.values, {this.shorthand});

  final List<CssComponentValue> values;
  final String? shorthand;

  @override
  String toString() => values.join();
}

class CssLengthValue extends CssValue {
  const CssLengthValue(this.length);

  final CssLength length;

  @override
  bool operator ==(Object other) =>
      other is CssLengthValue && other.length == length;

  @override
  int get hashCode => length.hashCode;

  @override
  String toString() => length.toString();
}

class CssNumberValue extends CssValue {
  const CssNumberValue(this.value);

  final double value;

  @override
  bool operator ==(Object other) =>
      other is CssNumberValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value.toString();
}

class CssColorValue extends CssValue {
  const CssColorValue(this.color);

  final CssColor color;

  @override
  bool operator ==(Object other) =>
      other is CssColorValue && other.color == color;

  @override
  int get hashCode => color.hashCode;

  @override
  String toString() => color.toString();
}

class CssFontFamilyValue extends CssValue {
  const CssFontFamilyValue(this.families);

  final List<String> families;

  @override
  String toString() => families.join(', ');
}

/// A string value, for `list-style-type: "•"`.
class CssStringValue extends CssValue {
  const CssStringValue(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is CssStringValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '"$value"';
}

/// `text-decoration-line`: which lines.
class CssTextDecorationValue extends CssValue {
  const CssTextDecorationValue({
    this.underline = false,
    this.overline = false,
    this.lineThrough = false,
  });

  final bool underline;
  final bool overline;
  final bool lineThrough;

  @override
  bool operator ==(Object other) =>
      other is CssTextDecorationValue &&
      other.underline == underline &&
      other.overline == overline &&
      other.lineThrough == lineThrough;

  @override
  int get hashCode => Object.hash(underline, overline, lineThrough);

  @override
  String toString() => [
    if (underline) 'underline',
    if (overline) 'overline',
    if (lineThrough) 'line-through',
  ].join(' ');
}

/// Two lengths: `border-spacing`'s horizontal and vertical spacing, or a
/// corner's horizontal and vertical radii.
class CssLengthPairValue extends CssValue {
  const CssLengthPairValue(this.first, this.second);

  final CssLength first;
  final CssLength second;

  @override
  bool operator ==(Object other) =>
      other is CssLengthPairValue &&
      other.first == first &&
      other.second == second;

  @override
  int get hashCode => Object.hash(first, second);

  @override
  String toString() => '$first $second';
}

/// `quotes`: open and close marks by nesting level, alternating.
class CssQuotesValue extends CssValue {
  const CssQuotesValue(this.marks);

  /// Level n opens with `marks[2n]` and closes with `marks[2n + 1]`.
  final List<String> marks;

  @override
  bool operator ==(Object other) {
    if (other is! CssQuotesValue || other.marks.length != marks.length) {
      return false;
    }
    for (var i = 0; i < marks.length; i++) {
      if (other.marks[i] != marks[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(marks);

  @override
  String toString() => marks.map((m) => '"$m"').join(' ');
}

/// One piece of generated content (`content`).
sealed class CssContentItem {
  const CssContentItem();
}

/// A string, as written.
class CssContentString extends CssContentItem {
  const CssContentString(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      other is CssContentString && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => '"$text"';
}

/// `attr(name)`: the originating element's attribute.
class CssContentAttr extends CssContentItem {
  const CssContentAttr(this.name);

  final String name;

  @override
  bool operator ==(Object other) =>
      other is CssContentAttr && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'attr($name)';
}

/// `counter(name, style)` or, with a [separator], `counters(…)`.
class CssContentCounter extends CssContentItem {
  const CssContentCounter(this.name, {this.style = 'decimal', this.separator});

  final String name;
  final String style;
  final String? separator;

  @override
  bool operator ==(Object other) =>
      other is CssContentCounter &&
      other.name == name &&
      other.style == style &&
      other.separator == separator;

  @override
  int get hashCode => Object.hash(name, style, separator);

  @override
  String toString() => separator == null
      ? 'counter($name, $style)'
      : 'counters($name, "$separator", $style)';
}

/// `open-quote`, `close-quote` and their `no-` forms, which move the
/// quote depth without a mark.
class CssContentQuote extends CssContentItem {
  const CssContentQuote({required this.open, this.mark = true});

  final bool open;
  final bool mark;

  @override
  bool operator ==(Object other) =>
      other is CssContentQuote && other.open == open && other.mark == mark;

  @override
  int get hashCode => Object.hash(open, mark);

  @override
  String toString() => '${mark ? '' : 'no-'}${open ? 'open' : 'close'}-quote';
}

/// `url(…)`: an image, relative to [base], the style sheet's address
/// (set by the cascade; null until then).
class CssContentUrl extends CssContentItem {
  const CssContentUrl(this.url, {this.base});

  final String url;
  final String? base;

  @override
  bool operator ==(Object other) =>
      other is CssContentUrl && other.url == url && other.base == base;

  @override
  int get hashCode => Object.hash(url, base);

  @override
  String toString() => 'url($url)';
}

/// `background-image: url(…)`, relative to [base], the style sheet's
/// address (set by the cascade; null until then).
class CssImageUrlValue extends CssValue {
  const CssImageUrlValue(this.url, {this.base});

  final String url;
  final String? base;

  @override
  bool operator ==(Object other) =>
      other is CssImageUrlValue && other.url == url && other.base == base;

  @override
  int get hashCode => Object.hash(url, base);

  @override
  String toString() => 'url($url)';
}

/// `background-size` as lengths: null sides are `auto`.
class CssBackgroundSizeValue extends CssValue {
  const CssBackgroundSizeValue(this.width, this.height);

  final CssLength? width;
  final CssLength? height;

  @override
  bool operator ==(Object other) =>
      other is CssBackgroundSizeValue &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width ?? 'auto'} ${height ?? 'auto'}';
}

/// `background-repeat`: whether the image repeats across and down.
class CssBackgroundRepeatValue extends CssValue {
  const CssBackgroundRepeatValue({required this.x, required this.y});

  final bool x;
  final bool y;

  @override
  bool operator ==(Object other) =>
      other is CssBackgroundRepeatValue && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => switch ((x, y)) {
    (true, true) => 'repeat',
    (true, false) => 'repeat-x',
    (false, true) => 'repeat-y',
    (false, false) => 'no-repeat',
  };
}

/// `background-position`: keywords as percentages.
class CssBackgroundPositionValue extends CssValue {
  const CssBackgroundPositionValue(this.x, this.y);

  final CssLength x;
  final CssLength y;

  @override
  bool operator ==(Object other) =>
      other is CssBackgroundPositionValue && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '$x $y';
}

/// `content`: what a `::before` or `::after` shows.
class CssContentValue extends CssValue {
  const CssContentValue(this.items);

  final List<CssContentItem> items;

  @override
  bool operator ==(Object other) {
    if (other is! CssContentValue || other.items.length != items.length) {
      return false;
    }
    for (var i = 0; i < items.length; i++) {
      if (other.items[i] != items[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(items);

  @override
  String toString() => items.join(' ');
}

/// `counter-reset`, `counter-increment`, `counter-set`: counters and
/// their values, in order.
class CssCountersValue extends CssValue {
  const CssCountersValue(this.counters);

  final List<(String, int)> counters;

  @override
  bool operator ==(Object other) {
    if (other is! CssCountersValue ||
        other.counters.length != counters.length) {
      return false;
    }
    for (var i = 0; i < counters.length; i++) {
      if (other.counters[i] != counters[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(counters);

  @override
  String toString() => counters.map((c) => '${c.$1} ${c.$2}').join(' ');
}

typedef CssValueParser = CssValue? Function(List<CssComponentValue> values);

/// One longhand property.
class CssPropertyDefinition {
  const CssPropertyDefinition(
    this.name, {
    required this.inherited,
    required this.initial,
    required this.parse,
    this.physicalName,
  });

  final String name;
  final bool inherited;
  final CssValue initial;
  final CssValueParser parse;

  /// For a flow-relative property (`margin-inline-start`, `inline-size`):
  /// the physical property it sets in horizontal text, left to right or
  /// [rtl]. The cascade resolves it with the element's direction, so a
  /// later physical declaration still overrides an earlier logical one.
  /// Null for physical properties.
  final String Function({required bool rtl})? physicalName;
}

/// A flow-relative edge in horizontal text: the inline sides follow the
/// direction, the block sides are the top and the bottom.
enum CssFlowSide {
  inlineStart('inline-start'),
  inlineEnd('inline-end'),
  blockStart('block-start'),
  blockEnd('block-end');

  const CssFlowSide(this.css);

  /// The name in property names: `inline-start`.
  final String css;

  /// The physical edge in left-to-right or [rtl] text.
  String edge({required bool rtl}) => switch (this) {
    inlineStart => rtl ? 'right' : 'left',
    inlineEnd => rtl ? 'left' : 'right',
    blockStart => 'top',
    blockEnd => 'bottom',
  };
}

/// A parsed longhand declaration.
class CssParsedDeclaration {
  const CssParsedDeclaration(
    this.property,
    this.value, {
    this.isImportant = false,
  });

  final CssPropertyDefinition property;
  final CssValue value;
  final bool isImportant;

  @override
  String toString() =>
      '${property.name}: $value${isImportant ? ' !important' : ''}';
}

/// Parses a declaration into longhands: one for a longhand, several for
/// a shorthand, none when the property is unknown or the value invalid.
/// A custom property keeps its value as written; a value with `var()`
/// in it waits for the cascade ([CssPendingValue]).
List<CssParsedDeclaration> parseCssDeclaration(CssDeclaration declaration) {
  final name = _aliases[declaration.name] ?? declaration.name;
  if (name.startsWith('--')) {
    return [
      CssParsedDeclaration(
        CssPropertyDefinition(
          name,
          inherited: true,
          initial: CssKeyword.initial,
          parse: (_) => null,
        ),
        CssCustomPropertyValue(declaration.value),
        isImportant: declaration.isImportant,
      ),
    ];
  }
  final values = cssWithoutWhitespace(declaration.value);
  if (values.isEmpty) return const [];
  if (cssContainsVar(values)) {
    final longhand = cssProperties[name];
    final shorthand = _shorthands[name];
    return [
      if (longhand != null)
        CssParsedDeclaration(
          longhand,
          CssPendingValue(declaration.value),
          isImportant: declaration.isImportant,
        )
      else if (shorthand != null)
        for (final longhand in shorthand.longhands)
          CssParsedDeclaration(
            cssProperties[longhand]!,
            CssPendingValue(declaration.value, shorthand: name),
            isImportant: declaration.isImportant,
          ),
    ];
  }
  final wide = _cssWideKeyword(values);
  final longhand = cssProperties[name];
  if (longhand != null) {
    final value = wide ?? longhand.parse(values);
    if (value == null) return const [];
    return [
      CssParsedDeclaration(
        longhand,
        value,
        isImportant: declaration.isImportant,
      ),
    ];
  }
  final shorthand = _shorthands[name];
  if (shorthand == null) return const [];
  final expanded = wide != null
      ? [for (final p in shorthand.longhands) (cssProperties[p]!, wide)]
      : shorthand.expand(values);
  if (expanded == null) return const [];
  return [
    for (final (property, value) in expanded)
      CssParsedDeclaration(
        property,
        value,
        isImportant: declaration.isImportant,
      ),
  ];
}

/// [pending]'s value for [longhand] with the custom properties in
/// [properties] substituted, parsed as written (a shorthand's part for
/// it); `unset` when it does not parse, as CSS makes a declaration
/// invalid at computed-value time.
CssValue resolveCssPendingValue(
  CssPendingValue pending,
  String longhand,
  CssCustomProperties properties,
) {
  final substituted = properties.substitute(pending.values);
  if (substituted == null) return CssKeyword.unset;
  final values = cssWithoutWhitespace(substituted);
  if (values.isEmpty) return CssKeyword.unset;
  final wide = _cssWideKeyword(values);
  if (wide != null) return wide;
  final shorthand = pending.shorthand;
  if (shorthand == null) {
    return cssProperties[longhand]?.parse(values) ?? CssKeyword.unset;
  }
  for (final (property, value)
      in _shorthands[shorthand]?.expand(values) ??
          const <(CssPropertyDefinition, CssValue)>[]) {
    if (property.name == longhand ||
        property.physicalName?.call(rtl: false) == longhand ||
        property.physicalName?.call(rtl: true) == longhand) {
      return value;
    }
  }
  return CssKeyword.unset;
}

/// Prefixed and legacy names browsers still read, to the property each
/// sets. `-epub-*` are WebKit's EPUB 3 aliases.
const _aliases = {
  '-webkit-hyphens': 'hyphens',
  '-epub-hyphens': 'hyphens',
  '-moz-hyphens': 'hyphens',
  '-ms-hyphens': 'hyphens',
  'word-wrap': 'overflow-wrap',
  '-ms-word-break': 'word-break',
  '-webkit-writing-mode': 'writing-mode',
  '-epub-writing-mode': 'writing-mode',
  '-epub-text-transform': 'text-transform',
  '-webkit-text-decoration-line': 'text-decoration-line',
  '-webkit-border-radius': 'border-radius',
  '-moz-border-radius': 'border-radius',
  '-webkit-box-sizing': 'box-sizing',
  '-moz-box-sizing': 'box-sizing',
};

CssKeyword? _cssWideKeyword(List<CssComponentValue> values) {
  final ident = cssIdentOf(values);
  return switch (ident) {
    'inherit' => CssKeyword.inherit,
    'initial' => CssKeyword.initial,
    'unset' => CssKeyword.unset,
    _ => null,
  };
}

// Grammar pieces.

CssValueParser _keywords(Set<String> allowed) => (values) {
  final ident = cssIdentOf(values);
  return ident != null && allowed.contains(ident) ? CssKeyword(ident) : null;
};

CssValue? _length(
  List<CssComponentValue> values, {
  bool allowPercent = true,
  bool allowNegative = true,
  Set<String> keywords = const {},
}) {
  if (values.length != 1) return null;
  final ident = cssIdentOf(values);
  if (ident != null) return keywords.contains(ident) ? CssKeyword(ident) : null;
  final length = CssLength.parse(values.single, allowPercent: allowPercent);
  if (length == null || (!allowNegative && length.value < 0)) return null;
  return CssLengthValue(length);
}

CssValue? _color(List<CssComponentValue> values) {
  if (values.length != 1) return null;
  final color = CssColor.parse(values.single);
  return color == null ? null : CssColorValue(color);
}

CssValue? _fontSize(List<CssComponentValue> values) => _length(
  values,
  allowNegative: false,
  keywords: const {
    'xx-small',
    'x-small',
    'small',
    'medium',
    'large',
    'x-large',
    'xx-large',
    'xxx-large',
    'larger',
    'smaller',
  },
);

CssValue? _fontWeight(List<CssComponentValue> values) {
  if (values.length != 1) return null;
  final ident = cssIdentOf(values);
  if (ident != null) {
    return const {'normal', 'bold', 'bolder', 'lighter'}.contains(ident)
        ? CssKeyword(ident)
        : null;
  }
  final v = values.single;
  if (v is CssTokenValue && v.token.type == CssTokenType.number) {
    final n = v.token.number;
    return n >= 1 && n <= 1000 ? CssNumberValue(n) : null;
  }
  return null;
}

CssValue? _lineHeight(List<CssComponentValue> values) {
  if (values.length != 1) return null;
  if (cssIdentOf(values) == 'normal') return const CssKeyword('normal');
  final v = values.single;
  if (v is CssTokenValue && v.token.type == CssTokenType.number) {
    return v.token.number >= 0 ? CssNumberValue(v.token.number) : null;
  }
  return _length(values, allowNegative: false);
}

CssValue? _fontFamily(List<CssComponentValue> values) {
  final families = cssParseFontFamilies(values);
  return families == null ? null : CssFontFamilyValue(families);
}

CssValue? _borderWidth(List<CssComponentValue> values) {
  final ident = cssIdentOf(values);
  return switch (ident) {
    'thin' => const CssLengthValue(CssLength.px(1)),
    'medium' => const CssLengthValue(CssLength.px(3)),
    'thick' => const CssLengthValue(CssLength.px(5)),
    _ => _length(values, allowPercent: false, allowNegative: false),
  };
}

CssValue? _textDecoration(List<CssComponentValue> values) {
  if (cssIdentOf(values) == 'none') return const CssTextDecorationValue();
  var underline = false;
  var overline = false;
  var lineThrough = false;
  var any = false;
  for (final v in values) {
    if (v is! CssTokenValue) return null;
    final t = v.token;
    switch (t.type == CssTokenType.ident ? t.value.toLowerCase() : null) {
      case 'underline':
        underline = true;
        any = true;
      case 'overline':
        overline = true;
        any = true;
      case 'line-through':
        lineThrough = true;
        any = true;
      case 'blink':
        any = true;
      case 'solid' || 'double' || 'dotted' || 'dashed' || 'wavy':
        // A decoration style, in the shorthand; accepted and ignored.
        break;
      default:
        // A decoration color, in the shorthand.
        if (CssColor.parse(v) == null) return null;
    }
  }
  return any
      ? CssTextDecorationValue(
          underline: underline,
          overline: overline,
          lineThrough: lineThrough,
        )
      : null;
}

CssValue? _listStyleType(List<CssComponentValue> values) {
  if (values.length != 1) return null;
  final v = values.single;
  if (v is CssTokenValue && v.token.type == CssTokenType.string) {
    return CssStringValue(v.token.value);
  }
  final ident = cssIdentOf(values);
  return ident == null ? null : CssKeyword(ident);
}

CssValue? _verticalAlign(List<CssComponentValue> values) => _length(
  values,
  keywords: const {
    'baseline',
    'sub',
    'super',
    'text-top',
    'text-bottom',
    'middle',
    'top',
    'bottom',
  },
);

CssValue? _display(List<CssComponentValue> values) {
  final ident = cssIdentOf(values);
  if (ident == null) return null;
  return switch (ident) {
    'flex' || 'grid' || 'flow-root' || 'block' => const CssKeyword('block'),
    'inline-flex' ||
    'inline-grid' ||
    'inline-block' => const CssKeyword('inline-block'),
    'inline' ||
    'none' ||
    'list-item' ||
    'table' ||
    'inline-table' ||
    'table-row-group' ||
    'table-header-group' ||
    'table-footer-group' ||
    'table-row' ||
    'table-cell' ||
    'table-caption' ||
    'table-column' ||
    'table-column-group' ||
    'ruby' ||
    'ruby-base' ||
    'ruby-text' ||
    'contents' => CssKeyword(ident),
    _ => null,
  };
}

/// `break-before: page` and friends map onto the page-break values.
CssValue? _breakValue(List<CssComponentValue> values) {
  final ident = cssIdentOf(values);
  return switch (ident) {
    'auto' || 'always' || 'avoid' || 'left' || 'right' => CssKeyword(ident!),
    'page' || 'column' || 'region' => const CssKeyword('always'),
    'avoid-page' ||
    'avoid-column' ||
    'avoid-region' => const CssKeyword('avoid'),
    'recto' => const CssKeyword('right'),
    'verso' => const CssKeyword('left'),
    _ => null,
  };
}

const _edges = ['top', 'right', 'bottom', 'left'];

const _borderStyles = {
  'none',
  'hidden',
  'solid',
  'dashed',
  'dotted',
  'double',
  'groove',
  'ridge',
  'inset',
  'outset',
};

/// The longhands, by name.
final Map<String, CssPropertyDefinition> cssProperties = {
  for (final p in _definitions) p.name: p,
  for (final p in _flowRelativeDefinitions) p.name: p,
};

/// `margin-inline-start` and its kin for every edge property, and the
/// logical sizes (`inline-size` is `width` in horizontal text): parsed as
/// their physical properties are.
final List<CssPropertyDefinition> _flowRelativeDefinitions = () {
  final physical = {for (final p in _definitions) p.name: p};
  CssPropertyDefinition alias(String name, String Function(bool rtl) to) {
    final target = physical[to(false)]!;
    return CssPropertyDefinition(
      name,
      inherited: target.inherited,
      initial: target.initial,
      parse: target.parse,
      physicalName: ({required rtl}) => to(rtl),
    );
  }

  return [
    for (final side in CssFlowSide.values)
      for (final (prefix, suffix) in const [
        ('margin-', ''),
        ('padding-', ''),
        ('border-', '-width'),
        ('border-', '-style'),
        ('border-', '-color'),
      ])
        alias(
          '$prefix${side.css}$suffix',
          (rtl) => '$prefix${side.edge(rtl: rtl)}$suffix',
        ),
    for (final (logical, size) in const [
      ('inline-size', 'width'),
      ('block-size', 'height'),
      ('min-inline-size', 'min-width'),
      ('min-block-size', 'min-height'),
      ('max-inline-size', 'max-width'),
      ('max-block-size', 'max-height'),
    ])
      alias(logical, (_) => size),
  ];
}();

final List<CssPropertyDefinition> _definitions = [
  CssPropertyDefinition(
    'font-family',
    inherited: true,
    initial: const CssFontFamilyValue(['serif']),
    parse: _fontFamily,
  ),
  CssPropertyDefinition(
    'font-size',
    inherited: true,
    initial: const CssKeyword('medium'),
    parse: _fontSize,
  ),
  CssPropertyDefinition(
    'font-style',
    inherited: true,
    initial: const CssKeyword('normal'),
    parse: _keywords(const {'normal', 'italic', 'oblique'}),
  ),
  CssPropertyDefinition(
    'font-weight',
    inherited: true,
    initial: const CssKeyword('normal'),
    parse: _fontWeight,
  ),
  CssPropertyDefinition(
    'font-variant',
    inherited: true,
    initial: const CssKeyword('normal'),
    parse: _keywords(const {'normal', 'small-caps'}),
  ),
  CssPropertyDefinition(
    'font-optical-sizing',
    inherited: true,
    initial: const CssKeyword('auto'),
    parse: _keywords(const {'auto', 'none'}),
  ),
  CssPropertyDefinition(
    'color',
    inherited: true,
    initial: const CssColorValue(CssColor.black),
    parse: _color,
  ),
  CssPropertyDefinition(
    'background-color',
    inherited: false,
    initial: const CssColorValue(CssColor.transparent),
    parse: _color,
  ),
  CssPropertyDefinition(
    'background-image',
    inherited: false,
    initial: const CssKeyword('none'),
    parse: _backgroundImage,
  ),
  CssPropertyDefinition(
    'background-size',
    inherited: false,
    initial: const CssKeyword('auto'),
    parse: _backgroundSize,
  ),
  CssPropertyDefinition(
    'background-repeat',
    inherited: false,
    initial: const CssBackgroundRepeatValue(x: true, y: true),
    parse: _backgroundRepeat,
  ),
  CssPropertyDefinition(
    'background-position',
    inherited: false,
    initial: const CssBackgroundPositionValue(
      CssLength.percent(0),
      CssLength.percent(0),
    ),
    parse: _backgroundPosition,
  ),
  CssPropertyDefinition(
    'text-align',
    inherited: true,
    initial: const CssKeyword('start'),
    parse: _textAlign,
  ),
  CssPropertyDefinition(
    'text-indent',
    inherited: true,
    initial: const CssLengthValue(CssLength.zero),
    parse: (values) => _length(values),
  ),
  CssPropertyDefinition(
    'line-height',
    inherited: true,
    initial: const CssKeyword('normal'),
    parse: _lineHeight,
  ),
  for (final edge in _edges)
    CssPropertyDefinition(
      'margin-$edge',
      inherited: false,
      initial: const CssLengthValue(CssLength.zero),
      parse: (values) => _length(values, keywords: const {'auto'}),
    ),
  for (final edge in _edges)
    CssPropertyDefinition(
      'padding-$edge',
      inherited: false,
      initial: const CssLengthValue(CssLength.zero),
      parse: (values) => _length(values, allowNegative: false),
    ),
  for (final edge in _edges)
    CssPropertyDefinition(
      'border-$edge-width',
      inherited: false,
      initial: const CssLengthValue(CssLength.px(3)),
      parse: _borderWidth,
    ),
  for (final edge in _edges)
    CssPropertyDefinition(
      'border-$edge-style',
      inherited: false,
      initial: const CssKeyword('none'),
      parse: _keywords(_borderStyles),
    ),
  for (final edge in _edges)
    CssPropertyDefinition(
      'border-$edge-color',
      inherited: false,
      initial: const CssColorValue(CssColor.currentColor),
      parse: _color,
    ),
  CssPropertyDefinition(
    'display',
    inherited: false,
    initial: const CssKeyword('inline'),
    parse: _display,
  ),
  CssPropertyDefinition(
    'page-break-before',
    inherited: false,
    initial: const CssKeyword('auto'),
    parse: _breakValue,
  ),
  CssPropertyDefinition(
    'page-break-after',
    inherited: false,
    initial: const CssKeyword('auto'),
    parse: _breakValue,
  ),
  CssPropertyDefinition(
    'page-break-inside',
    inherited: false,
    initial: const CssKeyword('auto'),
    parse: _keywords(const {'auto', 'avoid', 'avoid-page', 'avoid-column'}),
  ),
  for (final dimension in ['width', 'height'])
    CssPropertyDefinition(
      dimension,
      inherited: false,
      initial: const CssKeyword('auto'),
      parse: (values) => _length(
        values,
        allowNegative: false,
        keywords: dimension == 'width'
            ? const {'auto', 'min-content', 'max-content', 'fit-content'}
            : const {'auto'},
      ),
    ),
  for (final axis in ['overflow-x', 'overflow-y'])
    CssPropertyDefinition(
      axis,
      inherited: false,
      initial: const CssKeyword('visible'),
      parse: _keywords(_overflowKeywords),
    ),
  for (final dimension in ['max-width', 'max-height'])
    CssPropertyDefinition(
      dimension,
      inherited: false,
      initial: const CssKeyword('none'),
      parse: (values) =>
          _length(values, allowNegative: false, keywords: const {'none'}),
    ),
  for (final dimension in ['min-width', 'min-height'])
    CssPropertyDefinition(
      dimension,
      inherited: false,
      initial: const CssLengthValue(CssLength.zero),
      parse: (values) =>
          _length(values, allowNegative: false, keywords: const {'auto'}),
    ),
  CssPropertyDefinition(
    'float',
    inherited: false,
    initial: const CssKeyword('none'),
    parse: _keywords(const {
      'none',
      'left',
      'right',
      'inline-start',
      'inline-end',
    }),
  ),
  CssPropertyDefinition(
    'clear',
    inherited: false,
    initial: const CssKeyword('none'),
    parse: _keywords(const {
      'none',
      'left',
      'right',
      'both',
      'inline-start',
      'inline-end',
    }),
  ),
  CssPropertyDefinition(
    'text-decoration-line',
    inherited: false,
    initial: const CssTextDecorationValue(),
    parse: _textDecoration,
  ),
  CssPropertyDefinition(
    'letter-spacing',
    inherited: true,
    initial: const CssKeyword('normal'),
    parse: (values) =>
        _length(values, allowPercent: false, keywords: const {'normal'}),
  ),
  CssPropertyDefinition(
    'word-spacing',
    inherited: true,
    initial: const CssKeyword('normal'),
    parse: (values) => _length(values, keywords: const {'normal'}),
  ),
  CssPropertyDefinition(
    'white-space',
    inherited: true,
    initial: const CssKeyword('normal'),
    parse: _keywords(const {
      'normal',
      'nowrap',
      'pre',
      'pre-wrap',
      'pre-line',
      'break-spaces',
    }),
  ),
  CssPropertyDefinition(
    'vertical-align',
    inherited: false,
    initial: const CssKeyword('baseline'),
    parse: _verticalAlign,
  ),
  CssPropertyDefinition(
    'text-transform',
    inherited: true,
    initial: const CssKeyword('none'),
    parse: _keywords(const {
      'none',
      'capitalize',
      'uppercase',
      'lowercase',
      'full-width',
    }),
  ),
  CssPropertyDefinition(
    'hyphens',
    inherited: true,
    initial: const CssKeyword('manual'),
    parse: _keywords(const {'none', 'manual', 'auto'}),
  ),
  CssPropertyDefinition(
    'direction',
    inherited: true,
    initial: const CssKeyword('ltr'),
    parse: _keywords(const {'ltr', 'rtl'}),
  ),
  CssPropertyDefinition(
    'unicode-bidi',
    inherited: false,
    initial: const CssKeyword('normal'),
    parse: _keywords(const {
      'normal',
      'embed',
      'isolate',
      'bidi-override',
      'isolate-override',
      'plaintext',
    }),
  ),
  CssPropertyDefinition(
    'list-style-type',
    inherited: true,
    initial: const CssKeyword('disc'),
    parse: _listStyleType,
  ),
  CssPropertyDefinition(
    'visibility',
    inherited: true,
    initial: const CssKeyword('visible'),
    parse: _keywords(const {'visible', 'hidden', 'collapse'}),
  ),
  CssPropertyDefinition(
    'widows',
    inherited: true,
    initial: const CssNumberValue(2),
    parse: _positiveInteger,
  ),
  CssPropertyDefinition(
    'orphans',
    inherited: true,
    initial: const CssNumberValue(2),
    parse: _positiveInteger,
  ),
  CssPropertyDefinition(
    'writing-mode',
    inherited: true,
    initial: const CssKeyword('horizontal-tb'),
    parse: _keywords(const {
      'horizontal-tb',
      'vertical-rl',
      'vertical-lr',
      'sideways-rl',
      'sideways-lr',
      // SVG 1.1's values, which EPUB 3 style sheets still use.
      'lr',
      'lr-tb',
      'rl',
      'rl-tb',
      'tb',
      'tb-rl',
    }),
  ),
  CssPropertyDefinition(
    'overflow-wrap',
    inherited: true,
    initial: const CssKeyword('normal'),
    parse: _keywords(const {'normal', 'break-word', 'anywhere'}),
  ),
  CssPropertyDefinition(
    'word-break',
    inherited: true,
    initial: const CssKeyword('normal'),
    parse: _keywords(const {
      'normal',
      'break-all',
      'keep-all',
      'break-word',
      'auto-phrase',
    }),
  ),
  CssPropertyDefinition(
    'border-collapse',
    inherited: true,
    initial: const CssKeyword('separate'),
    parse: _keywords(const {'separate', 'collapse'}),
  ),
  CssPropertyDefinition(
    'border-spacing',
    inherited: true,
    initial: const CssLengthPairValue(CssLength.zero, CssLength.zero),
    parse: (values) => _lengthPair(values, allowPercent: false),
  ),
  CssPropertyDefinition(
    'caption-side',
    inherited: true,
    initial: const CssKeyword('top'),
    parse: _keywords(const {'top', 'bottom', 'block-start', 'block-end'}),
  ),
  CssPropertyDefinition(
    'position',
    inherited: false,
    initial: const CssKeyword('static'),
    parse: _keywords(const {
      'static',
      'relative',
      'absolute',
      'fixed',
      'sticky',
    }),
  ),
  for (final edge in _edges)
    CssPropertyDefinition(
      edge,
      inherited: false,
      initial: const CssKeyword('auto'),
      parse: (values) => _length(values, keywords: const {'auto'}),
    ),
  for (final corner in _corners)
    CssPropertyDefinition(
      'border-$corner-radius',
      inherited: false,
      initial: const CssLengthPairValue(CssLength.zero, CssLength.zero),
      parse: (values) => _lengthPair(values, allowPercent: true),
    ),
  CssPropertyDefinition(
    'box-sizing',
    inherited: false,
    initial: const CssKeyword('content-box'),
    parse: _keywords(const {'content-box', 'border-box'}),
  ),
  CssPropertyDefinition(
    'quotes',
    inherited: true,
    initial: const CssKeyword('auto'),
    parse: _quotes,
  ),
  CssPropertyDefinition(
    'list-style-position',
    inherited: true,
    initial: const CssKeyword('outside'),
    parse: _keywords(const {'inside', 'outside'}),
  ),
  CssPropertyDefinition(
    'content',
    inherited: false,
    initial: const CssKeyword('normal'),
    parse: _content,
  ),
  CssPropertyDefinition(
    'counter-reset',
    inherited: false,
    initial: const CssKeyword('none'),
    parse: _counters(0),
  ),
  CssPropertyDefinition(
    'counter-increment',
    inherited: false,
    initial: const CssKeyword('none'),
    parse: _counters(1),
  ),
  CssPropertyDefinition(
    'counter-set',
    inherited: false,
    initial: const CssKeyword('none'),
    parse: _counters(0),
  ),
];

/// Corners in the order `border-radius` lists them.
const _corners = ['top-left', 'top-right', 'bottom-right', 'bottom-left'];

CssValue? _textAlign(List<CssComponentValue> values) {
  final ident = cssIdentOf(values);
  return switch (ident) {
    'left' ||
    'right' ||
    'center' ||
    'justify' ||
    'start' ||
    'end' => CssKeyword(ident!),
    // The parent's alignment, as inheriting it gives.
    'match-parent' || '-webkit-match-parent' => CssKeyword.inherit,
    _ => null,
  };
}

/// One or two non-negative lengths: a corner's radii (percentages of the
/// box) or `border-spacing` (no percentages).
CssValue? _lengthPair(
  List<CssComponentValue> values, {
  required bool allowPercent,
}) {
  if (values.isEmpty || values.length > 2) return null;
  final lengths = [
    for (final v in values) CssLength.parse(v, allowPercent: allowPercent),
  ];
  if (lengths.any((l) => l == null || l.value < 0)) return null;
  return CssLengthPairValue(lengths.first!, lengths.last!);
}

CssValue? _quotes(List<CssComponentValue> values) {
  final ident = cssIdentOf(values);
  if (ident == 'none' || ident == 'auto') return CssKeyword(ident!);
  if (values.isEmpty || values.length.isOdd) return null;
  final marks = <String>[];
  for (final v in values) {
    if (v is! CssTokenValue || v.token.type != CssTokenType.string) {
      return null;
    }
    marks.add(v.token.value);
  }
  return CssQuotesValue(marks);
}

/// `content`: `normal`, `none`, or strings, `attr()`, counters, quotes
/// and images. Anything else (`target-counter()`, `leader()`, print
/// features browsers drop) invalidates the declaration.
CssValue? _content(List<CssComponentValue> values) {
  final ident = cssIdentOf(values);
  if (ident == 'normal' || ident == 'none') return CssKeyword(ident!);
  if (values.isEmpty) return null;
  final items = <CssContentItem>[];
  for (final v in values) {
    switch (v) {
      case CssTokenValue(:final token) when token.type == CssTokenType.string:
        items.add(CssContentString(token.value));
      case CssTokenValue(:final token) when token.type == CssTokenType.url:
        items.add(CssContentUrl(token.value));
      case CssTokenValue(:final token) when token.type == CssTokenType.ident:
        final item = switch (token.value.toLowerCase()) {
          'open-quote' => const CssContentQuote(open: true),
          'close-quote' => const CssContentQuote(open: false),
          'no-open-quote' => const CssContentQuote(open: true, mark: false),
          'no-close-quote' => const CssContentQuote(open: false, mark: false),
          _ => null,
        };
        if (item == null) return null;
        items.add(item);
      case CssFunctionValue(:final name, :final arguments):
        final item = _contentFunction(
          name.toLowerCase(),
          cssWithoutWhitespace(arguments),
        );
        if (item == null) return null;
        items.add(item);
      default:
        return null;
    }
  }
  return CssContentValue(items);
}

CssContentItem? _contentFunction(String name, List<CssComponentValue> args) {
  final parts = cssSplitOnCommas(args).map(cssWithoutWhitespace).toList();
  String? identAt(int i) => i < parts.length ? cssIdentOf(parts[i]) : null;
  switch (name) {
    case 'url':
      if (parts.length != 1 || parts.single.length != 1) return null;
      final v = parts.single.single;
      return v is CssTokenValue && v.token.type == CssTokenType.string
          ? CssContentUrl(v.token.value)
          : null;
    case 'attr':
      final attribute = identAt(0);
      return attribute == null || parts.length != 1
          ? null
          : CssContentAttr(attribute);
    case 'counter':
      final counter = identAt(0);
      if (counter == null || parts.length > 2) return null;
      return CssContentCounter(
        counter,
        style: parts.length == 2 ? identAt(1) ?? 'decimal' : 'decimal',
      );
    case 'counters':
      final counter = identAt(0);
      if (counter == null || parts.length < 2 || parts.length > 3) return null;
      final separator = parts[1].length == 1 ? parts[1].single : null;
      if (separator is! CssTokenValue ||
          separator.token.type != CssTokenType.string) {
        return null;
      }
      return CssContentCounter(
        counter,
        style: parts.length == 3 ? identAt(2) ?? 'decimal' : 'decimal',
        separator: separator.token.value,
      );
    default:
      return null;
  }
}

/// `none`, or counter names each with an optional integer
/// ([defaultValue] when left out).
CssValueParser _counters(int defaultValue) => (values) {
  if (cssIdentOf(values) == 'none') return const CssKeyword('none');
  if (values.isEmpty) return null;
  final counters = <(String, int)>[];
  for (final v in values) {
    if (v is! CssTokenValue) return null;
    final t = v.token;
    if (t.type == CssTokenType.ident) {
      final name = t.value;
      if (const {'none', 'inherit', 'initial', 'unset'}.contains(name)) {
        return null;
      }
      counters.add((name, defaultValue));
    } else if (t.type == CssTokenType.number && t.isInteger) {
      if (counters.isEmpty) return null;
      final (name, _) = counters.removeLast();
      counters.add((name, t.number.toInt()));
    } else {
      return null;
    }
  }
  return CssCountersValue(counters);
};

CssValue? _positiveInteger(List<CssComponentValue> values) {
  if (values.length != 1) return null;
  final v = values.single;
  if (v is CssTokenValue &&
      v.token.type == CssTokenType.number &&
      v.token.isInteger &&
      v.token.number >= 1) {
    return CssNumberValue(v.token.number);
  }
  return null;
}

class _Shorthand {
  const _Shorthand(this.longhands, this.expand);

  final List<String> longhands;
  final List<(CssPropertyDefinition, CssValue)>? Function(
    List<CssComponentValue> values,
  )
  expand;
}

List<(CssPropertyDefinition, CssValue)>? _expandEdges(
  String prefix,
  String suffix,
  List<CssComponentValue> values,
  CssValueParser parse,
) {
  if (values.isEmpty || values.length > 4) return null;
  final parsed = <CssValue>[];
  for (final v in values) {
    final value = parse([v]);
    if (value == null) return null;
    parsed.add(value);
  }
  final (top, right, bottom, left) = switch (parsed.length) {
    1 => (parsed[0], parsed[0], parsed[0], parsed[0]),
    2 => (parsed[0], parsed[1], parsed[0], parsed[1]),
    3 => (parsed[0], parsed[1], parsed[2], parsed[1]),
    _ => (parsed[0], parsed[1], parsed[2], parsed[3]),
  };
  return [
    (cssProperties['${prefix}top$suffix']!, top),
    (cssProperties['${prefix}right$suffix']!, right),
    (cssProperties['${prefix}bottom$suffix']!, bottom),
    (cssProperties['${prefix}left$suffix']!, left),
  ];
}

/// `margin-inline`, `padding-block` …: the start value, then the end one
/// (the start's when there is one value).
List<(CssPropertyDefinition, CssValue)>? _expandStartEnd(
  String prefix,
  String suffix,
  List<CssComponentValue> values,
  CssValueParser parse,
) {
  if (values.isEmpty || values.length > 2) return null;
  final start = parse([values.first]);
  final end = values.length == 2 ? parse([values.last]) : start;
  if (start == null || end == null) return null;
  return [
    (cssProperties['$prefix-start$suffix']!, start),
    (cssProperties['$prefix-end$suffix']!, end),
  ];
}

/// `border`, `border-top` …: width, style and color in any order.
List<(CssPropertyDefinition, CssValue)>? _expandBorder(
  List<String> edges,
  List<CssComponentValue> values,
) {
  if (values.isEmpty || values.length > 3) return null;
  CssValue width = const CssLengthValue(CssLength.px(3));
  CssValue style = const CssKeyword('none');
  CssValue color = const CssColorValue(CssColor.currentColor);
  for (final v in values) {
    final ident = cssIdentOf([v]);
    if (ident != null && _borderStyles.contains(ident)) {
      style = CssKeyword(ident);
    } else if (_borderWidth([v]) case final w?) {
      width = w;
    } else if (_color([v]) case final c?) {
      color = c;
    } else {
      return null;
    }
  }
  return [
    for (final edge in edges) ...[
      (cssProperties['border-$edge-width']!, width),
      (cssProperties['border-$edge-style']!, style),
      (cssProperties['border-$edge-color']!, color),
    ],
  ];
}

/// `font`: `[style || variant || weight] size [/ line-height] family`,
/// or a system font keyword, which is ignored.
List<(CssPropertyDefinition, CssValue)>? _expandFont(
  List<CssComponentValue> values,
) {
  CssValue style = const CssKeyword('normal');
  CssValue variant = const CssKeyword('normal');
  CssValue weight = const CssKeyword('normal');
  var i = 0;
  // Leading style/variant/weight keywords, `normal` counting for any.
  while (i < values.length) {
    final ident = cssIdentOf([values[i]]);
    if (ident == 'normal') {
      i++;
    } else if (ident == 'italic' || ident == 'oblique') {
      style = CssKeyword(ident!);
      i++;
    } else if (ident == 'small-caps') {
      variant = const CssKeyword('small-caps');
      i++;
    } else if (_fontWeight([values[i]]) case final w?) {
      // A number here is a weight only if a size follows.
      if (i + 1 >= values.length) break;
      weight = w;
      i++;
    } else {
      break;
    }
  }
  if (i >= values.length) return null;
  final size = _fontSize([values[i]]);
  if (size == null) return null;
  i++;
  CssValue lineHeight = const CssKeyword('normal');
  if (i < values.length &&
      values[i] is CssTokenValue &&
      (values[i] as CssTokenValue).token.isDelim('/')) {
    i++;
    if (i >= values.length) return null;
    final lh = _lineHeight([values[i]]);
    if (lh == null) return null;
    lineHeight = lh;
    i++;
  }
  final family = _fontFamily(values.sublist(i));
  if (family == null) return null;
  return [
    (cssProperties['font-style']!, style),
    (cssProperties['font-variant']!, variant),
    (cssProperties['font-weight']!, weight),
    (cssProperties['font-size']!, size),
    (cssProperties['line-height']!, lineHeight),
    (cssProperties['font-family']!, family),
  ];
}

/// `background-image`: `none` or one `url()`; gradients are not drawn.
CssValue? _backgroundImage(List<CssComponentValue> values) {
  if (values.length != 1) return null;
  if (cssIdentOf(values) == 'none') return const CssKeyword('none');
  final url = _url(values.single);
  return url == null ? null : CssImageUrlValue(url);
}

/// The address of `url(…)` as a token or a function with a string.
String? _url(CssComponentValue value) => switch (value) {
  CssTokenValue(:final token) when token.type == CssTokenType.url =>
    token.value,
  CssFunctionValue(:final name, :final arguments)
      when name.toLowerCase() == 'url' =>
    switch (cssWithoutWhitespace(arguments)) {
      [CssTokenValue(:final token)] when token.type == CssTokenType.string =>
        token.value,
      _ => null,
    },
  _ => null,
};

/// `background-size`: `cover`, `contain`, or one or two lengths or
/// `auto` (the height `auto` when only the width is given).
CssValue? _backgroundSize(List<CssComponentValue> values) {
  if (values.isEmpty || values.length > 2) return null;
  final ident = cssIdentOf(values);
  if (ident == 'cover' || ident == 'contain') return CssKeyword(ident!);
  final sides = <CssLength?>[];
  for (final v in values) {
    if (cssIdentOf([v]) == 'auto') {
      sides.add(null);
      continue;
    }
    final length = CssLength.parse(v);
    if (length == null || length.value < 0) return null;
    sides.add(length);
  }
  final width = sides.first;
  final height = sides.length == 2 ? sides.last : null;
  return width == null && height == null
      ? const CssKeyword('auto')
      : CssBackgroundSizeValue(width, height);
}

/// `background-repeat`: one keyword for both directions, or one each.
CssValue? _backgroundRepeat(List<CssComponentValue> values) {
  final words = [
    for (final v in values) cssIdentOf([v]),
  ];
  if (words.isEmpty || words.length > 2 || words.contains(null)) return null;
  bool? repeats(String word) => switch (word) {
    'repeat' || 'space' || 'round' => true,
    'no-repeat' => false,
    _ => null,
  };
  if (words.length == 1) {
    return switch (words.single!) {
      'repeat-x' => const CssBackgroundRepeatValue(x: true, y: false),
      'repeat-y' => const CssBackgroundRepeatValue(x: false, y: true),
      final word => switch (repeats(word)) {
        final r? => CssBackgroundRepeatValue(x: r, y: r),
        null => null,
      },
    };
  }
  final x = repeats(words.first!);
  final y = repeats(words.last!);
  return x == null || y == null ? null : CssBackgroundRepeatValue(x: x, y: y);
}

/// `background-position` with one or two values: keywords or lengths,
/// the horizontal one first unless the keywords say otherwise; a missing
/// one is `center`.
CssValue? _backgroundPosition(List<CssComponentValue> values) {
  if (values.isEmpty || values.length > 2) return null;
  const center = CssLength.percent(50);
  CssLength? keyword(String? word) => switch (word) {
    'left' || 'top' => const CssLength.percent(0),
    'center' => center,
    'right' || 'bottom' => const CssLength.percent(100),
    _ => null,
  };
  final words = [
    for (final v in values) cssIdentOf([v]),
  ];
  final lengths = [
    for (final (i, v) in values.indexed)
      keyword(words[i]) ?? CssLength.parse(v),
  ];
  if (lengths.contains(null)) return null;
  final vertical = words.first == 'top' || words.first == 'bottom';
  if (values.length == 1) {
    return vertical
        ? CssBackgroundPositionValue(center, lengths.single!)
        : CssBackgroundPositionValue(lengths.single!, center);
  }
  final horizontal = words.last == 'left' || words.last == 'right';
  if (vertical || horizontal) {
    if (words.first == 'left' || words.first == 'right') return null;
    return CssBackgroundPositionValue(lengths.last!, lengths.first!);
  }
  return CssBackgroundPositionValue(lengths.first!, lengths.last!);
}

/// `background`: the last layer's colour, and the image, position, size
/// and repeat of the first layer with an image; attachment, origin and
/// clip are accepted and left out.
List<(CssPropertyDefinition, CssValue)>? _expandBackground(
  List<CssComponentValue> values,
) {
  CssValue color = const CssColorValue(CssColor.transparent);
  CssValue image = const CssKeyword('none');
  CssValue repeat = cssProperties['background-repeat']!.initial;
  CssValue position = cssProperties['background-position']!.initial;
  CssValue size = cssProperties['background-size']!.initial;
  var imageSet = false;
  for (final layer in cssSplitOnCommas(values)) {
    final parts = cssWithoutWhitespace(layer);
    final slash = parts.indexWhere(
      (v) =>
          v is CssTokenValue &&
          v.token.type == CssTokenType.delim &&
          v.token.value == '/',
    );
    // `position / size`: the size is the one or two values after the
    // slash; whatever follows them is the layer's other parts.
    var sizeEnd = slash + 1;
    if (slash >= 0) {
      final first = sizeEnd < parts.length
          ? cssIdentOf([parts[sizeEnd]])
          : null;
      final limit = first == 'cover' || first == 'contain' ? 1 : 2;
      while (sizeEnd < parts.length &&
          sizeEnd - slash - 1 < limit &&
          _backgroundSize([parts[sizeEnd]]) != null) {
        sizeEnd++;
      }
    }
    final before = slash < 0
        ? parts
        : [...parts.sublist(0, slash), ...parts.sublist(sizeEnd)];
    final after = slash < 0
        ? const <CssComponentValue>[]
        : parts.sublist(slash + 1, sizeEnd);
    CssValue? layerImage;
    CssValue? layerRepeat;
    final positions = <CssComponentValue>[];
    final repeats = <CssComponentValue>[];
    for (final v in before) {
      final word = cssIdentOf([v]);
      if (_backgroundImage([v]) case final i?) {
        layerImage = i;
      } else if (const {
        'repeat',
        'repeat-x',
        'repeat-y',
        'no-repeat',
        'space',
        'round',
      }.contains(word)) {
        repeats.add(v);
      } else if (const {
        'scroll',
        'fixed',
        'local',
        'border-box',
        'padding-box',
        'content-box',
      }.contains(word)) {
        continue;
      } else if (_color([v]) case final c?) {
        color = c;
      } else {
        positions.add(v);
      }
    }
    if (repeats.isNotEmpty) layerRepeat = _backgroundRepeat(repeats);
    final layerPosition = positions.isEmpty
        ? null
        : _backgroundPosition(positions);
    final layerSize = after.isEmpty ? null : _backgroundSize(after);
    if ((repeats.isNotEmpty && layerRepeat == null) ||
        (positions.isNotEmpty && layerPosition == null) ||
        (slash >= 0 && (layerSize == null || layerPosition == null))) {
      return null;
    }
    if (!imageSet && layerImage != null && layerImage is! CssKeyword) {
      imageSet = true;
      image = layerImage;
      repeat = layerRepeat ?? repeat;
      position = layerPosition ?? position;
      size = layerSize ?? size;
    }
  }
  return [
    (cssProperties['background-color']!, color),
    (cssProperties['background-image']!, image),
    (cssProperties['background-repeat']!, repeat),
    (cssProperties['background-position']!, position),
    (cssProperties['background-size']!, size),
  ];
}

const _overflowKeywords = {'visible', 'hidden', 'clip', 'scroll', 'auto'};

List<(CssPropertyDefinition, CssValue)>? _expandListStyle(
  List<CssComponentValue> values,
) {
  if (values.isEmpty || values.length > 3) return null;
  CssValue type = const CssKeyword('disc');
  CssValue position = const CssKeyword('outside');
  var sawType = false;
  for (final v in values) {
    final ident = cssIdentOf([v]);
    if (ident == 'inside' || ident == 'outside') {
      position = CssKeyword(ident!);
      continue;
    }
    if (v is CssTokenValue && v.token.type == CssTokenType.url) continue;
    if (ident == 'none' && !sawType) {
      type = const CssKeyword('none');
      continue;
    }
    final t = _listStyleType([v]);
    if (t == null) return null;
    type = t;
    sawType = true;
  }
  return [
    (cssProperties['list-style-type']!, type),
    (cssProperties['list-style-position']!, position),
  ];
}

/// `border-radius`: one to four horizontal radii, then optionally `/`
/// and one to four vertical ones, each list expanded as `margin` is, by
/// corner from the top left clockwise.
List<(CssPropertyDefinition, CssValue)>? _expandBorderRadius(
  List<CssComponentValue> values,
) {
  final slash = values.indexWhere(
    (v) => v is CssTokenValue && v.token.isDelim('/'),
  );
  final horizontal = slash < 0 ? values : values.sublist(0, slash);
  final vertical = slash < 0 ? horizontal : values.sublist(slash + 1);
  List<CssLength>? corners(List<CssComponentValue> list) {
    if (list.isEmpty || list.length > 4) return null;
    final lengths = <CssLength>[];
    for (final v in list) {
      final length = CssLength.parse(v);
      if (length == null || length.value < 0) return null;
      lengths.add(length);
    }
    return switch (lengths.length) {
      1 => [lengths[0], lengths[0], lengths[0], lengths[0]],
      2 => [lengths[0], lengths[1], lengths[0], lengths[1]],
      3 => [lengths[0], lengths[1], lengths[2], lengths[1]],
      _ => lengths,
    };
  }

  final h = corners(horizontal);
  final v = corners(vertical);
  if (h == null || v == null) return null;
  return [
    for (var i = 0; i < 4; i++)
      (
        cssProperties['border-${_corners[i]}-radius']!,
        CssLengthPairValue(h[i], v[i]),
      ),
  ];
}

final Map<String, _Shorthand> _shorthands = {
  'margin': _Shorthand(
    [for (final e in _edges) 'margin-$e'],
    (values) => _expandEdges(
      'margin-',
      '',
      values,
      (v) => _length(v, keywords: const {'auto'}),
    ),
  ),
  'padding': _Shorthand(
    [for (final e in _edges) 'padding-$e'],
    (values) => _expandEdges(
      'padding-',
      '',
      values,
      (v) => _length(v, allowNegative: false),
    ),
  ),
  'border-width': _Shorthand(
    [for (final e in _edges) 'border-$e-width'],
    (values) => _expandEdges('border-', '-width', values, _borderWidth),
  ),
  'border-style': _Shorthand(
    [for (final e in _edges) 'border-$e-style'],
    (values) =>
        _expandEdges('border-', '-style', values, _keywords(_borderStyles)),
  ),
  'border-color': _Shorthand(
    [for (final e in _edges) 'border-$e-color'],
    (values) => _expandEdges('border-', '-color', values, _color),
  ),
  'border': _Shorthand(
    [
      for (final e in _edges) ...[
        'border-$e-width',
        'border-$e-style',
        'border-$e-color',
      ],
    ],
    (values) => _expandBorder(_edges, values),
  ),
  for (final edge in _edges)
    'border-$edge': _Shorthand(
      ['border-$edge-width', 'border-$edge-style', 'border-$edge-color'],
      (values) => _expandBorder([edge], values),
    ),
  for (final side in CssFlowSide.values)
    'border-${side.css}': _Shorthand(
      [
        'border-${side.css}-width',
        'border-${side.css}-style',
        'border-${side.css}-color',
      ],
      (values) => _expandBorder([side.css], values),
    ),
  for (final axis in const ['inline', 'block']) ...{
    'margin-$axis': _Shorthand(
      ['margin-$axis-start', 'margin-$axis-end'],
      (values) => _expandStartEnd(
        'margin-$axis',
        '',
        values,
        (v) => _length(v, keywords: const {'auto'}),
      ),
    ),
    'padding-$axis': _Shorthand(
      ['padding-$axis-start', 'padding-$axis-end'],
      (values) => _expandStartEnd(
        'padding-$axis',
        '',
        values,
        (v) => _length(v, allowNegative: false),
      ),
    ),
    'border-$axis': _Shorthand(
      [
        for (final end in const ['start', 'end']) ...[
          'border-$axis-$end-width',
          'border-$axis-$end-style',
          'border-$axis-$end-color',
        ],
      ],
      (values) => _expandBorder(['$axis-start', '$axis-end'], values),
    ),
    'border-$axis-width': _Shorthand(
      ['border-$axis-start-width', 'border-$axis-end-width'],
      (values) =>
          _expandStartEnd('border-$axis', '-width', values, _borderWidth),
    ),
    'border-$axis-style': _Shorthand(
      ['border-$axis-start-style', 'border-$axis-end-style'],
      (values) => _expandStartEnd(
        'border-$axis',
        '-style',
        values,
        _keywords(_borderStyles),
      ),
    ),
    'border-$axis-color': _Shorthand(
      ['border-$axis-start-color', 'border-$axis-end-color'],
      (values) => _expandStartEnd('border-$axis', '-color', values, _color),
    ),
  },
  'font': _Shorthand(
    const [
      'font-style',
      'font-variant',
      'font-weight',
      'font-size',
      'line-height',
      'font-family',
    ],
    _expandFont,
  ),
  'background': _Shorthand(const [
    'background-color',
    'background-image',
    'background-repeat',
    'background-position',
    'background-size',
  ], _expandBackground),
  'text-decoration': _Shorthand(
    const ['text-decoration-line'],
    (values) {
      final v = _textDecoration(values);
      return v == null ? null : [(cssProperties['text-decoration-line']!, v)];
    },
  ),
  'list-style': _Shorthand(const [
    'list-style-type',
    'list-style-position',
  ], _expandListStyle),
  'border-radius': _Shorthand([
    for (final c in _corners) 'border-$c-radius',
  ], _expandBorderRadius),
  // One keyword for both axes, or x then y.
  'overflow': _Shorthand(const ['overflow-x', 'overflow-y'], (values) {
    if (values.isEmpty || values.length > 2) return null;
    final keywords = [
      for (final v in values) cssIdentOf([v]),
    ];
    if (keywords.any((k) => !_overflowKeywords.contains(k))) return null;
    return [
      (cssProperties['overflow-x']!, CssKeyword(keywords.first!)),
      (cssProperties['overflow-y']!, CssKeyword(keywords.last!)),
    ];
  }),
  'inset': _Shorthand(
    _edges,
    (values) => _expandEdges(
      '',
      '',
      values,
      (v) => _length(v, keywords: const {'auto'}),
    ),
  ),
  'break-before': _Shorthand(const ['page-break-before'], (values) {
    final v = _breakValue(values);
    return v == null ? null : [(cssProperties['page-break-before']!, v)];
  }),
  'break-after': _Shorthand(const ['page-break-after'], (values) {
    final v = _breakValue(values);
    return v == null ? null : [(cssProperties['page-break-after']!, v)];
  }),
  'break-inside': _Shorthand(const ['page-break-inside'], (values) {
    final ident = cssIdentOf(values);
    final v = switch (ident) {
      'auto' => const CssKeyword('auto'),
      'avoid' || 'avoid-page' || 'avoid-column' => const CssKeyword('avoid'),
      _ => null,
    };
    return v == null ? null : [(cssProperties['page-break-inside']!, v)];
  }),
};
