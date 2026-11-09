/// Selectors (Selectors Level 3, the part books use): parsing from a
/// rule's prelude, specificity, and matching against a
/// [ContentDocument] element by index.
///
/// Supported: type and universal selectors with or without a namespace
/// prefix (`epub|type`, matched by the prefix the document writes),
/// `.class`, `#id`, attribute selectors with every operator and the `i`
/// flag, `:first-child`, `:last-child`, `:only-child`, `:nth-child(an+b)`,
/// `:nth-last-child`, `:first-of-type`, `:last-of-type`, `:only-of-type`,
/// `:nth-of-type`, `:nth-last-of-type`, `:root`, `:empty`, `:link`,
/// `:lang()`, and Selectors 4's `:not()`, `:is()`, `:where()` and
/// `:has()` over selector lists; the descendant, child, adjacent and
/// general sibling combinators; selector lists. A pseudo-element
/// (`::before`) makes the selector its pseudo-element's
/// ([CssSelector.pseudoElement]); dynamic pseudo-classes (`:hover`)
/// parse and never match, so their rules do not invalidate a list. An
/// unknown selector invalidates its whole rule, as the spec says.
library;

import '../document/content_document.dart';
import 'css_syntax.dart';
import 'css_tokenizer.dart';

/// `a, b, c`: a rule applies when any selector matches.
class CssSelectorList {
  const CssSelectorList(this.selectors);

  final List<CssSelector> selectors;

  /// Parses a rule prelude. Null when any selector is invalid: the rule
  /// is dropped.
  static CssSelectorList? parse(List<CssComponentValue> prelude) {
    final selectors = <CssSelector>[];
    var start = 0;
    for (var i = 0; i <= prelude.length; i++) {
      final atComma =
          i < prelude.length &&
          prelude[i] is CssTokenValue &&
          (prelude[i] as CssTokenValue).token.type == CssTokenType.comma;
      if (i == prelude.length || atComma) {
        final selector = CssSelector.parse(prelude.sublist(start, i));
        if (selector == null) return null;
        selectors.add(selector);
        start = i + 1;
      }
    }
    return CssSelectorList(selectors);
  }

  /// Parses selector text.
  static CssSelectorList? parseText(String text) =>
      parse(parseCssComponentValues(text));

  @override
  String toString() => selectors.join(', ');
}

enum CssCombinator { descendant, child, adjacentSibling, generalSibling }

/// A complex selector: compounds joined by combinators, matched right
/// to left.
class CssSelector {
  const CssSelector(
    this.compounds,
    this.combinators,
    this.specificity, {
    this.pseudoElement,
  }) : assert(combinators.length == compounds.length - 1);

  /// The pseudo-element the selector styles (`before`, `after`,
  /// `first-letter` …), or null for the element itself.
  final String? pseudoElement;

  /// Left to right.
  final List<CssCompoundSelector> compounds;

  /// `combinators[i]` joins `compounds[i]` and `compounds[i + 1]`.
  final List<CssCombinator> combinators;

  /// Packed as `ids * 1_000_000 + classes * 1_000 + types`.
  final int specificity;

  /// Whether a never-matching pseudo-class makes this selector match
  /// nothing.
  bool get neverMatches => compounds.any((c) => c.neverMatches);

  static CssSelector? parse(List<CssComponentValue> values) =>
      _SelectorParser(values).parseComplex();

  /// Whether [element] is the selector's subject. A selector of a
  /// pseudo-element styles that, never the element.
  bool matches(ContentDocument doc, int element) {
    if (pseudoElement != null || neverMatches) return false;
    return _matchFrom(doc, element, compounds.length - 1);
  }

  /// Whether [element] originates the pseudo-element this selector
  /// styles: everything but the pseudo-element matches.
  bool matchesOriginating(ContentDocument doc, int element) {
    if (neverMatches) return false;
    return _matchFrom(doc, element, compounds.length - 1);
  }

  /// For a relative selector of `:has()`: whether [element] matches with
  /// its leftmost compound tied to [anchor] by [lead].
  bool _matchesRelative(
    ContentDocument doc,
    int element,
    int anchor,
    CssCombinator lead,
  ) {
    if (neverMatches) return false;
    return _matchFrom(doc, element, compounds.length - 1, (e) {
      switch (lead) {
        case CssCombinator.child:
          return doc.parentOf(e) == anchor;
        case CssCombinator.descendant:
          for (
            var p = doc.parentOf(e);
            p != ContentDocument.none;
            p = doc.parentOf(p)
          ) {
            if (p == anchor) return true;
          }
          return false;
        case CssCombinator.adjacentSibling:
          return _previousElementSibling(doc, e) == anchor;
        case CssCombinator.generalSibling:
          for (
            var s = _previousElementSibling(doc, e);
            s != ContentDocument.none;
            s = _previousElementSibling(doc, s)
          ) {
            if (s == anchor) return true;
          }
          return false;
      }
    });
  }

  /// Matches compounds `0..index` with `compounds[index]` on [element];
  /// [leftmost], when given, must also hold for the element the first
  /// compound lands on.
  bool _matchFrom(
    ContentDocument doc,
    int element,
    int index, [
    bool Function(int)? leftmost,
  ]) {
    if (!compounds[index].matches(doc, element)) return false;
    if (index == 0) return leftmost == null || leftmost(element);
    switch (combinators[index - 1]) {
      case CssCombinator.child:
        final parent = doc.parentOf(element);
        return parent != ContentDocument.none &&
            _matchFrom(doc, parent, index - 1, leftmost);
      case CssCombinator.descendant:
        for (
          var p = doc.parentOf(element);
          p != ContentDocument.none;
          p = doc.parentOf(p)
        ) {
          if (_matchFrom(doc, p, index - 1, leftmost)) return true;
        }
        return false;
      case CssCombinator.adjacentSibling:
        final previous = _previousElementSibling(doc, element);
        return previous != ContentDocument.none &&
            _matchFrom(doc, previous, index - 1, leftmost);
      case CssCombinator.generalSibling:
        for (
          var s = _previousElementSibling(doc, element);
          s != ContentDocument.none;
          s = _previousElementSibling(doc, s)
        ) {
          if (_matchFrom(doc, s, index - 1, leftmost)) return true;
        }
        return false;
    }
  }

  @override
  String toString() {
    final buffer = StringBuffer(compounds.first.toString());
    for (var i = 0; i < combinators.length; i++) {
      buffer
        ..write(switch (combinators[i]) {
          CssCombinator.descendant => ' ',
          CssCombinator.child => ' > ',
          CssCombinator.adjacentSibling => ' + ',
          CssCombinator.generalSibling => ' ~ ',
        })
        ..write(compounds[i + 1]);
    }
    if (pseudoElement != null) buffer.write('::$pseudoElement');
    return buffer.toString();
  }
}

int _previousElementSibling(ContentDocument doc, int element) =>
    doc.parentOf(element) == ContentDocument.none
    ? ContentDocument.none
    : doc.previousElementSiblingOf(element);

/// `tag.class#id[attr]:pseudo`: every simple selector must match.
class CssCompoundSelector {
  const CssCompoundSelector(
    this.type,
    this.simples, {
    this.unmatchable = const [],
  });

  /// Lowercased local name, or null for the universal selector.
  final String? type;
  final List<CssSimpleSelector> simples;

  /// Pseudo-elements (`::before`) and dynamic pseudo-classes (`:hover`)
  /// as written: parsed so the rule stays valid, matching nothing.
  final List<String> unmatchable;

  bool get neverMatches => unmatchable.isNotEmpty;

  bool matches(ContentDocument doc, int element) {
    if (type != null && doc.localNameOf(element).toLowerCase() != type) {
      return false;
    }
    for (final simple in simples) {
      if (!simple.matches(doc, element)) return false;
    }
    return true;
  }

  @override
  String toString() =>
      '${type ?? (simples.isEmpty && unmatchable.isEmpty ? '*' : '')}'
      '${simples.join()}${unmatchable.join()}';
}

sealed class CssSimpleSelector {
  const CssSimpleSelector();

  bool matches(ContentDocument doc, int element);
}

class CssIdSelector extends CssSimpleSelector {
  const CssIdSelector(this.id);

  final String id;

  @override
  bool matches(ContentDocument doc, int element) => doc.idOf(element) == id;

  @override
  String toString() => '#$id';
}

class CssClassSelector extends CssSimpleSelector {
  const CssClassSelector(this.name);

  final String name;

  @override
  bool matches(ContentDocument doc, int element) {
    final classes = doc.attributeOf(element, 'class');
    if (classes == null) return false;
    // Whitespace-separated, no allocation for the common single class.
    var start = 0;
    while (start < classes.length) {
      while (start < classes.length && _isSpace(classes.codeUnitAt(start))) {
        start++;
      }
      var end = start;
      while (end < classes.length && !_isSpace(classes.codeUnitAt(end))) {
        end++;
      }
      if (end - start == name.length && classes.startsWith(name, start)) {
        return true;
      }
      start = end;
    }
    return false;
  }

  static bool _isSpace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C;

  @override
  String toString() => '.$name';
}

enum CssAttributeOperator {
  exists,
  equals,
  includes,
  dashMatch,
  prefix,
  suffix,
  substring,
}

class CssAttributeSelector extends CssSimpleSelector {
  const CssAttributeSelector(
    this.name,
    this.operator,
    this.value, {
    this.anyNamespace = false,
    this.ignoreCase = false,
  });

  /// As the document writes it: `epub:type` for `[epub|type]`.
  final String name;
  final CssAttributeOperator operator;
  final String value;

  /// `[*|type]`: `type` under any prefix or none.
  final bool anyNamespace;

  /// The `i` flag.
  final bool ignoreCase;

  @override
  bool matches(ContentDocument doc, int element) {
    final found = anyNamespace
        ? _anyNamespace(doc, element)
        : doc.attributeOf(element, name);
    if (found == null) return false;
    final actual = ignoreCase ? found.toLowerCase() : found;
    final value = ignoreCase ? this.value.toLowerCase() : this.value;
    switch (operator) {
      case CssAttributeOperator.exists:
        return true;
      case CssAttributeOperator.equals:
        return actual == value;
      case CssAttributeOperator.includes:
        return value.isNotEmpty && actual.split(RegExp(r'\s+')).contains(value);
      case CssAttributeOperator.dashMatch:
        return actual == value || actual.startsWith('$value-');
      case CssAttributeOperator.prefix:
        return value.isNotEmpty && actual.startsWith(value);
      case CssAttributeOperator.suffix:
        return value.isNotEmpty && actual.endsWith(value);
      case CssAttributeOperator.substring:
        return value.isNotEmpty && actual.contains(value);
    }
  }

  String? _anyNamespace(ContentDocument doc, int element) {
    for (final (attribute, value) in doc.attributesOf(element)) {
      final colon = attribute.indexOf(':');
      if ((colon < 0 ? attribute : attribute.substring(colon + 1)) == name) {
        return value;
      }
    }
    return null;
  }

  @override
  String toString() {
    final op = switch (operator) {
      CssAttributeOperator.exists => '',
      CssAttributeOperator.equals => '=',
      CssAttributeOperator.includes => '~=',
      CssAttributeOperator.dashMatch => '|=',
      CssAttributeOperator.prefix => '^=',
      CssAttributeOperator.suffix => r'$=',
      CssAttributeOperator.substring => '*=',
    };
    return '[$name$op${op.isEmpty ? '' : '"$value"'}]';
  }
}

/// `:first-child` and the other structural pseudo-classes.
class CssPseudoClassSelector extends CssSimpleSelector {
  const CssPseudoClassSelector(
    this.name, {
    this.a = 0,
    this.b = 0,
    this.argument,
  });

  final String name;

  /// For `:nth-child(an+b)` and `:nth-last-child`.
  final int a;
  final int b;

  /// For `:lang()`.
  final String? argument;

  @override
  bool matches(ContentDocument doc, int element) {
    final isRoot = doc.parentOf(element) == ContentDocument.none;
    switch (name) {
      case 'root':
        return isRoot;
      case 'first-child':
        return isRoot ||
            doc.previousElementSiblingOf(element) == ContentDocument.none;
      case 'last-child':
        return isRoot ||
            doc.nextElementSiblingOf(element) == ContentDocument.none;
      case 'only-child':
        return isRoot ||
            (doc.previousElementSiblingOf(element) == ContentDocument.none &&
                doc.nextElementSiblingOf(element) == ContentDocument.none);
      case 'nth-child':
        return _nthMatches(doc.elementIndexOf(element));
      case 'nth-last-child':
        return _nthMatches(_indexFromEnd(doc, element));
      case 'first-of-type':
        return isRoot || !_hasSameTypeSibling(doc, element, forward: false);
      case 'last-of-type':
        return isRoot || !_hasSameTypeSibling(doc, element, forward: true);
      case 'only-of-type':
        return isRoot ||
            (!_hasSameTypeSibling(doc, element, forward: false) &&
                !_hasSameTypeSibling(doc, element, forward: true));
      case 'nth-of-type':
        return _nthMatches(_typeIndex(doc, element, forward: false));
      case 'nth-last-of-type':
        return _nthMatches(_typeIndex(doc, element, forward: true));
      case 'empty':
        return doc.childCountOf(element) == 0;
      case 'link' || 'any-link':
        return switch (doc.localNameOf(element).toLowerCase()) {
          'a' || 'area' || 'link' => doc.attributeOf(element, 'href') != null,
          _ => false,
        };
      case 'lang':
        final lang = _languageOf(doc, element);
        if (lang == null || argument == null) return false;
        final lower = lang.toLowerCase();
        final wanted = argument!.toLowerCase();
        return lower == wanted || lower.startsWith('$wanted-');
      default:
        return false;
    }
  }

  bool _nthMatches(int index) {
    if (a == 0) return index == b;
    final n = (index - b) / a;
    return n >= 0 && n == n.truncateToDouble();
  }

  static int _indexFromEnd(ContentDocument doc, int element) {
    final parent = doc.parentOf(element);
    if (parent == ContentDocument.none) return 1;
    return doc.elementChildCountOf(parent) - doc.elementIndexOf(element) + 1;
  }

  /// Whether a sibling element before (or after) has the same name: a
  /// walk that stops at the first one, short for runs of paragraphs.
  static bool _hasSameTypeSibling(
    ContentDocument doc,
    int element, {
    required bool forward,
  }) {
    final name = doc.localNameOf(element);
    var s = forward
        ? doc.nextElementSiblingOf(element)
        : doc.previousElementSiblingOf(element);
    while (s != ContentDocument.none) {
      if (doc.localNameOf(s) == name) return true;
      s = forward
          ? doc.nextElementSiblingOf(s)
          : doc.previousElementSiblingOf(s);
    }
    return false;
  }

  /// The element's place among its siblings of its name, from 1: from
  /// the first, or from the last ([forward]).
  static int _typeIndex(
    ContentDocument doc,
    int element, {
    required bool forward,
  }) {
    final name = doc.localNameOf(element);
    var index = 1;
    for (
      var s = forward
          ? doc.nextElementSiblingOf(element)
          : doc.previousElementSiblingOf(element);
      s != ContentDocument.none;
      s = forward
          ? doc.nextElementSiblingOf(s)
          : doc.previousElementSiblingOf(s)
    ) {
      if (doc.localNameOf(s) == name) index++;
    }
    return index;
  }

  static String? _languageOf(ContentDocument doc, int element) {
    for (var e = element; e != ContentDocument.none; e = doc.parentOf(e)) {
      final lang = doc.attributeOf(e, 'xml:lang') ?? doc.attributeOf(e, 'lang');
      if (lang != null) return lang;
    }
    return null;
  }

  @override
  String toString() => switch (name) {
    'nth-child' ||
    'nth-last-child' ||
    'nth-of-type' ||
    'nth-last-of-type' => ':$name(${a}n+$b)',
    'lang' => ':lang($argument)',
    _ => ':$name',
  };
}

/// `:not(a, b)`: none of the selectors match.
class CssNotSelector extends CssSimpleSelector {
  const CssNotSelector(this.inner);

  final List<CssSelector> inner;

  @override
  bool matches(ContentDocument doc, int element) =>
      !inner.any((s) => s.matches(doc, element));

  @override
  String toString() => ':not(${inner.join(', ')})';
}

/// `:is(a, b)` and `:where(a, b)`: any of the selectors matches. They
/// differ in specificity only.
class CssIsSelector extends CssSimpleSelector {
  const CssIsSelector(this.name, this.inner);

  final String name;
  final List<CssSelector> inner;

  @override
  bool matches(ContentDocument doc, int element) =>
      inner.any((s) => s.matches(doc, element));

  @override
  String toString() => ':$name(${inner.join(', ')})';
}

/// `:has(> img, p)`: some element related to this one as a relative
/// selector says matches it (a descendant when it starts with no
/// combinator).
class CssHasSelector extends CssSimpleSelector {
  const CssHasSelector(this.relative);

  final List<({CssCombinator lead, CssSelector selector})> relative;

  @override
  bool matches(ContentDocument doc, int element) {
    for (final (:lead, :selector) in relative) {
      switch (lead) {
        case CssCombinator.child || CssCombinator.descendant:
          final end = doc.subtreeEndOf(element);
          for (var n = element + 1; n < end; n++) {
            if (doc.isElement(n) &&
                selector._matchesRelative(doc, n, element, lead)) {
              return true;
            }
          }
        case CssCombinator.adjacentSibling || CssCombinator.generalSibling:
          final parent = doc.parentOf(element);
          if (parent == ContentDocument.none) continue;
          final end = doc.subtreeEndOf(parent);
          for (var n = doc.subtreeEndOf(element); n < end; n++) {
            if (doc.isElement(n) &&
                selector._matchesRelative(doc, n, element, lead)) {
              return true;
            }
          }
      }
    }
    return false;
  }

  @override
  String toString() => ':has(${relative.map((r) => r.selector).join(', ')})';
}

/// Pseudo-classes that depend on state a static layout has none of.
/// Nothing is visited, so `:link` is every link (see [_linkPseudoClasses]).
const _dynamicPseudoClasses = {
  'hover',
  'active',
  'focus',
  'focus-within',
  'focus-visible',
  'visited',
  'target',
  'checked',
  'disabled',
  'enabled',
};

const _structuralPseudoClasses = {
  'root',
  'first-child',
  'last-child',
  'only-child',
  'first-of-type',
  'last-of-type',
  'only-of-type',
  'empty',
  ..._linkPseudoClasses,
};

/// `:link` and `:any-link`: an `a`, `area` or `link` with an `href`, as
/// in a browser where nothing has been visited.
const _linkPseudoClasses = {'link', 'any-link'};

class _SelectorParser {
  _SelectorParser(this._values);

  final List<CssComponentValue> _values;
  int _i = 0;

  CssComponentValue? get _peek => _i < _values.length ? _values[_i] : null;

  CssToken? get _peekToken {
    final v = _peek;
    return v is CssTokenValue ? v.token : null;
  }

  void _skipWhitespace() {
    while (_peekToken?.isWhitespace ?? false) {
      _i++;
    }
  }

  CssSelector? parseComplex() {
    _skipWhitespace();
    final compounds = <CssCompoundSelector>[];
    final combinators = <CssCombinator>[];
    var specificity = 0;
    String? pseudoElement;
    while (true) {
      // A pseudo-element ends the selector.
      if (pseudoElement != null) return null;
      final compound = _parseCompound();
      if (compound == null) return null;
      compounds.add(compound.selector);
      specificity += compound.specificity;
      pseudoElement = compound.pseudoElement;
      final sawWhitespace = _peekToken?.isWhitespace ?? false;
      _skipWhitespace();
      final t = _peekToken;
      if (t == null) break;
      if (t.isDelim('>')) {
        combinators.add(CssCombinator.child);
      } else if (t.isDelim('+')) {
        combinators.add(CssCombinator.adjacentSibling);
      } else if (t.isDelim('~')) {
        combinators.add(CssCombinator.generalSibling);
      } else if (sawWhitespace) {
        combinators.add(CssCombinator.descendant);
        continue;
      } else {
        return null;
      }
      _i++;
      _skipWhitespace();
      if (_peek == null) return null;
    }
    if (compounds.isEmpty) return null;
    return CssSelector(
      compounds,
      combinators,
      specificity,
      pseudoElement: pseudoElement,
    );
  }

  /// A relative selector of `:has()`: an optional leading combinator,
  /// descendant when there is none, then a complex selector.
  ({CssCombinator lead, CssSelector selector})? parseRelative() {
    _skipWhitespace();
    final t = _peekToken;
    var lead = CssCombinator.descendant;
    if (t != null) {
      final combinator = t.isDelim('>')
          ? CssCombinator.child
          : t.isDelim('+')
          ? CssCombinator.adjacentSibling
          : t.isDelim('~')
          ? CssCombinator.generalSibling
          : null;
      if (combinator != null) {
        lead = combinator;
        _i++;
      }
    }
    final selector = parseComplex();
    if (selector == null || selector.pseudoElement != null) return null;
    return (lead: lead, selector: selector);
  }

  ({CssCompoundSelector selector, int specificity, String? pseudoElement})?
  _parseCompound() {
    String? type;
    String? pseudoElement;
    final simples = <CssSimpleSelector>[];
    final unmatchable = <String>[];
    var ids = 0;
    var classes = 0;
    var types = 0;
    var any = false;
    // `ns|type`, `*|type`, `|type`: the namespace is not checked; type
    // names are local names.
    final first = _peekToken;
    final second = _i + 1 < _values.length ? _values[_i + 1] : null;
    final prefixed =
        second is CssTokenValue &&
        second.token.isDelim('|') &&
        first != null &&
        (first.type == CssTokenType.ident || first.isDelim('*'));
    if (prefixed) _i += 2;
    if (!prefixed && first != null && first.isDelim('|')) _i++;
    final name = _peekToken;
    if (name != null && name.type == CssTokenType.ident) {
      type = name.value.toLowerCase();
      types++;
      any = true;
      _i++;
    } else if (name != null && name.isDelim('*')) {
      any = true;
      _i++;
    } else if (prefixed || (first != null && first.isDelim('|'))) {
      return null;
    }
    while (true) {
      final v = _peek;
      if (v == null) break;
      if (v is CssBlockValue && v.open == CssTokenType.openSquare) {
        final attribute = _parseAttribute(v.values);
        if (attribute == null) return null;
        simples.add(attribute);
        classes++;
        _i++;
        any = true;
        continue;
      }
      if (v is CssFunctionValue) return null;
      if (v is! CssTokenValue) return null;
      final t = v.token;
      if (t.type == CssTokenType.hash) {
        if (!t.isId) return null;
        simples.add(CssIdSelector(t.value));
        ids++;
        _i++;
        any = true;
      } else if (t.isDelim('.')) {
        _i++;
        final name = _peekToken;
        if (name == null || name.type != CssTokenType.ident) return null;
        simples.add(CssClassSelector(name.value));
        classes++;
        _i++;
        any = true;
      } else if (t.type == CssTokenType.colon) {
        _i++;
        final next = _peek;
        if (next is CssTokenValue && next.token.type == CssTokenType.colon) {
          // A pseudo-element: the selector styles it, not the element.
          _i++;
          final name = _peekToken;
          if (name == null || name.type != CssTokenType.ident) return null;
          if (pseudoElement != null) return null;
          _i++;
          pseudoElement = name.value.toLowerCase();
          types++;
          any = true;
        } else if (next is CssTokenValue &&
            next.token.type == CssTokenType.ident) {
          final name = next.token.value.toLowerCase();
          _i++;
          if (_structuralPseudoClasses.contains(name)) {
            simples.add(CssPseudoClassSelector(name));
            classes++;
          } else if (_dynamicPseudoClasses.contains(name)) {
            unmatchable.add(':$name');
            classes++;
          } else if (name == 'first-line' ||
              name == 'first-letter' ||
              name == 'before' ||
              name == 'after') {
            // CSS 2 single-colon pseudo-elements.
            if (pseudoElement != null) return null;
            pseudoElement = name;
            types++;
          } else {
            return null;
          }
          any = true;
        } else if (next is CssFunctionValue) {
          final selector = _parseFunctionalPseudo(next);
          if (selector == null) return null;
          _i++;
          simples.add(selector.selector);
          classes += selector.specificity ~/ 1000 % 1000;
          ids += selector.specificity ~/ 1000000;
          types += selector.specificity % 1000;
          any = true;
        } else {
          return null;
        }
      } else {
        break;
      }
    }
    if (!any) return null;
    return (
      selector: CssCompoundSelector(type, simples, unmatchable: unmatchable),
      specificity: ids * 1000000 + classes * 1000 + types,
      pseudoElement: pseudoElement,
    );
  }

  ({CssSimpleSelector selector, int specificity})? _parseFunctionalPseudo(
    CssFunctionValue function,
  ) {
    final name = function.name.toLowerCase();
    final arguments = function.arguments
        .where((v) => !(v is CssTokenValue && v.token.isWhitespace))
        .toList();
    switch (name) {
      case 'nth-child' ||
          'nth-last-child' ||
          'nth-of-type' ||
          'nth-last-of-type':
        final nth = _parseNth(function.arguments);
        if (nth == null) return null;
        return (
          selector: CssPseudoClassSelector(name, a: nth.$1, b: nth.$2),
          specificity: 1000,
        );
      case 'lang':
        if (arguments.length != 1) return null;
        final v = arguments.single;
        if (v is! CssTokenValue ||
            (v.token.type != CssTokenType.ident &&
                v.token.type != CssTokenType.string)) {
          return null;
        }
        return (
          selector: CssPseudoClassSelector('lang', argument: v.token.value),
          specificity: 1000,
        );
      case 'not':
        final list = _selectorList(function.arguments, forgiving: false);
        if (list == null || list.isEmpty) return null;
        return (
          selector: CssNotSelector(list),
          specificity: _maxSpecificity(list),
        );
      case 'is' || 'matches' || '-webkit-any' || 'where':
        final list = _selectorList(function.arguments, forgiving: true)!;
        return (
          selector: CssIsSelector(name == 'where' ? 'where' : 'is', list),
          specificity: name == 'where' ? 0 : _maxSpecificity(list),
        );
      case 'has':
        final relative = <({CssCombinator lead, CssSelector selector})>[];
        for (final part in _splitOnCommas(function.arguments)) {
          final parsed = _SelectorParser(part).parseRelative();
          if (parsed == null) return null;
          relative.add(parsed);
        }
        if (relative.isEmpty) return null;
        return (
          selector: CssHasSelector(relative),
          specificity: _maxSpecificity([for (final r in relative) r.selector]),
        );
      default:
        return null;
    }
  }

  /// The complex selectors of a functional pseudo-class's argument; with
  /// [forgiving] (`:is()`, `:where()`) an invalid one is left out rather
  /// than invalidating the list. A pseudo-element is never allowed.
  static List<CssSelector>? _selectorList(
    List<CssComponentValue> values, {
    required bool forgiving,
  }) {
    final out = <CssSelector>[];
    for (final part in _splitOnCommas(values)) {
      final selector = CssSelector.parse(part);
      if (selector == null || selector.pseudoElement != null) {
        if (forgiving) continue;
        return null;
      }
      out.add(selector);
    }
    return out;
  }

  static List<List<CssComponentValue>> _splitOnCommas(
    List<CssComponentValue> values,
  ) {
    final parts = <List<CssComponentValue>>[[]];
    for (final v in values) {
      if (v is CssTokenValue && v.token.type == CssTokenType.comma) {
        parts.add([]);
      } else {
        parts.last.add(v);
      }
    }
    return [
      for (final part in parts)
        if (part.any((v) => !(v is CssTokenValue && v.token.isWhitespace)))
          part,
    ];
  }

  static int _maxSpecificity(List<CssSelector> selectors) =>
      selectors.fold(0, (m, s) => s.specificity > m ? s.specificity : m);

  /// The `An+B` microsyntax over tokens: `odd`, `even`, `3`, `2n`,
  /// `2n+1`, `-n+2`, `n`, `2n - 1`. The tokenizer folds `2n-1` into one
  /// dimension and keeps a sign only on negative numbers, so the pieces
  /// are read back from token values rather than from their text.
  static (int, int)? _parseNth(List<CssComponentValue> values) {
    final tokens = [
      for (final v in values)
        if (v is CssTokenValue && !v.token.isWhitespace)
          v.token
        else if (v is! CssTokenValue)
          null,
    ];
    if (tokens.isEmpty || tokens.contains(null)) return null;
    var i = 0;
    final first = tokens[i]!;
    int a;
    String rest;
    switch (first.type) {
      case CssTokenType.ident when first.value.toLowerCase() == 'odd':
        return tokens.length == 1 ? (2, 1) : null;
      case CssTokenType.ident when first.value.toLowerCase() == 'even':
        return tokens.length == 1 ? (2, 0) : null;
      case CssTokenType.number when first.isInteger:
        return tokens.length == 1 ? (0, first.number.toInt()) : null;
      case CssTokenType.dimension when first.isInteger:
        final unit = first.unit;
        if (!unit.startsWith('n')) return null;
        a = first.number.toInt();
        rest = unit.substring(1);
        i++;
      case CssTokenType.ident:
        final name = first.value.toLowerCase();
        if (name.startsWith('-n')) {
          a = -1;
          rest = name.substring(2);
        } else if (name.startsWith('n')) {
          a = 1;
          rest = name.substring(1);
        } else {
          return null;
        }
        i++;
      case CssTokenType.delim when first.value == '+':
        i++;
        if (i >= tokens.length || tokens[i]!.type != CssTokenType.ident) {
          return null;
        }
        final name = tokens[i]!.value.toLowerCase();
        if (!name.startsWith('n')) return null;
        a = 1;
        rest = name.substring(1);
        i++;
      default:
        return null;
    }
    // `rest` is what followed the `n` inside the same token: '', '-',
    // '-1' or '+1'; a sign alone means the number is the next token.
    var b = 0;
    if (rest.isNotEmpty) {
      if (rest == '-' || rest == '+') {
        if (i >= tokens.length || tokens[i]!.type != CssTokenType.number) {
          return null;
        }
        final n = tokens[i]!;
        if (!n.isInteger || n.number < 0) return null;
        b = (rest == '-' ? -1 : 1) * n.number.toInt();
        i++;
      } else {
        final parsed = int.tryParse(rest);
        if (parsed == null) return null;
        b = parsed;
      }
    } else if (i < tokens.length) {
      final t = tokens[i]!;
      if (t.type == CssTokenType.number) {
        // `2n +1` and `2n -1`: the sign is in the number.
        if (!t.isInteger) return null;
        b = t.number.toInt();
        i++;
      } else if (t.isDelim('+') || t.isDelim('-')) {
        i++;
        if (i >= tokens.length || tokens[i]!.type != CssTokenType.number) {
          return null;
        }
        final n = tokens[i]!;
        if (!n.isInteger || n.number < 0) return null;
        b = (t.value == '-' ? -1 : 1) * n.number.toInt();
        i++;
      }
    }
    return i == tokens.length ? (a, b) : null;
  }

  static CssAttributeSelector? _parseAttribute(List<CssComponentValue> values) {
    final tokens = [
      for (final v in values)
        if (v is CssTokenValue && !v.token.isWhitespace)
          v.token
        else if (v is! CssTokenValue)
          null,
    ];
    if (tokens.isEmpty || tokens.contains(null)) return null;
    // `[ns|name]`, `[*|name]`, `[|name]`: the document writes `ns:name`.
    var anyNamespace = false;
    String? prefix;
    if (tokens.length >= 3 &&
        tokens[1]!.isDelim('|') &&
        tokens[2]!.type == CssTokenType.ident &&
        (tokens[0]!.type == CssTokenType.ident || tokens[0]!.isDelim('*'))) {
      if (tokens[0]!.isDelim('*')) {
        anyNamespace = true;
      } else {
        prefix = tokens[0]!.value;
      }
      tokens.removeRange(0, 2);
    } else if (tokens.length >= 2 &&
        tokens[0]!.isDelim('|') &&
        tokens[1]!.type == CssTokenType.ident) {
      tokens.removeAt(0);
    }
    final name = tokens[0]!;
    if (name.type != CssTokenType.ident) return null;
    final qualified = prefix == null ? name.value : '$prefix:${name.value}';
    if (tokens.length == 1) {
      return CssAttributeSelector(
        qualified,
        CssAttributeOperator.exists,
        '',
        anyNamespace: anyNamespace,
      );
    }
    // `=` is a delim; `~=` etc. are a delim followed by `=`.
    CssAttributeOperator? operator;
    var valueIndex = 2;
    final op = tokens[1]!;
    if (op.isDelim('=')) {
      operator = CssAttributeOperator.equals;
    } else if (tokens.length > 3 && tokens[2]!.isDelim('=')) {
      operator = switch (op.value) {
        '~' => CssAttributeOperator.includes,
        '|' => CssAttributeOperator.dashMatch,
        '^' => CssAttributeOperator.prefix,
        r'$' => CssAttributeOperator.suffix,
        '*' => CssAttributeOperator.substring,
        _ => null,
      };
      valueIndex = 3;
    }
    if (operator == null) return null;
    final rest = tokens.sublist(valueIndex);
    // An optional `i` (case-insensitive) or `s` flag.
    var ignoreCase = false;
    if (rest.length == 2 && rest[1]!.type == CssTokenType.ident) {
      final flag = rest[1]!.value.toLowerCase();
      if (flag != 'i' && flag != 's') return null;
      ignoreCase = flag == 'i';
      rest.removeLast();
    }
    if (rest.length != 1) return null;
    final value = rest.single!;
    if (value.type != CssTokenType.ident && value.type != CssTokenType.string) {
      return null;
    }
    return CssAttributeSelector(
      qualified,
      operator,
      value.value,
      anyNamespace: anyNamespace,
      ignoreCase: ignoreCase,
    );
  }
}
