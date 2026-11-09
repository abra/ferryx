/// Typed CSS values and their parsers from component values: lengths,
/// colors, keywords, numbers, font families. Property grammars in
/// `css_properties.dart` compose these.
library;

import 'css_syntax.dart';
import 'css_tokenizer.dart';

part 'css_calc.dart';

enum CssLengthUnit {
  px,
  em,
  rem,
  ex,
  ch,
  pt,
  pc,
  inch,
  cm,
  mm,
  q,
  vw,
  vh,
  vmin,
  vmax,
  percent,

  /// A math function: [CssLength.calc] holds it.
  calc,
}

/// A length or percentage. Absolute units convert to px at parse time;
/// `em`, `rem`, `ex`, `ch` and the viewport units resolve when the style
/// is computed; a percentage stays one, for the layout to resolve
/// against whatever the property says. A math function ([calc]) does
/// the same with each of its terms ([computedIn]).
class CssLength {
  const CssLength(this.value, this.unit) : calc = null;

  const CssLength.px(this.value) : unit = CssLengthUnit.px, calc = null;

  const CssLength.percent(this.value)
    : unit = CssLengthUnit.percent,
      calc = null;

  const CssLength.calc(CssCalc this.calc)
    : value = 0,
      unit = CssLengthUnit.calc;

  static const zero = CssLength.px(0);

  final double value;
  final CssLengthUnit unit;

  /// The math function of a [CssLengthUnit.calc] length.
  final CssCalc? calc;

  bool get isPercent => unit == CssLengthUnit.percent;

  /// Whether the length depends on what percentages are of: a
  /// percentage, or a math function with one.
  bool get hasPercent => isPercent || (calc?.hasPercent ?? false);

  /// The computed length: relative units in px by [context], a
  /// percentage kept, a math function with its terms computed (one with
  /// no percentage left is a px length).
  CssLength computedIn(CssLengthContext context) {
    if (isPercent || isPx) return this;
    final calc = this.calc;
    if (calc == null) return CssLength.px(toPx(context));
    final resolved = calc.resolve(context);
    return resolved.hasPercent
        ? CssLength.calc(resolved)
        : CssLength.px(resolved.evaluate(null, 0));
  }

  bool get isPx => unit == CssLengthUnit.px;

  bool get isZero => value == 0;

  /// Parses a dimension, a percentage, a unitless 0 or a math function
  /// (`calc()`, `min()`, `max()`, `clamp()`). Null otherwise.
  static CssLength? parse(CssComponentValue value, {bool allowPercent = true}) {
    if (value is CssFunctionValue) {
      final calc = CssCalc.parse(value);
      if (calc == null || (!allowPercent && calc.hasPercent)) return null;
      return CssLength.calc(calc);
    }
    if (value is! CssTokenValue) return null;
    final t = value.token;
    switch (t.type) {
      case CssTokenType.number:
        return t.number == 0 ? zero : null;
      case CssTokenType.percentage:
        return allowPercent ? CssLength.percent(t.number) : null;
      case CssTokenType.dimension:
        return switch (t.unit) {
          'px' => CssLength.px(t.number),
          'pt' => CssLength.px(t.number * 4 / 3),
          'pc' => CssLength.px(t.number * 16),
          'in' => CssLength.px(t.number * 96),
          'cm' => CssLength.px(t.number * 96 / 2.54),
          'mm' => CssLength.px(t.number * 96 / 25.4),
          'q' => CssLength.px(t.number * 96 / 25.4 / 4),
          'em' => CssLength(t.number, CssLengthUnit.em),
          'rem' => CssLength(t.number, CssLengthUnit.rem),
          'ex' => CssLength(t.number, CssLengthUnit.ex),
          'ch' => CssLength(t.number, CssLengthUnit.ch),
          'vw' => CssLength(t.number, CssLengthUnit.vw),
          'vh' => CssLength(t.number, CssLengthUnit.vh),
          'vmin' => CssLength(t.number, CssLengthUnit.vmin),
          'vmax' => CssLength(t.number, CssLengthUnit.vmax),
          _ => null,
        };
      default:
        return null;
    }
  }

  /// The length in px, given what relative units refer to.
  double toPx(CssLengthContext context, {double percentOf = 0}) =>
      switch (unit) {
        CssLengthUnit.px => value,
        CssLengthUnit.em => value * context.fontSize,
        CssLengthUnit.rem => value * context.rootFontSize,
        CssLengthUnit.ex => value * context.fontSize * 0.5,
        CssLengthUnit.ch => value * context.fontSize * 0.5,
        CssLengthUnit.vw => value * context.viewportWidth / 100,
        CssLengthUnit.vh => value * context.viewportHeight / 100,
        CssLengthUnit.vmin =>
          value *
              (context.viewportWidth < context.viewportHeight
                  ? context.viewportWidth
                  : context.viewportHeight) /
              100,
        CssLengthUnit.vmax =>
          value *
              (context.viewportWidth > context.viewportHeight
                  ? context.viewportWidth
                  : context.viewportHeight) /
              100,
        CssLengthUnit.percent => value * percentOf / 100,
        CssLengthUnit.calc => calc!.evaluate(context, percentOf),
        // Absolute units were converted at parse time.
        CssLengthUnit.pt ||
        CssLengthUnit.pc ||
        CssLengthUnit.inch ||
        CssLengthUnit.cm ||
        CssLengthUnit.mm ||
        CssLengthUnit.q => value,
      };

  @override
  bool operator ==(Object other) =>
      other is CssLength &&
      other.value == value &&
      other.unit == unit &&
      other.calc == calc;

  @override
  int get hashCode => Object.hash(value, unit, calc);

  @override
  String toString() => switch (unit) {
    CssLengthUnit.percent => '$value%',
    CssLengthUnit.inch => '${value}in',
    CssLengthUnit.calc => 'calc($calc)',
    _ => '$value${unit.name}',
  };
}

/// What relative lengths resolve against.
class CssLengthContext {
  const CssLengthContext({
    required this.fontSize,
    required this.rootFontSize,
    this.viewportWidth = 0,
    this.viewportHeight = 0,
  });

  /// The element's own computed font size, in px.
  final double fontSize;
  final double rootFontSize;
  final double viewportWidth;
  final double viewportHeight;
}

/// An sRGB color with alpha, or `currentcolor`.
class CssColor {
  const CssColor(this.argb) : isCurrentColor = false;

  const CssColor._current() : argb = 0, isCurrentColor = true;

  static const currentColor = CssColor._current();
  static const transparent = CssColor(0x00000000);
  static const black = CssColor(0xFF000000);

  /// `0xAARRGGBB`.
  final int argb;
  final bool isCurrentColor;

  int get alpha => (argb >> 24) & 0xFF;

  /// Parses a named color, a hex color, `rgb()`/`rgba()`, `hsl()`/`hsla()`,
  /// `transparent` or `currentcolor`. Null otherwise.
  static CssColor? parse(CssComponentValue value) {
    switch (value) {
      case CssTokenValue(:final token):
        switch (token.type) {
          case CssTokenType.ident:
            final name = token.value.toLowerCase();
            if (name == 'currentcolor') return currentColor;
            final named = cssNamedColors[name];
            return named == null ? null : CssColor(named);
          case CssTokenType.hash:
            return _parseHex(token.value);
          default:
            return null;
        }
      case CssFunctionValue(:final name, :final arguments):
        final args = _numbers(arguments);
        if (args == null) return null;
        switch (name.toLowerCase()) {
          case 'rgb' || 'rgba':
            if (args.length != 3 && args.length != 4) return null;
            final channels = [
              for (final a in args.take(3))
                a.isPercent ? a.value * 255 / 100 : a.value,
            ];
            return CssColor(
              _argb(
                channels[0],
                channels[1],
                channels[2],
                args.length == 4 ? _alpha(args[3]) : 1,
              ),
            );
          case 'hsl' || 'hsla':
            if (args.length != 3 && args.length != 4) return null;
            final (r, g, b) = _hslToRgb(
              args[0].value,
              args[1].value,
              args[2].value,
            );
            return CssColor(
              _argb(r, g, b, args.length == 4 ? _alpha(args[3]) : 1),
            );
          default:
            return null;
        }
      default:
        return null;
    }
  }

  static double _alpha(({double value, bool isPercent}) a) =>
      a.isPercent ? a.value / 100 : a.value;

  static int _argb(double r, double g, double b, double a) =>
      ((a * 255).round().clamp(0, 255) << 24) |
      (r.round().clamp(0, 255) << 16) |
      (g.round().clamp(0, 255) << 8) |
      b.round().clamp(0, 255);

  /// Numbers, percentages and the `/` and `,` separators of a color
  /// function; null when anything else appears.
  static List<({double value, bool isPercent})>? _numbers(
    List<CssComponentValue> arguments,
  ) {
    final out = <({double value, bool isPercent})>[];
    for (final v in arguments) {
      if (v is! CssTokenValue) return null;
      final t = v.token;
      switch (t.type) {
        case CssTokenType.whitespace || CssTokenType.comma:
          continue;
        case CssTokenType.delim when t.value == '/':
          continue;
        case CssTokenType.number:
          out.add((value: t.number, isPercent: false));
        case CssTokenType.percentage:
          out.add((value: t.number, isPercent: true));
        case CssTokenType.dimension when t.unit == 'deg':
          out.add((value: t.number, isPercent: false));
        default:
          return null;
      }
    }
    return out;
  }

  static CssColor? _parseHex(String hex) {
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;
    String expand(String s) => s.split('').map((c) => '$c$c').join();
    final full = switch (hex.length) {
      3 => '${expand(hex)}ff',
      4 => expand(hex),
      6 => '${hex}ff',
      8 => hex,
      _ => null,
    };
    if (full == null) return null;
    final rgba = int.parse(full, radix: 16);
    return CssColor(((rgba & 0xFF) << 24) | (rgba >> 8));
  }

  static (double, double, double) _hslToRgb(double h, double s, double l) {
    final hue = ((h % 360) + 360) % 360 / 360;
    final sat = (s / 100).clamp(0.0, 1.0);
    final light = (l / 100).clamp(0.0, 1.0);
    if (sat == 0) return (light * 255, light * 255, light * 255);
    final q = light < 0.5 ? light * (1 + sat) : light + sat - light * sat;
    final p = 2 * light - q;
    double channel(double t) {
      var x = t;
      if (x < 0) x += 1;
      if (x > 1) x -= 1;
      if (x < 1 / 6) return p + (q - p) * 6 * x;
      if (x < 1 / 2) return q;
      if (x < 2 / 3) return p + (q - p) * (2 / 3 - x) * 6;
      return p;
    }

    return (
      channel(hue + 1 / 3) * 255,
      channel(hue) * 255,
      channel(hue - 1 / 3) * 255,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CssColor &&
      other.argb == argb &&
      other.isCurrentColor == isCurrentColor;

  @override
  int get hashCode => Object.hash(argb, isCurrentColor);

  @override
  String toString() => isCurrentColor
      ? 'currentcolor'
      : '#${argb.toRadixString(16).padLeft(8, '0')}';
}

/// The lowercased identifier a single-ident value holds, or null.
String? cssIdentOf(List<CssComponentValue> values) {
  if (values.length != 1) return null;
  final v = values.single;
  if (v is! CssTokenValue || v.token.type != CssTokenType.ident) return null;
  return v.token.value.toLowerCase();
}

/// The component values with whitespace tokens removed.
List<CssComponentValue> cssWithoutWhitespace(List<CssComponentValue> values) =>
    [
      for (final v in values)
        if (!(v is CssTokenValue && v.token.isWhitespace)) v,
    ];

/// Splits on top-level commas.
List<List<CssComponentValue>> cssSplitOnCommas(List<CssComponentValue> values) {
  final out = <List<CssComponentValue>>[[]];
  for (final v in values) {
    if (v is CssTokenValue && v.token.type == CssTokenType.comma) {
      out.add([]);
    } else {
      out.last.add(v);
    }
  }
  return out;
}

/// Parses a `font-family` list: strings as written, runs of identifiers
/// joined with spaces, generic families lowercased. Null when empty or
/// malformed.
List<String>? cssParseFontFamilies(List<CssComponentValue> values) {
  final families = <String>[];
  for (final part in cssSplitOnCommas(values)) {
    final tokens = cssWithoutWhitespace(part);
    if (tokens.isEmpty) return null;
    if (tokens.length == 1 &&
        tokens.single is CssTokenValue &&
        (tokens.single as CssTokenValue).token.type == CssTokenType.string) {
      final name = (tokens.single as CssTokenValue).token.value;
      if (name.isEmpty) return null;
      families.add(name);
      continue;
    }
    final words = <String>[];
    for (final t in tokens) {
      if (t is! CssTokenValue || t.token.type != CssTokenType.ident) {
        return null;
      }
      words.add(t.token.value);
    }
    final name = words.join(' ');
    families.add(
      cssGenericFontFamilies.contains(name.toLowerCase())
          ? name.toLowerCase()
          : name,
    );
  }
  return families;
}

const cssGenericFontFamilies = {
  'serif',
  'sans-serif',
  'monospace',
  'cursive',
  'fantasy',
  'system-ui',
  'ui-serif',
  'ui-sans-serif',
  'ui-monospace',
  'math',
  'emoji',
};

/// CSS Color Level 4 named colors, as `0xAARRGGBB`.
const Map<String, int> cssNamedColors = {
  'transparent': 0x00000000,
  'aliceblue': 0xFFF0F8FF,
  'antiquewhite': 0xFFFAEBD7,
  'aqua': 0xFF00FFFF,
  'aquamarine': 0xFF7FFFD4,
  'azure': 0xFFF0FFFF,
  'beige': 0xFFF5F5DC,
  'bisque': 0xFFFFE4C4,
  'black': 0xFF000000,
  'blanchedalmond': 0xFFFFEBCD,
  'blue': 0xFF0000FF,
  'blueviolet': 0xFF8A2BE2,
  'brown': 0xFFA52A2A,
  'burlywood': 0xFFDEB887,
  'cadetblue': 0xFF5F9EA0,
  'chartreuse': 0xFF7FFF00,
  'chocolate': 0xFFD2691E,
  'coral': 0xFFFF7F50,
  'cornflowerblue': 0xFF6495ED,
  'cornsilk': 0xFFFFF8DC,
  'crimson': 0xFFDC143C,
  'cyan': 0xFF00FFFF,
  'darkblue': 0xFF00008B,
  'darkcyan': 0xFF008B8B,
  'darkgoldenrod': 0xFFB8860B,
  'darkgray': 0xFFA9A9A9,
  'darkgreen': 0xFF006400,
  'darkgrey': 0xFFA9A9A9,
  'darkkhaki': 0xFFBDB76B,
  'darkmagenta': 0xFF8B008B,
  'darkolivegreen': 0xFF556B2F,
  'darkorange': 0xFFFF8C00,
  'darkorchid': 0xFF9932CC,
  'darkred': 0xFF8B0000,
  'darksalmon': 0xFFE9967A,
  'darkseagreen': 0xFF8FBC8F,
  'darkslateblue': 0xFF483D8B,
  'darkslategray': 0xFF2F4F4F,
  'darkslategrey': 0xFF2F4F4F,
  'darkturquoise': 0xFF00CED1,
  'darkviolet': 0xFF9400D3,
  'deeppink': 0xFFFF1493,
  'deepskyblue': 0xFF00BFFF,
  'dimgray': 0xFF696969,
  'dimgrey': 0xFF696969,
  'dodgerblue': 0xFF1E90FF,
  'firebrick': 0xFFB22222,
  'floralwhite': 0xFFFFFAF0,
  'forestgreen': 0xFF228B22,
  'fuchsia': 0xFFFF00FF,
  'gainsboro': 0xFFDCDCDC,
  'ghostwhite': 0xFFF8F8FF,
  'gold': 0xFFFFD700,
  'goldenrod': 0xFFDAA520,
  'gray': 0xFF808080,
  'green': 0xFF008000,
  'greenyellow': 0xFFADFF2F,
  'grey': 0xFF808080,
  'honeydew': 0xFFF0FFF0,
  'hotpink': 0xFFFF69B4,
  'indianred': 0xFFCD5C5C,
  'indigo': 0xFF4B0082,
  'ivory': 0xFFFFFFF0,
  'khaki': 0xFFF0E68C,
  'lavender': 0xFFE6E6FA,
  'lavenderblush': 0xFFFFF0F5,
  'lawngreen': 0xFF7CFC00,
  'lemonchiffon': 0xFFFFFACD,
  'lightblue': 0xFFADD8E6,
  'lightcoral': 0xFFF08080,
  'lightcyan': 0xFFE0FFFF,
  'lightgoldenrodyellow': 0xFFFAFAD2,
  'lightgray': 0xFFD3D3D3,
  'lightgreen': 0xFF90EE90,
  'lightgrey': 0xFFD3D3D3,
  'lightpink': 0xFFFFB6C1,
  'lightsalmon': 0xFFFFA07A,
  'lightseagreen': 0xFF20B2AA,
  'lightskyblue': 0xFF87CEFA,
  'lightslategray': 0xFF778899,
  'lightslategrey': 0xFF778899,
  'lightsteelblue': 0xFFB0C4DE,
  'lightyellow': 0xFFFFFFE0,
  'lime': 0xFF00FF00,
  'limegreen': 0xFF32CD32,
  'linen': 0xFFFAF0E6,
  'magenta': 0xFFFF00FF,
  'maroon': 0xFF800000,
  'mediumaquamarine': 0xFF66CDAA,
  'mediumblue': 0xFF0000CD,
  'mediumorchid': 0xFFBA55D3,
  'mediumpurple': 0xFF9370DB,
  'mediumseagreen': 0xFF3CB371,
  'mediumslateblue': 0xFF7B68EE,
  'mediumspringgreen': 0xFF00FA9A,
  'mediumturquoise': 0xFF48D1CC,
  'mediumvioletred': 0xFFC71585,
  'midnightblue': 0xFF191970,
  'mintcream': 0xFFF5FFFA,
  'mistyrose': 0xFFFFE4E1,
  'moccasin': 0xFFFFE4B5,
  'navajowhite': 0xFFFFDEAD,
  'navy': 0xFF000080,
  'oldlace': 0xFFFDF5E6,
  'olive': 0xFF808000,
  'olivedrab': 0xFF6B8E23,
  'orange': 0xFFFFA500,
  'orangered': 0xFFFF4500,
  'orchid': 0xFFDA70D6,
  'palegoldenrod': 0xFFEEE8AA,
  'palegreen': 0xFF98FB98,
  'paleturquoise': 0xFFAFEEEE,
  'palevioletred': 0xFFDB7093,
  'papayawhip': 0xFFFFEFD5,
  'peachpuff': 0xFFFFDAB9,
  'peru': 0xFFCD853F,
  'pink': 0xFFFFC0CB,
  'plum': 0xFFDDA0DD,
  'powderblue': 0xFFB0E0E6,
  'purple': 0xFF800080,
  'rebeccapurple': 0xFF663399,
  'red': 0xFFFF0000,
  'rosybrown': 0xFFBC8F8F,
  'royalblue': 0xFF4169E1,
  'saddlebrown': 0xFF8B4513,
  'salmon': 0xFFFA8072,
  'sandybrown': 0xFFF4A460,
  'seagreen': 0xFF2E8B57,
  'seashell': 0xFFFFF5EE,
  'sienna': 0xFFA0522D,
  'silver': 0xFFC0C0C0,
  'skyblue': 0xFF87CEEB,
  'slateblue': 0xFF6A5ACD,
  'slategray': 0xFF708090,
  'slategrey': 0xFF708090,
  'snow': 0xFFFFFAFA,
  'springgreen': 0xFF00FF7F,
  'steelblue': 0xFF4682B4,
  'tan': 0xFFD2B48C,
  'teal': 0xFF008080,
  'thistle': 0xFFD8BFD8,
  'tomato': 0xFFFF6347,
  'turquoise': 0xFF40E0D0,
  'violet': 0xFFEE82EE,
  'wheat': 0xFFF5DEB3,
  'white': 0xFFFFFFFF,
  'whitesmoke': 0xFFF5F5F5,
  'yellow': 0xFFFFFF00,
  'yellowgreen': 0xFF9ACD32,
};
