/// Custom properties and `var()` (CSS Custom Properties for Cascading
/// Variables 1): `--name: value` declarations keep their tokens as
/// written, inherit down the tree, and are substituted into declarations
/// that reference them when the element's style is computed.
library;

import 'css_syntax.dart';
import 'css_tokenizer.dart';
import 'css_values.dart';

/// An element's custom properties: each name's value with the `var()`
/// references in it substituted. An element that declares none shares
/// its parent's set.
class CssCustomProperties {
  const CssCustomProperties._(this._values, this._texts, this._hash);

  factory CssCustomProperties._from(
    Map<String, List<CssComponentValue>> values,
  ) {
    final texts = {for (final e in values.entries) e.key: e.value.join()};
    return CssCustomProperties._(
      values,
      texts,
      Object.hashAllUnordered([
        for (final e in texts.entries) Object.hash(e.key, e.value),
      ]),
    );
  }

  static const empty = CssCustomProperties._({}, {}, 0);

  /// [own], the element's declared values as written, over [parent]'s:
  /// references to other custom properties resolve first; one in a
  /// cycle, or naming nothing without a fallback, is left out (CSS's
  /// guaranteed-invalid value). `initial` drops a property, `inherit`
  /// and `unset` keep the parent's.
  factory CssCustomProperties.of(
    CssCustomProperties parent,
    Map<String, List<CssComponentValue>> own,
  ) {
    if (own.isEmpty) return parent;
    final out = Map.of(parent._values);
    final resolving = <String>{};
    final resolved = <String, List<CssComponentValue>?>{};
    List<CssComponentValue>? resolve(String name) {
      if (resolved.containsKey(name)) return resolved[name];
      final raw = own[name];
      if (raw == null) return parent._values[name];
      if (!resolving.add(name)) return null;
      final value = switch (cssIdentOf(cssWithoutWhitespace(raw))) {
        'initial' => null,
        'inherit' || 'unset' => parent._values[name],
        _ => _substitute(raw, resolve),
      };
      resolving.remove(name);
      return resolved[name] = value;
    }

    for (final name in own.keys) {
      final value = resolve(name);
      if (value == null) {
        out.remove(name);
      } else {
        out[name] = value;
      }
    }
    return CssCustomProperties._from(Map.unmodifiable(out));
  }

  final Map<String, List<CssComponentValue>> _values;

  /// The values as text, for equality.
  final Map<String, String> _texts;
  final int _hash;

  /// The value of custom property [name] (with its `--`), or null.
  List<CssComponentValue>? operator [](String name) => _values[name];

  bool get isEmpty => _values.isEmpty;

  /// [values] with every `var()` in them replaced by its custom
  /// property's value or its fallback (§3), or null when one has
  /// neither: the declaration is then invalid at computed-value time.
  List<CssComponentValue>? substitute(List<CssComponentValue> values) =>
      _substitute(values, (name) => _values[name]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CssCustomProperties ||
        other._hash != _hash ||
        other._texts.length != _texts.length) {
      return false;
    }
    for (final e in _texts.entries) {
      if (other._texts[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => _hash;

  @override
  String toString() => 'CssCustomProperties(${_texts.keys.join(', ')})';
}

/// Whether [values] reference a custom property anywhere, nested in
/// functions and blocks too.
bool cssContainsVar(List<CssComponentValue> values) {
  for (final value in values) {
    switch (value) {
      case CssFunctionValue(:final name, :final arguments):
        if (name.toLowerCase() == 'var' || cssContainsVar(arguments)) {
          return true;
        }
      case CssBlockValue(:final values):
        if (cssContainsVar(values)) return true;
      case CssTokenValue():
        break;
    }
  }
  return false;
}

List<CssComponentValue>? _substitute(
  List<CssComponentValue> values,
  List<CssComponentValue>? Function(String name) lookup,
) {
  final out = <CssComponentValue>[];
  for (final value in values) {
    switch (value) {
      case CssFunctionValue(:final name, :final arguments)
          when name.toLowerCase() == 'var':
        final replaced = _reference(arguments, lookup);
        if (replaced == null) return null;
        out.addAll(replaced);
      case CssFunctionValue(:final name, :final arguments):
        final inner = _substitute(arguments, lookup);
        if (inner == null) return null;
        out.add(CssFunctionValue(name, inner));
      case CssBlockValue(:final open, :final values):
        final inner = _substitute(values, lookup);
        if (inner == null) return null;
        out.add(CssBlockValue(open, inner));
      case CssTokenValue():
        out.add(value);
    }
  }
  return out;
}

/// What `var(--name, fallback)` with [arguments] stands for.
List<CssComponentValue>? _reference(
  List<CssComponentValue> arguments,
  List<CssComponentValue>? Function(String name) lookup,
) {
  var i = 0;
  while (i < arguments.length && _isWhitespace(arguments[i])) {
    i++;
  }
  if (i >= arguments.length) return null;
  final first = arguments[i];
  if (first is! CssTokenValue ||
      first.token.type != CssTokenType.ident ||
      !first.token.value.startsWith('--')) {
    return null;
  }
  final value = lookup(first.token.value);
  if (value != null) return value;
  for (var j = i + 1; j < arguments.length; j++) {
    final a = arguments[j];
    if (a is CssTokenValue && a.token.type == CssTokenType.comma) {
      return _substitute(arguments.sublist(j + 1), lookup);
    }
  }
  return null;
}

bool _isWhitespace(CssComponentValue value) =>
    value is CssTokenValue && value.token.type == CssTokenType.whitespace;
