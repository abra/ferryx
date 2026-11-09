import 'dart:math' as math;
import 'dart:ui' as ui show LineMetrics;

import 'package:flutter/painting.dart';

import 'box_tree.dart' show MathNode;

/// A formula laid out (MathML Core's elements, with the spacing and
/// shifts of TeX's rules that browsers follow): its width, how far it
/// reaches above and below its baseline, and painting. Text is drawn
/// with [TextPainter]s in the paragraph's font (math symbols fall back
/// to a math font the platform has); fraction bars, radicals and
/// enclosures are drawn as rules and paths in its colour.
///
/// Owns native resources: [dispose] when done.
class MathLayout {
  MathLayout._(this._box);

  /// Lays [math] out in [style]'s font, size and colour; [display]
  /// formulas (`display="block"`) are set as TeX's display style: large
  /// operators larger, their limits above and below, fractions full
  /// size.
  factory MathLayout.layout(
    MathNode math,
    TextStyle style, {
    required bool display,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final size = style.fontSize ?? 16;
    final context = _MathContext(
      style.copyWith(
        fontFamilyFallback: [
          ...?style.fontFamilyFallback,
          ..._mathFonts,
        ],
      ),
      textScaler,
      size: size,
      rootSize: size,
      display: display || math['display'] == 'block',
      level: 0,
    );
    return MathLayout._(_layOut(math, context));
  }

  final _MathBox _box;

  double get width => _box.width;

  /// How far the formula reaches above its baseline.
  double get ascent => _box.ascent;

  /// How far it reaches below its baseline.
  double get descent => _box.descent;

  double get height => ascent + descent;

  /// Paints it with its top left at [topLeft].
  void paint(Canvas canvas, Offset topLeft) =>
      _box.paint(canvas, topLeft + Offset(0, ascent));

  void dispose() => _box.dispose();
}

/// Math fonts the platforms have, after the paragraph's own fonts: what
/// draws `∑`, `√` or `⟨` when a book font does not.
const _mathFonts = [
  'STIX Two Math',
  'Cambria Math',
  'Noto Sans Math',
  'Latin Modern Math',
];

/// What a node is laid out with: the font, its size here, the root size
/// (scripts never shrink below a part of it), display style and script
/// level.
class _MathContext {
  const _MathContext(
    this.style,
    this.textScaler, {
    required this.size,
    required this.rootSize,
    required this.display,
    required this.level,
  });

  final TextStyle style;
  final TextScaler textScaler;
  final double size;
  final double rootSize;
  final bool display;
  final int level;

  Color get color => style.color ?? const Color(0xFF000000);

  /// The default rule thickness: fraction bars, radicals' overbars.
  double get rule => math.max(1, size * 0.066);

  /// The math axis: where fraction bars and `−` sit, above the baseline.
  double get axis => size * 0.25;

  /// One level smaller (scripts, fractions in text style).
  _MathContext script([int levels = 1]) {
    var next = size;
    for (var i = 0; i < levels; i++) {
      next *= 0.71;
    }
    return _MathContext(
      style,
      textScaler,
      size: math.max(next, rootSize * 0.55),
      rootSize: rootSize,
      display: false,
      level: level + levels,
    );
  }

  _MathContext withDisplay(bool display) => _MathContext(
    style,
    textScaler,
    size: size,
    rootSize: rootSize,
    display: display,
    level: level,
  );

  _MathContext withSize(double size) => _MathContext(
    style,
    textScaler,
    size: size,
    rootSize: rootSize,
    display: display,
    level: level,
  );
}

/// A laid-out piece of a formula, drawn from a point on its baseline.
abstract class _MathBox {
  double get width;
  double get ascent;
  double get descent;

  /// Paints with the left end of the baseline at [baseline].
  void paint(Canvas canvas, Offset baseline);

  void dispose() {}
}

/// Text: one run of glyphs in one style.
class _Glyphs extends _MathBox {
  _Glyphs(this._painter) {
    final metrics = _painter.computeLineMetrics();
    final ui.LineMetrics? line = metrics.isEmpty ? null : metrics.first;
    _ascent = line?.ascent ?? _painter.height;
    _descent = line?.descent ?? 0;
  }

  final TextPainter _painter;
  late final double _ascent;
  late final double _descent;

  @override
  double get width => _painter.width;

  @override
  double get ascent => _ascent;

  @override
  double get descent => _descent;

  @override
  void paint(Canvas canvas, Offset baseline) =>
      _painter.paint(canvas, baseline - Offset(0, _ascent));

  @override
  void dispose() => _painter.dispose();
}

/// Room with nothing in it.
class _Space extends _MathBox {
  _Space(this.width, {this.ascent = 0, this.descent = 0});

  @override
  final double width;
  @override
  final double ascent;
  @override
  final double descent;

  @override
  void paint(Canvas canvas, Offset baseline) {}
}

/// Boxes placed by their baselines' left ends, relative to this box's,
/// and rules (rectangles) and strokes (paths) in the formula's colour.
class _Composite extends _MathBox {
  _Composite(
    this.parts, {
    double? width,
    this.rules = const [],
    this.strokes = const [],
    this.strokeWidth = 1,
    required this.color,
    this.visible = true,
  }) : width = width ?? _widthOf(parts) {
    var up = 0.0;
    var down = 0.0;
    for (final (box, at) in parts) {
      up = math.max(up, box.ascent - at.dy);
      down = math.max(down, box.descent + at.dy);
    }
    for (final rule in rules) {
      up = math.max(up, -rule.top);
      down = math.max(down, rule.bottom);
    }
    for (final stroke in strokes) {
      final bounds = stroke.getBounds();
      up = math.max(up, -bounds.top + strokeWidth / 2);
      down = math.max(down, bounds.bottom + strokeWidth / 2);
    }
    ascent = up;
    descent = down;
  }

  /// [boxes] side by side on one baseline.
  factory _Composite.row(List<_MathBox> boxes, {required Color color}) {
    final parts = <(_MathBox, Offset)>[];
    var x = 0.0;
    for (final box in boxes) {
      parts.add((box, Offset(x, 0)));
      x += box.width;
    }
    return _Composite(parts, width: x, color: color);
  }

  static double _widthOf(List<(_MathBox, Offset)> parts) {
    var right = 0.0;
    for (final (box, at) in parts) {
      right = math.max(right, at.dx + box.width);
    }
    return right;
  }

  final List<(_MathBox, Offset)> parts;
  final List<Rect> rules;
  final List<Path> strokes;
  final double strokeWidth;
  final Color color;

  /// False for `mphantom`: it takes its room and draws nothing.
  final bool visible;

  @override
  final double width;
  @override
  late final double ascent;
  @override
  late final double descent;

  @override
  void paint(Canvas canvas, Offset baseline) {
    if (!visible) return;
    for (final (box, at) in parts) {
      box.paint(canvas, baseline + at);
    }
    if (rules.isNotEmpty) {
      final paint = Paint()..color = color;
      for (final rule in rules) {
        canvas.drawRect(rule.shift(baseline), paint);
      }
    }
    if (strokes.isNotEmpty) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round;
      for (final stroke in strokes) {
        canvas.drawPath(stroke.shift(baseline), paint);
      }
    }
  }

  @override
  void dispose() {
    for (final (box, _) in parts) {
      box.dispose();
    }
  }
}

// Layout.

_MathBox _layOut(MathNode node, _MathContext c) {
  switch (node.name) {
    case 'mi':
      return _identifier(node, c);
    case 'mn' || 'mtext':
      return _text(node.text, c, node['mathvariant']);
    case 'ms':
      return _text('"${node.text}"', c, node['mathvariant']);
    case 'mo':
      return _operator(node, c, stretchTo: null);
    case 'mspace':
      return _Space(
        _length(node['width'], c) ?? 0,
        ascent: _length(node['height'], c) ?? 0,
        descent: _length(node['depth'], c) ?? 0,
      );
    case 'mfrac':
      return _fraction(node, c);
    case 'msub' || 'msup' || 'msubsup':
      return _scripts(node, c);
    case 'munder' || 'mover' || 'munderover':
      return _underOver(node, c);
    case 'msqrt':
      return _radical(_row(node.children, c), null, c);
    case 'mroot':
      return _radical(
        _layOut(_first(node, 0), c),
        _layOut(_first(node, 1), c.script(2)),
        c,
      );
    case 'mtable':
      return _table(node, c);
    case 'mfenced':
      return _fenced(node, c);
    case 'menclose':
      return _enclose(node, c);
    case 'mphantom':
      final inner = _row(node.children, c);
      return _Composite([(inner, Offset.zero)], color: c.color, visible: false);
    case 'mstyle':
      return _row(node.children, _styled(node, c));
    case 'semantics' || 'maction':
      return node.children.isEmpty
          ? _Space(0)
          : _layOut(node.children.first, c);
    default:
      // mrow, math, mpadded, merror and anything unknown: a row.
      return _row(node.children, c);
  }
}

MathNode _first(MathNode node, int index) => index < node.children.length
    ? node.children[index]
    : const MathNode('mrow');

/// `mstyle`'s `displaystyle`, `scriptlevel` and `mathsize`.
_MathContext _styled(MathNode node, _MathContext c) {
  var out = c;
  switch (node['displaystyle']) {
    case 'true':
      out = out.withDisplay(true);
    case 'false':
      out = out.withDisplay(false);
  }
  final level = node['scriptlevel'];
  if (level != null) {
    final n = int.tryParse(level.replaceFirst('+', ''));
    if (n != null && n > 0) out = out.script(n);
    if (n != null && n < 0) out = out.withSize(out.size / math.pow(0.71, -n));
  }
  final size = node['mathsize'];
  if (size != null) {
    out = out.withSize(switch (size) {
      'small' => out.size * 0.8,
      'big' => out.size * 1.2,
      'normal' => out.size,
      _ => _length(size, out, percentOf: out.size) ?? out.size,
    });
  }
  return out;
}

/// A length attribute: `em`, `ex`, `px`, `pt`, percentages of
/// [percentOf], unitless numbers, and the named spaces.
double? _length(String? value, _MathContext c, {double? percentOf}) {
  if (value == null) return null;
  final named = switch (value.trim()) {
    'veryverythinmathspace' => 1 / 18,
    'verythinmathspace' => 2 / 18,
    'thinmathspace' => 3 / 18,
    'mediummathspace' => 4 / 18,
    'thickmathspace' => 5 / 18,
    'verythickmathspace' => 6 / 18,
    'veryverythickmathspace' => 7 / 18,
    _ => null,
  };
  if (named != null) return named * c.size;
  final m = RegExp(
    r'^\s*(-?[0-9]*\.?[0-9]+)\s*(em|ex|px|pt|%)?\s*$',
  ).firstMatch(value);
  if (m == null) return null;
  final n = double.parse(m.group(1)!);
  return switch (m.group(2)) {
    'em' => n * c.size,
    'ex' => n * c.size * 0.5,
    'pt' => n * 4 / 3,
    '%' => n * (percentOf ?? c.size) / 100,
    _ => n,
  };
}

_Glyphs _glyphs(
  String text,
  _MathContext c, {
  bool italic = false,
  bool bold = false,
  double? size,
}) => _Glyphs(
  TextPainter(
    text: TextSpan(
      text: text,
      style: c.style.copyWith(
        fontSize: size ?? c.size,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        fontWeight: bold ? FontWeight.bold : null,
        height: 1,
        decoration: TextDecoration.none,
      ),
    ),
    textDirection: TextDirection.ltr,
    textScaler: c.textScaler,
  )..layout(),
);

_MathBox _text(String text, _MathContext c, String? variant) => _glyphs(
  text,
  c,
  italic: variant?.contains('italic') ?? false,
  bold: variant?.contains('bold') ?? false,
);

/// `mi`: one letter is italic, a name (`sin`, `log`) upright, unless
/// `mathvariant` says otherwise.
_MathBox _identifier(MathNode node, _MathContext c) {
  final variant = node['mathvariant'];
  final single = node.text.runes.length == 1;
  return _glyphs(
    node.text,
    c,
    italic: variant == null ? single : variant.contains('italic'),
    bold: variant?.contains('bold') ?? false,
  );
}

/// What a character draws as in an operator: a hyphen is a minus.
String _operatorText(String text) => switch (text) {
  '-' => '−',
  "'" => '′',
  _ => text,
};

const _largeOperators = {
  '∑',
  '∏',
  '∐',
  '⋀',
  '⋁',
  '⋂',
  '⋃',
  '⨀',
  '⨁',
  '⨂',
  '∫',
  '∬',
  '∭',
  '∮',
};

const _limitOperators = {
  '∑',
  '∏',
  '∐',
  '⋀',
  '⋁',
  '⋂',
  '⋃',
  '⨀',
  '⨁',
  '⨂',
  'lim',
  'max',
  'min',
  'sup',
  'inf',
  'det',
  'gcd',
  'Pr',
  'lim sup',
  'lim inf',
};

const _fences = {
  '(',
  ')',
  '[',
  ']',
  '{',
  '}',
  '|',
  '‖',
  '⟨',
  '⟩',
  '⌈',
  '⌉',
  '⌊',
  '⌋',
};

/// `mo`: its glyph, larger for a large operator in display style, a
/// fence [stretchTo] a height (above and below the axis) when given.
_MathBox _operator(
  MathNode node,
  _MathContext c, {
  required ({double ascent, double descent})? stretchTo,
}) {
  final text = _operatorText(node.text);
  if (stretchTo != null && _fences.contains(text)) {
    // A fence as tall as what it encloses, centred on the axis.
    final half = math.max(
      stretchTo.ascent - c.axis,
      stretchTo.descent + c.axis,
    );
    final size = math.max(c.size, half * 2 / 1.15);
    final glyphs = _glyphs(text, c, size: size);
    final middle = (glyphs.ascent - glyphs.descent) / 2;
    return _Composite([
      (glyphs, Offset(0, middle - c.axis)),
    ], color: c.color);
  }
  if (c.display && _largeOperators.contains(text)) {
    final glyphs = _glyphs(text, c, size: c.size * 1.45);
    final middle = (glyphs.ascent - glyphs.descent) / 2;
    return _Composite([
      (glyphs, Offset(0, middle - c.axis)),
    ], color: c.color);
  }
  return _glyphs(text, c);
}

enum _OperatorKind { relation, binary, punctuation, large, other }

_OperatorKind _kindOf(String text) {
  const relations = {
    '=',
    '≠',
    '<',
    '>',
    '≤',
    '≥',
    '≈',
    '≡',
    '∼',
    '≅',
    '≃',
    '∝',
    '→',
    '←',
    '↔',
    '⇒',
    '⇐',
    '⇔',
    '↦',
    '∈',
    '∉',
    '∋',
    '⊂',
    '⊃',
    '⊆',
    '⊇',
    ':=',
    '≔',
    '≪',
    '≫',
    '⊢',
    '⊨',
    '∣',
  };
  const binaries = {
    '+',
    '−',
    '-',
    '±',
    '∓',
    '×',
    '÷',
    '·',
    '⋅',
    '∗',
    '∘',
    '∪',
    '∩',
    '∧',
    '∨',
    '⊕',
    '⊗',
    '⊖',
    '∖',
    '⋆',
  };
  if (relations.contains(text)) return _OperatorKind.relation;
  if (binaries.contains(text)) return _OperatorKind.binary;
  if (text == ',' || text == ';') return _OperatorKind.punctuation;
  if (_largeOperators.contains(text)) return _OperatorKind.large;
  return _OperatorKind.other;
}

/// The space before and after operator [node] at [index] of a row of
/// [count]: thick around relations, medium around binary operators
/// (none for a sign before its operand), thin after punctuation; none in
/// scripts but after punctuation. `lspace` and `rspace` override.
(double, double) _operatorSpacing(
  MathNode node,
  int index,
  int count,
  _MathContext c,
) {
  final kind = _kindOf(_operatorText(node.text));
  final em = c.size / 18;
  final script = c.level > 0;
  var (left, right) = switch (kind) {
    _OperatorKind.relation => script ? (0.0, 0.0) : (5 * em, 5 * em),
    _OperatorKind.binary when index == 0 => (0.0, 0.0),
    _OperatorKind.binary => script ? (0.0, 0.0) : (4 * em, 4 * em),
    _OperatorKind.punctuation => (0.0, 3 * em),
    _OperatorKind.large => (0.0, 3 * em),
    _OperatorKind.other => (0.0, 0.0),
  };
  if (index == count - 1 && kind != _OperatorKind.punctuation) right = 0;
  left = _length(node['lspace'], c) ?? left;
  right = _length(node['rspace'], c) ?? right;
  return (left, right);
}

/// Children side by side, operators spaced; fences stretched to what
/// is between them.
_MathBox _row(List<MathNode> nodes, _MathContext c) {
  if (nodes.isEmpty) return _Space(0);
  bool isFence(MathNode n) =>
      n.name == 'mo' &&
      _fences.contains(_operatorText(n.text)) &&
      n['stretchy'] != 'false';
  final laidOut = <_MathBox?>[
    for (final n in nodes) isFence(n) ? null : _layOut(n, c),
  ];
  var up = 0.0;
  var down = 0.0;
  for (final box in laidOut) {
    if (box == null) continue;
    up = math.max(up, box.ascent);
    down = math.max(down, box.descent);
  }
  final tall = up + down > c.size * 1.3;
  final boxes = <_MathBox>[];
  for (final (i, n) in nodes.indexed) {
    var box = laidOut[i];
    box ??= _operator(
      n,
      c,
      stretchTo: tall ? (ascent: up, descent: down) : null,
    );
    if (n.name == 'mo') {
      final (left, right) = _operatorSpacing(n, i, nodes.length, c);
      if (left > 0) boxes.add(_Space(left));
      boxes.add(box);
      if (right > 0) boxes.add(_Space(right));
    } else {
      boxes.add(box);
    }
  }
  return boxes.length == 1
      ? boxes.single
      : _Composite.row(boxes, color: c.color);
}

/// `mfrac`: numerator over denominator, centred, the bar on the axis;
/// TeX's minimum shifts and gaps for display and text style.
_MathBox _fraction(MathNode node, _MathContext c) {
  final inner = c.display ? c.withDisplay(false) : c.script();
  final numerator = _layOut(_first(node, 0), inner);
  final denominator = _layOut(_first(node, 1), inner);
  final thickness = switch (node['linethickness']) {
    null => c.rule,
    'thin' => c.rule / 2,
    'medium' => c.rule,
    'thick' => c.rule * 2,
    final value => _length(value, c, percentOf: c.rule) ?? c.rule,
  };
  final axis = c.axis;
  final gap = thickness == 0
      ? (c.display ? 7 : 3) * c.rule
      : (c.display ? 3 : 1) * math.max(thickness, c.rule);
  final pad = c.size * 0.12;
  final width = math.max(numerator.width, denominator.width) + 2 * pad;
  var numeratorY = -(axis + thickness / 2 + gap + numerator.descent);
  numeratorY = math.min(numeratorY, -(c.display ? 0.677 : 0.394) * c.size);
  var denominatorY = denominator.ascent + gap + thickness / 2 - axis;
  denominatorY = math.max(denominatorY, (c.display ? 0.686 : 0.345) * c.size);
  return _Composite(
    [
      (numerator, Offset((width - numerator.width) / 2, numeratorY)),
      (denominator, Offset((width - denominator.width) / 2, denominatorY)),
    ],
    width: width,
    rules: [
      if (thickness > 0)
        Rect.fromLTWH(pad / 2, -axis - thickness / 2, width - pad, thickness),
    ],
    color: c.color,
  );
}

/// Whether [node] is a large operator whose limits go above and below in
/// display style (`movablelimits`).
bool _hasLimits(MathNode node, _MathContext c) =>
    c.display &&
    node.name == 'mo' &&
    node['movablelimits'] != 'false' &&
    _limitOperators.contains(node.text.trim());

/// `msub`, `msup`, `msubsup`: scripts one level smaller beside the base,
/// raised and lowered by TeX's rules; limits of a large operator in
/// display style go above and below it instead.
_MathBox _scripts(MathNode node, _MathContext c) {
  final baseNode = _first(node, 0);
  final hasSub = node.name != 'msup';
  final hasSup = node.name != 'msub';
  if (_hasLimits(baseNode, c)) {
    return _underOver(
      MathNode(
        hasSub && hasSup
            ? 'munderover'
            : hasSub
            ? 'munder'
            : 'mover',
        children: node.children,
      ),
      c,
    );
  }
  final base = _layOut(baseNode, c);
  final small = c.script();
  final sub = hasSub ? _layOut(_first(node, 1), small) : null;
  final sup = hasSup
      ? _layOut(_first(node, node.name == 'msup' ? 1 : 2), small)
      : null;
  var supUp = sup == null
      ? 0.0
      : math.max(
          c.size * (c.display ? 0.413 : 0.363),
          base.ascent - c.size * 0.38,
        );
  var subDown = sub == null
      ? 0.0
      : math.max(c.size * 0.15, base.descent + small.size * 0.25);
  if (sup != null) supUp = math.max(supUp, sup.descent + c.size * 0.11);
  if (sub != null) subDown = math.max(subDown, sub.ascent - c.size * 0.32);
  if (sup != null && sub != null) {
    final gap = (supUp - sup.descent) - (sub.ascent - subDown);
    if (gap < c.size * 0.2) subDown += c.size * 0.2 - gap;
  }
  final kern = c.size * 0.04;
  final x = base.width + kern;
  return _Composite([
    (base, Offset.zero),
    if (sup != null) (sup, Offset(x, -supUp)),
    if (sub != null) (sub, Offset(x, subDown)),
  ], color: c.color);
}

/// Characters that, alone over a base, are a line across it.
const _overLines = {'¯', '‾', '_', '̅', '‐', '−'};

/// `munder`, `mover`, `munderover`: the parts centred above and below
/// the base; accents (and lines) close to it and full size.
_MathBox _underOver(MathNode node, _MathContext c) {
  final hasUnder = node.name != 'mover';
  final hasOver = node.name != 'munder';
  final baseNode = _first(node, 0);
  if (!c.display &&
      _limitOperators.contains(baseNode.text.trim()) &&
      baseNode['movablelimits'] != 'false') {
    // Limits move to the side in text style.
    return _scripts(
      MathNode(
        hasUnder && hasOver
            ? 'msubsup'
            : hasUnder
            ? 'msub'
            : 'msup',
        children: node.children,
      ),
      c.withDisplay(false),
    );
  }
  final base = _layOut(baseNode, c);
  final underNode = hasUnder ? _first(node, 1) : null;
  final overNode = hasOver ? _first(node, hasUnder ? 2 : 1) : null;
  bool accent(MathNode? n, String attribute) =>
      n != null &&
      (node[attribute] == 'true' ||
          (n.name == 'mo' &&
              n.text.runes.length == 1 &&
              node[attribute] != 'false'));
  final overAccent = accent(overNode, 'accent');
  final underAccent = accent(underNode, 'accentunder');
  final rules = <Rect>[];
  final parts = <(_MathBox, Offset)>[];
  final gap = c.size * 0.1;
  final accentGap = c.size * 0.04;
  _MathBox? over;
  _MathBox? under;
  var width = base.width;
  if (overNode != null) {
    if (_overLines.contains(overNode.text.trim()) &&
        overNode.children.isEmpty) {
      rules.add(
        Rect.fromLTWH(0, -base.ascent - accentGap - c.rule, base.width, c.rule),
      );
    } else {
      over = _layOut(overNode, overAccent ? c : c.script());
      width = math.max(width, over.width);
    }
  }
  if (underNode != null) {
    if (_overLines.contains(underNode.text.trim()) &&
        underNode.children.isEmpty) {
      rules.add(
        Rect.fromLTWH(0, base.descent + accentGap, base.width, c.rule),
      );
    } else {
      under = _layOut(underNode, underAccent ? c : c.script());
      width = math.max(width, under.width);
    }
  }
  final baseX = (width - base.width) / 2;
  parts.add((base, Offset(baseX, 0)));
  if (over != null) {
    parts.add((
      over,
      Offset(
        (width - over.width) / 2,
        -(base.ascent + (overAccent ? accentGap : gap) + over.descent),
      ),
    ));
  }
  if (under != null) {
    parts.add((
      under,
      Offset(
        (width - under.width) / 2,
        base.descent + (underAccent ? accentGap : gap) + under.ascent,
      ),
    ));
  }
  return _Composite(
    parts,
    width: width,
    rules: [for (final r in rules) r.shift(Offset(baseX, 0))],
    color: c.color,
  );
}

/// `msqrt` and `mroot`: the radical sign as a stroke as tall as the
/// content and a gap, its bar over the content; an index above its
/// hook.
_MathBox _radical(_MathBox content, _MathBox? index, _MathContext c) {
  final thickness = c.rule;
  final gap = c.size * (c.display ? 0.2 : 0.12);
  final top = content.ascent + gap + thickness / 2;
  final bottom = content.descent;
  final sign = c.size * 0.56;
  final indexWidth = index == null
      ? 0.0
      : math.max(0.0, index.width - sign * 0.45);
  final x0 = indexWidth;
  final hookY = -(top + bottom) * 0.35 + bottom * 0.5;
  final path = Path()
    ..moveTo(x0, hookY + c.size * 0.04)
    ..lineTo(x0 + sign * 0.2, hookY - c.size * 0.04)
    ..lineTo(x0 + sign * 0.5, bottom)
    ..lineTo(x0 + sign, -top)
    ..lineTo(x0 + sign + content.width + c.size * 0.1, -top);
  final parts = <(_MathBox, Offset)>[
    (content, Offset(x0 + sign + c.size * 0.05, 0)),
    if (index != null)
      (index, Offset(0, hookY - c.size * 0.12 - index.descent)),
  ];
  return _Composite(
    parts,
    width: x0 + sign + content.width + c.size * 0.15,
    strokes: [path],
    strokeWidth: thickness,
    color: c.color,
  );
}

/// `mtable`: rows of cells (a labelled row's label left out), columns as
/// wide as their widest cell, cells centred, the table centred on the
/// axis.
_MathBox _table(MathNode node, _MathContext c) {
  final rows = [
    for (final row in node.children)
      if (row.name == 'mtr' || row.name == 'mlabeledtr')
        [
          for (final (i, cell) in row.children.indexed)
            if (!(row.name == 'mlabeledtr' && i == 0))
              cell.name == 'mtd' ? _row(cell.children, c) : _layOut(cell, c),
        ],
  ];
  if (rows.isEmpty) return _Space(0);
  final columns = rows.map((r) => r.length).reduce(math.max);
  final widths = List<double>.filled(columns, 0);
  for (final row in rows) {
    for (final (i, cell) in row.indexed) {
      widths[i] = math.max(widths[i], cell.width);
    }
  }
  final columnGap = c.size * 0.8;
  final rowGap = c.size * 0.35;
  final parts = <(_MathBox, Offset)>[];
  var y = 0.0;
  for (final row in rows) {
    var up = 0.0;
    var down = 0.0;
    for (final cell in row) {
      up = math.max(up, cell.ascent);
      down = math.max(down, cell.descent);
    }
    final baseline = y + up;
    var x = 0.0;
    for (final (i, cell) in row.indexed) {
      parts.add((cell, Offset(x + (widths[i] - cell.width) / 2, baseline)));
      x += widths[i] + columnGap;
    }
    y = baseline + down + rowGap;
  }
  final height = y - rowGap;
  // Centred on the axis: shift everything up by half the height plus it.
  final shift = height / 2 + c.axis;
  return _Composite(
    [for (final (box, at) in parts) (box, at.translate(0, -shift))],
    width: widths.fold<double>(0, (a, b) => a + b) + columnGap * (columns - 1),
    color: c.color,
  );
}

/// `mfenced`: its children between `open` and `close`, separated by
/// `separators`, as the row of operators it stands for.
_MathBox _fenced(MathNode node, _MathContext c) {
  final open = node['open'] ?? '(';
  final close = node['close'] ?? ')';
  final separators = (node['separators'] ?? ',').replaceAll(RegExp(r'\s'), '');
  final children = <MathNode>[
    if (open.isNotEmpty) MathNode('mo', text: open),
  ];
  for (final (i, child) in node.children.indexed) {
    if (i > 0 && separators.isNotEmpty) {
      final s = separators[math.min(i - 1, separators.length - 1)];
      children.add(MathNode('mo', text: s));
    }
    children.add(child);
  }
  if (close.isNotEmpty) children.add(MathNode('mo', text: close));
  return _row(children, c);
}

/// `menclose`: its content with the lines its `notation` names around
/// it (a box by default).
_MathBox _enclose(MathNode node, _MathContext c) {
  final content = _row(node.children, c);
  final notations = (node['notation'] ?? 'longdiv').split(RegExp(r'\s+'));
  final pad = c.size * 0.15;
  final t = c.rule;
  final rect = Rect.fromLTRB(
    0,
    -content.ascent - pad,
    content.width + 2 * pad,
    content.descent + pad,
  );
  final rules = <Rect>[];
  final strokes = <Path>[];
  for (final notation in notations) {
    switch (notation) {
      case 'box' || 'roundedbox':
        rules
          ..add(Rect.fromLTWH(rect.left, rect.top, rect.width, t))
          ..add(Rect.fromLTWH(rect.left, rect.bottom - t, rect.width, t))
          ..add(Rect.fromLTWH(rect.left, rect.top, t, rect.height))
          ..add(Rect.fromLTWH(rect.right - t, rect.top, t, rect.height));
      case 'top' || 'actuarial' || 'longdiv':
        rules.add(Rect.fromLTWH(rect.left, rect.top, rect.width, t));
        if (notation == 'actuarial') {
          rules.add(Rect.fromLTWH(rect.right - t, rect.top, t, rect.height));
        }
        if (notation == 'longdiv') {
          strokes.add(
            Path()
              ..moveTo(rect.left, rect.top)
              ..quadraticBezierTo(
                rect.left + pad,
                rect.center.dy,
                rect.left,
                rect.bottom,
              ),
          );
        }
      case 'bottom':
        rules.add(Rect.fromLTWH(rect.left, rect.bottom - t, rect.width, t));
      case 'left':
        rules.add(Rect.fromLTWH(rect.left, rect.top, t, rect.height));
      case 'right':
        rules.add(Rect.fromLTWH(rect.right - t, rect.top, t, rect.height));
      case 'horizontalstrike':
        rules.add(Rect.fromLTWH(rect.left, -c.axis - t / 2, rect.width, t));
      case 'verticalstrike':
        rules.add(
          Rect.fromLTWH(rect.center.dx - t / 2, rect.top, t, rect.height),
        );
      case 'updiagonalstrike':
        strokes.add(
          Path()
            ..moveTo(rect.left, rect.bottom)
            ..lineTo(rect.right, rect.top),
        );
      case 'downdiagonalstrike':
        strokes.add(
          Path()
            ..moveTo(rect.left, rect.top)
            ..lineTo(rect.right, rect.bottom),
        );
      case 'circle':
        strokes.add(Path()..addOval(rect));
    }
  }
  return _Composite(
    [(content, Offset(pad, 0))],
    width: rect.width,
    rules: rules,
    strokes: strokes,
    strokeWidth: t,
    color: c.color,
  );
}
