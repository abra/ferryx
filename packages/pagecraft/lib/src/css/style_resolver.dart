/// The cascade: stylesheets in their origins, matched against a
/// [ContentDocument], become one [ComputedStyle] per element.
///
/// Rules are indexed by the rightmost compound of each selector (id,
/// class, type or universal) so an element only tests the rules that
/// could match it. Elements resolve in document order, parents first,
/// so inheritance reads a finished parent. Computed styles are interned:
/// a thousand identical paragraphs share one object.
///
/// Precedence follows CSS Cascading Level 4 for the three origins:
/// user-agent, then user, then author, normal declarations in that
/// order; important declarations reverse it. Inline `style` attributes
/// are author declarations that beat every author selector.
/// Presentational attributes (`align`, `width`, `bgcolor`, Kindle's
/// `height` and `width` on paragraphs) are author declarations that
/// every author rule beats.
library;

import 'dart:collection';

import '../document/content_document.dart';
import 'computed_style.dart';
import 'css_custom_properties.dart';
import 'css_media.dart';
import 'css_properties.dart';
import 'css_selector.dart';
import 'css_syntax.dart';
import 'css_values.dart';
import 'stylesheet_loader.dart' show cssImageSource;

enum CssOrigin { userAgent, user, author }

/// A stylesheet with the origin it came from and, for URLs in it, its
/// address.
class CssSheetSource {
  const CssSheetSource(this.sheet, this.origin, {this.baseHref});

  final CssStyleSheet sheet;
  final CssOrigin origin;

  /// What the sheet's `url()`s are relative to; null leaves them as
  /// written.
  final String? baseHref;
}

/// The computed styles of one document, by element index. Text nodes
/// take their parent's style.
class ComputedStyles {
  ComputedStyles._(
    this.document,
    this._styles,
    this.rootFontSize,
    this._before,
    this._after,
  );

  final ContentDocument document;
  final List<ComputedStyle?> _styles;
  final double rootFontSize;
  final Map<int, ComputedStyle> _before;
  final Map<int, ComputedStyle> _after;

  ComputedStyle operator [](int node) {
    var n = node;
    while (!document.isElement(n)) {
      n = document.parentOf(n);
    }
    return _styles[n]!;
  }

  /// The style of [element]'s `::before`, when it has content.
  ComputedStyle? before(int element) => _before[element];

  /// The style of [element]'s `::after`, when it has content.
  ComputedStyle? after(int element) => _after[element];

  /// How many distinct style objects the document needed.
  int get distinctStyleCount =>
      _styles.whereType<ComputedStyle>().toSet().length;
}

/// What the resolver needs to know about the viewport and the reader's
/// base font size.
class StyleResolverOptions {
  const StyleResolverOptions({
    this.rootFontSize = 16,
    this.viewportWidth = 0,
    this.viewportHeight = 0,
    this.inlineStyleTransform,
  });

  /// The size `medium` and `1rem` mean, in px.
  final double rootFontSize;
  final double viewportWidth;
  final double viewportHeight;

  /// Rewrites `style` attributes before they are parsed.
  final String Function(String css)? inlineStyleTransform;
}

class StyleResolver {
  /// Builds the rule index for [sheets], in the order given within each
  /// origin. `@media` blocks are included when their query matches
  /// [media], `@supports` blocks when pagecraft supports their condition;
  /// other at-rules are ignored here (`@import` is the loader's job).
  StyleResolver(
    List<CssSheetSource> sheets, {
    CssMediaEnvironment media = const CssMediaEnvironment(),
  }) : _media = media {
    var order = 0;
    for (final source in sheets) {
      order = _index(
        source.sheet.rules,
        source.origin,
        order,
        source.baseHref,
      );
    }
  }

  final CssMediaEnvironment _media;

  /// Rules for elements, and for their `::before` and `::after`.
  final _rules = _RuleIndex();
  final _beforeRules = _RuleIndex();
  final _afterRules = _RuleIndex();

  int _index(
    List<CssRule> rules,
    CssOrigin origin,
    int order,
    String? baseHref,
  ) {
    var next = order;
    for (final rule in rules) {
      switch (rule) {
        case CssQualifiedRule():
          final selectors = CssSelectorList.parse(rule.prelude);
          if (selectors == null) continue;
          final declarations = [
            for (final d in rule.declarations)
              for (final parsed in parseCssDeclaration(d))
                _withBase(parsed, baseHref),
          ];
          if (declarations.isEmpty) continue;
          for (final selector in selectors.selectors) {
            if (selector.neverMatches) continue;
            final index = switch (selector.pseudoElement) {
              null => _rules,
              'before' => _beforeRules,
              'after' => _afterRules,
              // `::first-letter`, `::marker` …: not drawn.
              _ => null,
            };
            index?.add(_IndexedRule(selector, declarations, origin, next++));
          }
        case CssAtRule(name: 'media', :final rules?):
          if (cssMediaQueryListMatches(rule.prelude, _media)) {
            next = _index(rules, origin, next, baseHref);
          }
        case CssAtRule(name: 'supports', :final rules?):
          if (cssSupportsConditionHolds(rule.prelude)) {
            next = _index(rules, origin, next, baseHref);
          }
        case CssAtRule():
          break;
      }
    }
    return next;
  }

  /// [declaration] with its `content` and background image URLs
  /// relative to [baseHref].
  static CssParsedDeclaration _withBase(
    CssParsedDeclaration declaration,
    String? baseHref,
  ) {
    final value = declaration.value;
    if (baseHref != null && value is CssImageUrlValue) {
      return CssParsedDeclaration(
        declaration.property,
        CssImageUrlValue(value.url, base: baseHref),
        isImportant: declaration.isImportant,
      );
    }
    if (baseHref == null ||
        value is! CssContentValue ||
        !value.items.any((i) => i is CssContentUrl)) {
      return declaration;
    }
    return CssParsedDeclaration(
      declaration.property,
      CssContentValue([
        for (final item in value.items)
          item is CssContentUrl
              ? CssContentUrl(item.url, base: baseHref)
              : item,
      ]),
      isImportant: declaration.isImportant,
    );
  }

  /// Resolves every element of [document].
  ComputedStyles resolve(
    ContentDocument document, {
    StyleResolverOptions options = const StyleResolverOptions(),
  }) {
    final styles = List<ComputedStyle?>.filled(document.nodeCount, null);
    final before = <int, ComputedStyle>{};
    final after = <int, ComputedStyle>{};
    final run = _ResolveRun(document, options);
    for (var n = 0; n < document.nodeCount; n++) {
      if (!document.isElement(n)) continue;
      final parent = document.parentOf(n);
      final parentStyle = parent == ContentDocument.none
          ? null
          : styles[parent];
      final style = styles[n] = _compute(run, n, parentStyle);
      if (style.display == CssDisplay.none) continue;
      if (_pseudo(run, n, _beforeRules, style) case final b?) before[n] = b;
      if (_pseudo(run, n, _afterRules, style) case final a?) after[n] = a;
    }
    return ComputedStyles._(
      document,
      styles,
      options.rootFontSize,
      before,
      after,
    );
  }

  /// The style of [element]'s pseudo-element from [rules], inheriting
  /// from the element's [style]; null when no rule gives it content.
  ComputedStyle? _pseudo(
    _ResolveRun run,
    int element,
    _RuleIndex rules,
    ComputedStyle style,
  ) {
    if (rules.isEmpty) return null;
    final matched = <_IndexedRule>[];
    rules.collect(
      run.document,
      element,
      (rule) => rule.selector.matchesOriginating(run.document, element),
      matched,
    );
    if (matched.isEmpty) return null;
    final orders = [for (final rule in matched) rule.order]..sort();
    final key = _ShareKey(style, orders, null, null);
    final shared = run.sharedPseudo[key];
    if (shared != null) return shared.content == null ? null : shared;
    final candidates = [
      for (final rule in matched)
        for (final d in rule.declarations)
          _Candidate(
            d,
            _level(rule.origin, d.isImportant),
            rule.selector.specificity,
            rule.order,
          ),
    ]..sort();
    // Flow-relative properties land on the physical ones, as for elements.
    final rtl = _isRtl(candidates, style);
    final specified = <String, CssValue>{};
    for (final c in candidates) {
      final property = c.declaration.property;
      specified[property.physicalName?.call(rtl: rtl) ?? property.name] =
          c.declaration.value;
    }
    final computed = _ComputedStyleBuilder(
      specified,
      style,
      run.options,
      _customProperties(specified, style),
    ).build();
    final interned = run.intern.putIfAbsent(computed, () => computed);
    run.sharedPseudo[key] = interned;
    return interned.content == null ? null : interned;
  }

  /// The custom properties an element with [specified] values and a
  /// [parent] style has: its own over the parent's.
  static CssCustomProperties _customProperties(
    Map<String, CssValue> specified,
    ComputedStyle? parent,
  ) {
    final inherited = parent?.customProperties ?? CssCustomProperties.empty;
    Map<String, List<CssComponentValue>>? own;
    for (final MapEntry(:key, :value) in specified.entries) {
      if (value is CssCustomPropertyValue) {
        (own ??= {})[key] = value.values;
      }
    }
    return own == null ? inherited : CssCustomProperties.of(inherited, own);
  }

  /// The style of [element]: shared with an earlier element when both
  /// have the same parent style, matched rules, presentational attributes
  /// and inline style, which is most of a book's elements; computed and
  /// interned otherwise.
  ComputedStyle _compute(_ResolveRun run, int element, ComputedStyle? parent) {
    final doc = run.document;
    final matched = run.matched..clear();
    _rules.collect(
      doc,
      element,
      (rule) => rule.selector.matches(doc, element),
      matched,
    );

    final inline = doc.attributeOf(element, 'style');
    final hints = _hintSignature(doc, element);
    final orders = List<int>.generate(matched.length, (i) => matched[i].order)
      ..sort();
    final key = _ShareKey(parent, orders, hints, inline);
    final shared = run.shared[key];
    if (shared != null) return shared;

    final candidates = <_Candidate>[
      for (final rule in matched)
        for (final d in rule.declarations)
          _Candidate(
            d,
            _level(rule.origin, d.isImportant),
            rule.selector.specificity,
            rule.order,
          ),
      // Presentational hints: author origin, below every author rule.
      if (hints != null)
        for (final d in _presentationalHints(doc, element))
          _Candidate(d, _level(CssOrigin.author, false), -1, -1),
    ];
    // The style attribute: author origin, above every author rule.
    if (inline != null) {
      var order = 0;
      final css = run.options.inlineStyleTransform?.call(inline) ?? inline;
      for (final declaration in parseCssDeclarations(css)) {
        for (final d in parseCssDeclaration(declaration)) {
          candidates.add(
            _Candidate(
              d,
              _level(CssOrigin.author, d.isImportant),
              _inlineSpecificity,
              _inlineOrder + order++,
            ),
          );
        }
      }
    }
    candidates.sort();

    // Flow-relative properties land on the physical ones for this
    // element's direction, in cascade order: the later declaration wins.
    final rtl = _isRtl(candidates, parent);
    final specified = <String, CssValue>{};
    for (final c in candidates) {
      final property = c.declaration.property;
      final name = property.physicalName?.call(rtl: rtl) ?? property.name;
      specified[name] = c.declaration.value;
    }
    final computed = _ComputedStyleBuilder(
      specified,
      parent,
      run.options,
      _customProperties(specified, parent),
    ).build();
    final interned = run.intern.putIfAbsent(computed, () => computed);
    run.shared[key] = interned;
    return interned;
  }

  /// The element's computed direction from its sorted [candidates]: the
  /// last `direction` declared, else the parent's (it inherits).
  static bool _isRtl(List<_Candidate> candidates, ComputedStyle? parent) {
    for (final c in candidates.reversed) {
      if (c.declaration.property.name != 'direction') continue;
      return switch (c.declaration.value) {
        CssKeyword(name: 'rtl') => true,
        CssKeyword(name: 'ltr' || 'initial') => false,
        _ => parent?.direction == CssDirection.rtl,
      };
    }
    return parent?.direction == CssDirection.rtl;
  }

  /// Above every selector's specificity and source order.
  static const _inlineSpecificity = 1 << 40;
  static const _inlineOrder = 1 << 40;

  /// Calls [visit] with each class of a `class` attribute, split on
  /// ASCII whitespace without a regular expression.
  static void _forEachClass(String classes, void Function(String) visit) {
    var start = 0;
    final n = classes.length;
    while (start < n) {
      while (start < n && _isClassSpace(classes.codeUnitAt(start))) {
        start++;
      }
      var end = start;
      while (end < n && !_isClassSpace(classes.codeUnitAt(end))) {
        end++;
      }
      if (end > start) visit(classes.substring(start, end));
      start = end;
    }
  }

  static bool _isClassSpace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C;

  /// The element's presentational attributes as a string, or null when
  /// it has none: part of the style-sharing key.
  static String? _hintSignature(ContentDocument doc, int element) {
    StringBuffer? buffer;
    for (final (name, value) in doc.attributesOf(element)) {
      if (!_hintAttributes.contains(name.toLowerCase())) continue;
      (buffer ??= StringBuffer(doc.localNameOf(element).toLowerCase()))
        ..write('\u0000')
        ..write(name)
        ..write('=')
        ..write(value);
    }
    return buffer?.toString();
  }

  static const _hintAttributes = {
    'align',
    'width',
    'height',
    'bgcolor',
    'color',
    'face',
    'size',
    'text',
    'dir',
    'nowrap',
    'hidden',
    'hspace',
    'vspace',
    'border',
    'valign',
  };

  /// Cascade precedence: higher wins.
  static int _level(CssOrigin origin, bool important) =>
      switch ((origin, important)) {
        (CssOrigin.userAgent, false) => 0,
        (CssOrigin.user, false) => 1,
        (CssOrigin.author, false) => 2,
        (CssOrigin.author, true) => 3,
        (CssOrigin.user, true) => 4,
        (CssOrigin.userAgent, true) => 5,
      };

  /// HTML attributes that carry style, as declarations.
  static List<CssParsedDeclaration> _presentationalHints(
    ContentDocument doc,
    int element,
  ) {
    final tag = doc.localNameOf(element).toLowerCase();
    final out = <CssParsedDeclaration>[];
    void add(String property, String value) {
      out.addAll(
        parseCssDeclaration(
          CssDeclaration(property, parseCssComponentValues(value)),
        ),
      );
    }

    for (final (name, value) in doc.attributesOf(element)) {
      switch (name.toLowerCase()) {
        case 'align':
          final v = value.toLowerCase();
          if (v == 'left' || v == 'right' || v == 'center' || v == 'justify') {
            if (tag == 'img' || tag == 'table') {
              if (v == 'left' || v == 'right') add('float', v);
            } else {
              add('text-align', v);
            }
          }
        case 'width' when tag == 'p' || tag == 'div' || tag == 'blockquote':
          // Kindle: the paragraph's first-line indent.
          add('text-indent', _dimension(value));
        case 'height' when tag == 'p' || tag == 'div' || tag == 'blockquote':
          // Kindle: space above the paragraph.
          add('margin-top', _dimension(value));
        case 'width'
            when tag == 'img' ||
                tag == 'table' ||
                tag == 'td' ||
                tag == 'th' ||
                tag == 'hr':
          add('width', _dimension(value));
        case 'height'
            when tag == 'img' || tag == 'table' || tag == 'td' || tag == 'th':
          add('height', _dimension(value));
        case 'bgcolor':
          add('background-color', _colorAttribute(value));
        case 'color' when tag == 'font':
          add('color', _colorAttribute(value));
        case 'face' when tag == 'font':
          add('font-family', value);
        case 'size' when tag == 'font':
          final size = _fontSizeAttribute(value);
          if (size != null) add('font-size', size);
        case 'text' when tag == 'body':
          add('color', _colorAttribute(value));
        case 'dir':
          final v = value.toLowerCase();
          if (v == 'ltr' || v == 'rtl') add('direction', v);
        case 'nowrap':
          add('white-space', 'nowrap');
        case 'hidden':
          add('display', 'none');
        case 'hspace' when tag == 'img':
          add('margin-left', _dimension(value));
          add('margin-right', _dimension(value));
        case 'vspace' when tag == 'img':
          add('margin-top', _dimension(value));
          add('margin-bottom', _dimension(value));
        case 'border' when tag == 'img':
          add('border', '${_dimension(value)} solid');
        case 'valign' when tag == 'td' || tag == 'th' || tag == 'tr':
          add('vertical-align', value.toLowerCase());
      }
    }
    return out;
  }

  /// `12` means px; `50%` and `2em` are as written.
  static String _dimension(String value) {
    final v = value.trim();
    return RegExp(r'^\d+(\.\d+)?$').hasMatch(v) ? '${v}px' : v;
  }

  static String _colorAttribute(String value) {
    final v = value.trim();
    return RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(v) ? '#$v' : v;
  }

  static String? _fontSizeAttribute(String value) {
    final v = value.trim();
    final relative = RegExp(r'^([+-])(\d)$').firstMatch(v);
    var n = int.tryParse(v);
    if (relative != null) {
      n =
          3 +
          (relative.group(1) == '+' ? 1 : -1) * int.parse(relative.group(2)!);
    }
    if (n == null) return null;
    return switch (n.clamp(1, 7)) {
      1 => 'x-small',
      2 => 'small',
      3 => 'medium',
      4 => 'large',
      5 => 'x-large',
      6 => 'xx-large',
      _ => 'xxx-large',
    };
  }
}

/// The state of one [StyleResolver.resolve] call.
class _ResolveRun {
  _ResolveRun(this.document, this.options);

  final ContentDocument document;
  final StyleResolverOptions options;

  /// Styles by value, so equal styles are one object.
  final intern = HashMap<ComputedStyle, ComputedStyle>();

  /// Styles by what they were computed from.
  final shared = HashMap<_ShareKey, ComputedStyle>();

  /// Pseudo-element styles by their element's style and their rules.
  final sharedPseudo = HashMap<_ShareKey, ComputedStyle>();

  /// Scratch list of the rules an element matches.
  final matched = <_IndexedRule>[];
}

/// What an element's computed style depends on: its parent's style (by
/// identity: styles are interned), the rules it matches, its
/// presentational attributes and its inline style.
class _ShareKey {
  _ShareKey(this.parent, this.rules, this.hints, this.inline)
    : hashCode = Object.hash(
        identityHashCode(parent),
        Object.hashAll(rules),
        hints,
        inline,
      );

  final ComputedStyle? parent;
  final List<int> rules;
  final String? hints;
  final String? inline;

  @override
  final int hashCode;

  @override
  bool operator ==(Object other) {
    if (other is! _ShareKey ||
        other.hashCode != hashCode ||
        !identical(other.parent, parent) ||
        other.hints != hints ||
        other.inline != inline ||
        other.rules.length != rules.length) {
      return false;
    }
    for (var i = 0; i < rules.length; i++) {
      if (other.rules[i] != rules[i]) return false;
    }
    return true;
  }
}

/// Rules bucketed by the rightmost compound of their selector (id, else
/// class, else type, else universal), so an element only tests the rules
/// that could match it.
class _RuleIndex {
  final _byId = <String, List<_IndexedRule>>{};
  final _byClass = <String, List<_IndexedRule>>{};
  final _byType = <String, List<_IndexedRule>>{};
  final _universal = <_IndexedRule>[];

  bool get isEmpty =>
      _byId.isEmpty &&
      _byClass.isEmpty &&
      _byType.isEmpty &&
      _universal.isEmpty;

  void add(_IndexedRule rule) {
    final last = rule.selector.compounds.last;
    final id = last.simples.whereType<CssIdSelector>().firstOrNull;
    final cls = last.simples.whereType<CssClassSelector>().firstOrNull;
    if (id != null) {
      _byId.putIfAbsent(id.id, () => []).add(rule);
    } else if (cls != null) {
      _byClass.putIfAbsent(cls.name, () => []).add(rule);
    } else if (last.type != null) {
      _byType.putIfAbsent(last.type!, () => []).add(rule);
    } else {
      _universal.add(rule);
    }
  }

  /// Adds to [out] the rules for [element] that [matches] accepts.
  void collect(
    ContentDocument doc,
    int element,
    bool Function(_IndexedRule) matches,
    List<_IndexedRule> out,
  ) {
    void from(List<_IndexedRule>? rules) {
      if (rules == null) return;
      for (final rule in rules) {
        if (matches(rule)) out.add(rule);
      }
    }

    final id = doc.idOf(element);
    if (id != null) from(_byId[id]);
    final classes = doc.attributeOf(element, 'class');
    if (classes != null) {
      StyleResolver._forEachClass(classes, (cls) => from(_byClass[cls]));
    }
    from(_byType[doc.localNameOf(element).toLowerCase()]);
    from(_universal);
  }
}

class _IndexedRule {
  const _IndexedRule(this.selector, this.declarations, this.origin, this.order);

  final CssSelector selector;
  final List<CssParsedDeclaration> declarations;
  final CssOrigin origin;
  final int order;
}

class _Candidate implements Comparable<_Candidate> {
  const _Candidate(this.declaration, this.level, this.specificity, this.order);

  final CssParsedDeclaration declaration;
  final int level;
  final int specificity;
  final int order;

  @override
  int compareTo(_Candidate other) {
    if (level != other.level) return level.compareTo(other.level);
    if (specificity != other.specificity) {
      return specificity.compareTo(other.specificity);
    }
    return order.compareTo(other.order);
  }
}

/// Turns the cascaded specified values of one element into its computed
/// style: inheritance, initial values, `em` and keyword resolution.
class _ComputedStyleBuilder {
  _ComputedStyleBuilder(
    this.specified,
    this.parent,
    this.options,
    this.customProperties,
  );

  final Map<String, CssValue> specified;
  final ComputedStyle? parent;
  final StyleResolverOptions options;
  final CssCustomProperties customProperties;

  /// The specified value after the CSS-wide keywords: null means "take
  /// the parent's computed value", whether the property inherits by
  /// default or `inherit`/`unset` asked for it.
  CssValue? _value(String name) {
    final property = cssProperties[name]!;
    var value = specified[name];
    if (value is CssPendingValue) {
      value = resolveCssPendingValue(value, name, customProperties);
    }
    if (value == null) {
      return property.inherited && parent != null ? null : property.initial;
    }
    if (value is CssKeyword && value.isCssWide) {
      final inherit =
          value.name == 'inherit' ||
          (value.name == 'unset' && property.inherited);
      return inherit && parent != null ? null : property.initial;
    }
    return value;
  }

  late final double fontSize = _fontSize();

  late final CssLengthContext lengths = CssLengthContext(
    fontSize: fontSize,
    rootFontSize: options.rootFontSize,
    viewportWidth: options.viewportWidth,
    viewportHeight: options.viewportHeight,
  );

  late final CssLengthContext parentLengths = CssLengthContext(
    fontSize: parent?.fontSize ?? options.rootFontSize,
    rootFontSize: options.rootFontSize,
    viewportWidth: options.viewportWidth,
    viewportHeight: options.viewportHeight,
  );

  double _fontSize() {
    final value = _value('font-size');
    final parentSize = parent?.fontSize ?? options.rootFontSize;
    switch (value) {
      case null:
        return parentSize;
      case CssLengthValue(:final length):
        return length.toPx(parentLengths, percentOf: parentSize);
      case CssKeyword(:final name):
        final medium = options.rootFontSize;
        return switch (name) {
          'xx-small' => medium * 9 / 16,
          'x-small' => medium * 10 / 16,
          'small' => medium * 13 / 16,
          'medium' => medium,
          'large' => medium * 18 / 16,
          'x-large' => medium * 24 / 16,
          'xx-large' => medium * 32 / 16,
          'xxx-large' => medium * 48 / 16,
          'larger' => parentSize * 1.2,
          'smaller' => parentSize / 1.2,
          _ => medium,
        };
      default:
        return parentSize;
    }
  }

  /// The background image, its size, repeat and position computed;
  /// null without one.
  CssBackgroundImage? _backgroundImage() {
    final source = switch (_value('background-image')) {
      null => parent?.backgroundImage?.source,
      CssImageUrlValue(:final url, :final base) => cssImageSource(url, base),
      _ => null,
    };
    if (source == null) return null;
    final inherited = parent?.backgroundImage;
    var fit = CssBackgroundFit.auto;
    CssLength? width;
    CssLength? height;
    switch (_value('background-size')) {
      case null:
        fit = inherited?.fit ?? fit;
        width = inherited?.width;
        height = inherited?.height;
      case CssKeyword(name: 'cover'):
        fit = CssBackgroundFit.cover;
      case CssKeyword(name: 'contain'):
        fit = CssBackgroundFit.contain;
      case CssBackgroundSizeValue(width: final w, height: final h):
        width = w?.computedIn(lengths);
        height = h?.computedIn(lengths);
      default:
        break;
    }
    final repeat = switch (_value('background-repeat')) {
      CssBackgroundRepeatValue(:final x, :final y) => (x: x, y: y),
      _ => (
        x: inherited?.repeatX ?? true,
        y: inherited?.repeatY ?? true,
      ),
    };
    final position = switch (_value('background-position')) {
      CssBackgroundPositionValue(:final x, :final y) => (
        x: x.computedIn(lengths),
        y: y.computedIn(lengths),
      ),
      _ => (
        x: inherited?.x ?? const CssLength.percent(0),
        y: inherited?.y ?? const CssLength.percent(0),
      ),
    };
    return CssBackgroundImage(
      source,
      fit: fit,
      width: width,
      height: height,
      repeatX: repeat.x,
      repeatY: repeat.y,
      x: position.x,
      y: position.y,
    );
  }

  T _keyword<T extends Enum>(
    String name,
    List<T> values,
    T Function(String) map, {
    required T Function(ComputedStyle) inherited,
  }) {
    final value = _value(name);
    if (value == null) return inherited(parent!);
    return value is CssKeyword ? map(value.name) : values.first;
  }

  /// A length in px (relative units resolved) or a kept percentage;
  /// null for the keyword [nullKeyword].
  CssLength? _length(
    String name, {
    String? nullKeyword,
    required CssLength? Function(ComputedStyle) inherited,
  }) {
    final value = _value(name);
    if (value == null) return inherited(parent!);
    return switch (value) {
      CssLengthValue(:final length) => length.computedIn(lengths),
      CssKeyword(:final name) when name == nullKeyword => null,
      _ => CssLength.zero,
    };
  }

  int _color(
    String name, {
    required int Function(ComputedStyle) inherited,
    required int current,
  }) {
    final value = _value(name);
    if (value == null) return inherited(parent!);
    if (value is! CssColorValue) return 0;
    return value.color.isCurrentColor ? current : value.color.argb;
  }

  ComputedStyle build() {
    final fontFamily = switch (_value('font-family')) {
      null => parent!.fontFamily,
      CssFontFamilyValue(:final families) => families,
      _ => const ['serif'],
    };
    final fontWeight = _fontWeight();
    final fontStyle = _keyword(
      'font-style',
      CssFontStyle.values,
      (k) => switch (k) {
        'italic' => CssFontStyle.italic,
        'oblique' => CssFontStyle.oblique,
        _ => CssFontStyle.normal,
      },
      inherited: (p) => p.fontStyle,
    );
    final smallCaps = switch (_value('font-variant')) {
      null => parent!.smallCaps,
      CssKeyword(name: 'small-caps') => true,
      _ => false,
    };
    final opticalSizing = switch (_value('font-optical-sizing')) {
      null => parent!.opticalSizing,
      CssKeyword(name: 'none') => false,
      _ => true,
    };
    final color = _color(
      'color',
      inherited: (p) => p.color,
      current: parent?.color ?? 0xFF000000,
    );
    final backgroundColor = _color(
      'background-color',
      inherited: (p) => p.backgroundColor,
      current: color,
    );
    final lineHeight = switch (_value('line-height')) {
      null => parent!.lineHeight,
      CssNumberValue(:final value) => CssLineHeight.factor(value),
      CssLengthValue(:final length) => CssLineHeight.px(
        length.toPx(lengths, percentOf: fontSize),
      ),
      _ => CssLineHeight.normal,
    };
    final margin = CssEdges(
      _length(
        'margin-top',
        nullKeyword: 'auto',
        inherited: (p) => p.margin.top,
      ),
      _length(
        'margin-right',
        nullKeyword: 'auto',
        inherited: (p) => p.margin.right,
      ),
      _length(
        'margin-bottom',
        nullKeyword: 'auto',
        inherited: (p) => p.margin.bottom,
      ),
      _length(
        'margin-left',
        nullKeyword: 'auto',
        inherited: (p) => p.margin.left,
      ),
    );
    final paddingEdges = CssEdges(
      _length('padding-top', inherited: (p) => p.padding.top),
      _length('padding-right', inherited: (p) => p.padding.right),
      _length('padding-bottom', inherited: (p) => p.padding.bottom),
      _length('padding-left', inherited: (p) => p.padding.left),
    );
    final padding = CssEdges(
      paddingEdges.top ?? CssLength.zero,
      paddingEdges.right ?? CssLength.zero,
      paddingEdges.bottom ?? CssLength.zero,
      paddingEdges.left ?? CssLength.zero,
    );
    CssBorderStyle borderStyle(String edge) =>
        switch (_value('border-$edge-style')) {
          null => _parentEdge(parent!.borderStyle, edge),
          CssKeyword(:final name) => switch (name) {
            'hidden' => CssBorderStyle.hidden,
            'dashed' => CssBorderStyle.dashed,
            'dotted' => CssBorderStyle.dotted,
            'double' => CssBorderStyle.double,
            'groove' => CssBorderStyle.groove,
            'ridge' => CssBorderStyle.ridge,
            'inset' => CssBorderStyle.inset,
            'outset' => CssBorderStyle.outset,
            'none' => CssBorderStyle.none,
            _ => CssBorderStyle.solid,
          },
          _ => CssBorderStyle.none,
        };
    final styles = CssEdges(
      borderStyle('top'),
      borderStyle('right'),
      borderStyle('bottom'),
      borderStyle('left'),
    );
    double borderWidth(String edge, CssBorderStyle style) {
      if (style == CssBorderStyle.none || style == CssBorderStyle.hidden) {
        return 0;
      }
      return switch (_value('border-$edge-width')) {
        null => _parentEdge(parent!.borderWidth, edge),
        CssLengthValue(:final length) => length.toPx(lengths),
        _ => 3,
      };
    }

    final widths = CssEdges(
      borderWidth('top', styles.top),
      borderWidth('right', styles.right),
      borderWidth('bottom', styles.bottom),
      borderWidth('left', styles.left),
    );
    int borderColor(String edge) => _color(
      'border-$edge-color',
      inherited: (p) => _parentEdge(p.borderColor, edge),
      current: color,
    );
    final colors = CssEdges(
      borderColor('top'),
      borderColor('right'),
      borderColor('bottom'),
      borderColor('left'),
    );
    final display = switch (_value('display')) {
      null => parent!.display,
      CssKeyword(:final name) => CssDisplay.fromKeyword(name),
      _ => CssDisplay.inline,
    };
    CssPageBreak pageBreak(String name) => switch (_value(name)) {
      null =>
        name == 'page-break-before'
            ? parent!.pageBreakBefore
            : parent!.pageBreakAfter,
      CssKeyword(:final name) => switch (name) {
        'always' => CssPageBreak.always,
        'avoid' => CssPageBreak.avoid,
        'left' => CssPageBreak.left,
        'right' => CssPageBreak.right,
        _ => CssPageBreak.auto,
      },
      _ => CssPageBreak.auto,
    };
    final avoidInside = switch (_value('page-break-inside')) {
      null => parent!.avoidPageBreakInside,
      CssKeyword(:final name) => name != 'auto',
      _ => false,
    };
    final verticalAlignValue = _value('vertical-align');
    final (verticalAlign, verticalAlignLength) = switch (verticalAlignValue) {
      null => (parent!.verticalAlign, parent!.verticalAlignLength),
      CssLengthValue(:final length) => (
        CssVerticalAlign.length,
        length.computedIn(lengths),
      ),
      CssKeyword(:final name) => (
        switch (name) {
          'sub' => CssVerticalAlign.sub,
          'super' => CssVerticalAlign.sup,
          'text-top' => CssVerticalAlign.textTop,
          'text-bottom' => CssVerticalAlign.textBottom,
          'middle' => CssVerticalAlign.middle,
          'top' => CssVerticalAlign.top,
          'bottom' => CssVerticalAlign.bottom,
          _ => CssVerticalAlign.baseline,
        },
        null,
      ),
      _ => (CssVerticalAlign.baseline, null),
    };
    final decoration = switch (_value('text-decoration-line')) {
      null => CssTextDecorationValue(
        underline: parent!.underline,
        overline: parent!.overline,
        lineThrough: parent!.lineThrough,
      ),
      CssTextDecorationValue v => v,
      _ => const CssTextDecorationValue(),
    };
    double spacing(String name, double Function(ComputedStyle) inherited) =>
        switch (_value(name)) {
          null => inherited(parent!),
          CssLengthValue(:final length) => length.toPx(
            lengths,
            percentOf: fontSize,
          ),
          _ => 0,
        };
    final listStyleType = switch (_value('list-style-type')) {
      null => parent!.listStyleType,
      CssKeyword(:final name) => name,
      CssStringValue(:final value) => value,
      _ => 'disc',
    };
    int integer(
      String name,
      int Function(ComputedStyle) inherited,
      int fallback,
    ) => switch (_value(name)) {
      null => inherited(parent!),
      CssNumberValue(:final value) => value.toInt(),
      _ => fallback,
    };
    final (spacingX, spacingY) = _borderSpacing();
    final widthKeyword = switch (_value('width')) {
      null => parent!.widthKeyword,
      CssKeyword(name: 'min-content') => CssSizeKeyword.minContent,
      CssKeyword(name: 'max-content') => CssSizeKeyword.maxContent,
      CssKeyword(name: 'fit-content') => CssSizeKeyword.fitContent,
      _ => null,
    };
    return ComputedStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontStyle: fontStyle,
      fontWeight: fontWeight,
      smallCaps: smallCaps,
      opticalSizing: opticalSizing,
      color: color,
      backgroundColor: backgroundColor,
      backgroundImage: _backgroundImage(),
      textAlign: _keyword(
        'text-align',
        CssTextAlign.values,
        (k) => switch (k) {
          'left' => CssTextAlign.left,
          'right' => CssTextAlign.right,
          'center' => CssTextAlign.center,
          'justify' => CssTextAlign.justify,
          'end' => CssTextAlign.end,
          _ => CssTextAlign.start,
        },
        inherited: (p) => p.textAlign,
      ),
      textIndent:
          _length('text-indent', inherited: (p) => p.textIndent) ??
          CssLength.zero,
      lineHeight: lineHeight,
      margin: margin,
      padding: padding,
      borderWidth: widths,
      borderStyle: styles,
      borderColor: colors,
      display: display,
      pageBreakBefore: pageBreak('page-break-before'),
      pageBreakAfter: pageBreak('page-break-after'),
      avoidPageBreakInside: avoidInside,
      width: widthKeyword == null
          ? _length('width', nullKeyword: 'auto', inherited: (p) => p.width)
          : null,
      widthKeyword: widthKeyword,
      height: _length(
        'height',
        nullKeyword: 'auto',
        inherited: (p) => p.height,
      ),
      maxWidth: _length(
        'max-width',
        nullKeyword: 'none',
        inherited: (p) => p.maxWidth,
      ),
      maxHeight: _length(
        'max-height',
        nullKeyword: 'none',
        inherited: (p) => p.maxHeight,
      ),
      minWidth:
          _length(
            'min-width',
            nullKeyword: 'auto',
            inherited: (p) => p.minWidth,
          ) ??
          CssLength.zero,
      minHeight:
          _length(
            'min-height',
            nullKeyword: 'auto',
            inherited: (p) => p.minHeight,
          ) ??
          CssLength.zero,
      float: _keyword(
        'float',
        CssFloat.values,
        (k) => switch (k) {
          'left' || 'inline-start' => CssFloat.left,
          'right' || 'inline-end' => CssFloat.right,
          _ => CssFloat.none,
        },
        inherited: (p) => p.float,
      ),
      clear: _keyword(
        'clear',
        CssClear.values,
        (k) => switch (k) {
          'left' || 'inline-start' => CssClear.left,
          'right' || 'inline-end' => CssClear.right,
          'both' => CssClear.both,
          _ => CssClear.none,
        },
        inherited: (p) => p.clear,
      ),
      underline: decoration.underline,
      overline: decoration.overline,
      lineThrough: decoration.lineThrough,
      letterSpacing: spacing('letter-spacing', (p) => p.letterSpacing),
      wordSpacing: spacing('word-spacing', (p) => p.wordSpacing),
      whiteSpace: _keyword(
        'white-space',
        CssWhiteSpace.values,
        (k) => switch (k) {
          'nowrap' => CssWhiteSpace.nowrap,
          'pre' => CssWhiteSpace.pre,
          'pre-wrap' || 'break-spaces' => CssWhiteSpace.preWrap,
          'pre-line' => CssWhiteSpace.preLine,
          _ => CssWhiteSpace.normal,
        },
        inherited: (p) => p.whiteSpace,
      ),
      verticalAlign: verticalAlign,
      verticalAlignLength: verticalAlignLength,
      textTransform: _keyword(
        'text-transform',
        CssTextTransform.values,
        (k) => switch (k) {
          'capitalize' => CssTextTransform.capitalize,
          'uppercase' => CssTextTransform.uppercase,
          'lowercase' => CssTextTransform.lowercase,
          _ => CssTextTransform.none,
        },
        inherited: (p) => p.textTransform,
      ),
      hyphens: _keyword(
        'hyphens',
        CssHyphens.values,
        (k) => switch (k) {
          'none' => CssHyphens.none,
          'auto' => CssHyphens.auto,
          _ => CssHyphens.manual,
        },
        inherited: (p) => p.hyphens,
      ),
      direction: _keyword(
        'direction',
        CssDirection.values,
        (k) => k == 'rtl' ? CssDirection.rtl : CssDirection.ltr,
        inherited: (p) => p.direction,
      ),
      unicodeBidi: _keyword(
        'unicode-bidi',
        CssUnicodeBidi.values,
        (k) => switch (k) {
          'embed' => CssUnicodeBidi.embed,
          'isolate' => CssUnicodeBidi.isolate,
          'bidi-override' => CssUnicodeBidi.bidiOverride,
          'isolate-override' => CssUnicodeBidi.isolateOverride,
          'plaintext' => CssUnicodeBidi.plaintext,
          _ => CssUnicodeBidi.normal,
        },
        inherited: (p) => p.unicodeBidi,
      ),
      listStyleType: listStyleType,
      visible: switch (_value('visibility')) {
        null => parent!.visible,
        CssKeyword(name: 'visible') => true,
        _ => false,
      },
      widows: integer('widows', (p) => p.widows, 2),
      orphans: integer('orphans', (p) => p.orphans, 2),
      writingMode: _keyword(
        'writing-mode',
        CssWritingMode.values,
        (k) => switch (k) {
          'vertical-rl' ||
          'sideways-rl' ||
          'tb' ||
          'tb-rl' => CssWritingMode.verticalRl,
          'vertical-lr' || 'sideways-lr' => CssWritingMode.verticalLr,
          _ => CssWritingMode.horizontalTb,
        },
        inherited: (p) => p.writingMode,
      ),
      overflowWrap: _keyword(
        'overflow-wrap',
        CssOverflowWrap.values,
        (k) => switch (k) {
          'break-word' => CssOverflowWrap.breakWord,
          'anywhere' => CssOverflowWrap.anywhere,
          _ => CssOverflowWrap.normal,
        },
        inherited: (p) => p.overflowWrap,
      ),
      wordBreak: wordBreak,
      borderCollapse: switch (_value('border-collapse')) {
        null => parent!.borderCollapse,
        CssKeyword(:final name) => name == 'collapse',
        _ => false,
      },
      borderSpacingX: spacingX,
      borderSpacingY: spacingY,
      captionSide: _keyword(
        'caption-side',
        CssCaptionSide.values,
        (k) => k == 'bottom' || k == 'block-end'
            ? CssCaptionSide.bottom
            : CssCaptionSide.top,
        inherited: (p) => p.captionSide,
      ),
      overflowX: _keyword(
        'overflow-x',
        CssOverflow.values,
        (k) => switch (k) {
          'hidden' => CssOverflow.hidden,
          'clip' => CssOverflow.clip,
          'scroll' => CssOverflow.scroll,
          'auto' => CssOverflow.auto,
          _ => CssOverflow.visible,
        },
        inherited: (p) => p.overflowX,
      ),
      position: _keyword(
        'position',
        CssPosition.values,
        (k) => switch (k) {
          'relative' => CssPosition.relative,
          'absolute' => CssPosition.absolute,
          'fixed' => CssPosition.fixed,
          'sticky' => CssPosition.sticky,
          _ => CssPosition.static,
        },
        inherited: (p) => p.position,
      ),
      offsets: CssEdges(
        _length('top', nullKeyword: 'auto', inherited: (p) => p.offsets.top),
        _length(
          'right',
          nullKeyword: 'auto',
          inherited: (p) => p.offsets.right,
        ),
        _length(
          'bottom',
          nullKeyword: 'auto',
          inherited: (p) => p.offsets.bottom,
        ),
        _length('left', nullKeyword: 'auto', inherited: (p) => p.offsets.left),
      ),
      borderRadius: CssCorners(
        radius('top-left', (p) => p.borderRadius.topLeft),
        radius('top-right', (p) => p.borderRadius.topRight),
        radius('bottom-right', (p) => p.borderRadius.bottomRight),
        radius('bottom-left', (p) => p.borderRadius.bottomLeft),
      ),
      boxSizing: _keyword(
        'box-sizing',
        CssBoxSizing.values,
        (k) => k == 'border-box'
            ? CssBoxSizing.borderBox
            : CssBoxSizing.contentBox,
        inherited: (p) => p.boxSizing,
      ),
      quotes: switch (_value('quotes')) {
        null => parent!.quotes,
        CssQuotesValue(:final marks) => marks,
        CssKeyword(name: 'none') => const [],
        _ => null,
      },
      listStyleInside: switch (_value('list-style-position')) {
        null => parent!.listStyleInside,
        CssKeyword(:final name) => name == 'inside',
        _ => false,
      },
      content: switch (_value('content')) {
        CssContentValue(:final items) => items,
        _ => null,
      },
      counterReset: _countersOf('counter-reset'),
      counterIncrement: _countersOf('counter-increment'),
      counterSet: _countersOf('counter-set'),
      customProperties: customProperties,
    );
  }

  List<(String, int)> _countersOf(String name) => switch (_value(name)) {
    CssCountersValue(:final counters) => counters,
    _ => const [],
  };

  /// A corner's radii in px, or percentages kept for the layout.
  CssRadius radius(String corner, CssRadius Function(ComputedStyle) inherited) {
    final value = _value('border-$corner-radius');
    if (value == null) return inherited(parent!);
    if (value is! CssLengthPairValue) return CssRadius.zero;
    CssLength resolve(CssLength length) => length.computedIn(lengths);
    return CssRadius(resolve(value.first), resolve(value.second));
  }

  /// `word-break: break-word` is `overflow-wrap: anywhere` with `normal`
  /// breaking (CSS Text 3); it computes to `normal` here and the wrap
  /// side is the layout's, which breaks long words anyway.
  CssWordBreak get wordBreak => _keyword(
    'word-break',
    CssWordBreak.values,
    (k) => switch (k) {
      'break-all' => CssWordBreak.breakAll,
      'keep-all' => CssWordBreak.keepAll,
      _ => CssWordBreak.normal,
    },
    inherited: (p) => p.wordBreak,
  );

  /// `border-spacing` in px, horizontal and vertical.
  (double, double) _borderSpacing() => switch (_value('border-spacing')) {
    null => (parent!.borderSpacingX, parent!.borderSpacingY),
    CssLengthPairValue(:final first, :final second) => (
      first.toPx(lengths),
      second.toPx(lengths),
    ),
    _ => (0, 0),
  };

  static T _parentEdge<T>(CssEdges<T> edges, String edge) => switch (edge) {
    'top' => edges.top,
    'right' => edges.right,
    'bottom' => edges.bottom,
    _ => edges.left,
  };

  int _fontWeight() {
    final value = _value('font-weight');
    final parentWeight = parent?.fontWeight ?? 400;
    return switch (value) {
      null => parentWeight,
      CssNumberValue(:final value) => value.round().clamp(1, 1000),
      CssKeyword(name: 'bold') => 700,
      CssKeyword(name: 'bolder') =>
        parentWeight < 350
            ? 400
            : parentWeight < 550
            ? 700
            : 900,
      CssKeyword(name: 'lighter') =>
        parentWeight < 100
            ? parentWeight
            : parentWeight < 550
            ? 100
            : parentWeight < 750
            ? 400
            : 700,
      _ => 400,
    };
  }
}
