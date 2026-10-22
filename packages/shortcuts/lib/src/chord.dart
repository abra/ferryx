import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'key_sequence.dart';

/// A key plus modifiers, written once for every platform.
///
/// [primary] is the platform's command modifier: ⌘ on macOS, Ctrl elsewhere.
/// [control] and [alt] are explicit and never remapped. A [prefix] makes a
/// Vim-style two-key sequence (`dd`, `gg`): the prefix is pressed alone
/// first, within a second.
@immutable
class Chord extends Equatable {
  const Chord(
    this.key, {
    this.primary = false,
    this.shift = false,
    this.alt = false,
    this.control = false,
    this.prefix,
  });

  final LogicalKeyboardKey key;
  final bool primary;
  final bool shift;
  final bool alt;
  final bool control;
  final LogicalKeyboardKey? prefix;

  bool get hasModifier => primary || shift || alt || control;

  /// Activator for the `Shortcuts` map: a sequence when there is a prefix.
  /// With ⇧ on a key that ⇧ turns into another glyph, it answers the key
  /// under either name ([shiftedKeys]).
  ShortcutActivator toShortcutActivator(TargetPlatform platform) {
    final base = toActivator(platform);
    final shifted = shift ? shiftedKeys[key] : null;
    final single = shifted == null
        ? base
        : _EitherActivator(
            base,
            SingleActivator(
              shifted,
              meta: base.meta,
              control: base.control,
              shift: true,
              alt: base.alt,
            ),
          );
    return switch (prefix) {
      null => single,
      final prefix => SequenceActivator(prefix, single),
    };
  }

  /// What ⇧ makes of a key on a US layout. macOS names a key pressed with
  /// ⇧ by the glyph it types (⇧\ arrives as `bar`, ⇧[ as `braceLeft`;
  /// a digit stays a digit there), the other desktops may name the key: a
  /// chord is written with the key and answers both.
  static final shiftedKeys = {
    LogicalKeyboardKey.backslash: LogicalKeyboardKey.bar,
    LogicalKeyboardKey.bracketLeft: LogicalKeyboardKey.braceLeft,
    LogicalKeyboardKey.bracketRight: LogicalKeyboardKey.braceRight,
    LogicalKeyboardKey.slash: LogicalKeyboardKey.question,
    LogicalKeyboardKey.semicolon: LogicalKeyboardKey.colon,
    LogicalKeyboardKey.quoteSingle: LogicalKeyboardKey.quote,
    LogicalKeyboardKey.comma: LogicalKeyboardKey.less,
    LogicalKeyboardKey.period: LogicalKeyboardKey.greater,
    LogicalKeyboardKey.backquote: LogicalKeyboardKey.tilde,
    LogicalKeyboardKey.minus: LogicalKeyboardKey.underscore,
    LogicalKeyboardKey.equal: LogicalKeyboardKey.add,
    LogicalKeyboardKey.digit1: LogicalKeyboardKey.exclamation,
    LogicalKeyboardKey.digit2: LogicalKeyboardKey.at,
    LogicalKeyboardKey.digit3: LogicalKeyboardKey.numberSign,
    LogicalKeyboardKey.digit4: LogicalKeyboardKey.dollar,
    LogicalKeyboardKey.digit5: LogicalKeyboardKey.percent,
    LogicalKeyboardKey.digit6: LogicalKeyboardKey.caret,
    LogicalKeyboardKey.digit7: LogicalKeyboardKey.ampersand,
    LogicalKeyboardKey.digit8: LogicalKeyboardKey.asterisk,
    LogicalKeyboardKey.digit9: LogicalKeyboardKey.parenthesisLeft,
    LogicalKeyboardKey.digit0: LogicalKeyboardKey.parenthesisRight,
  };

  static final _unshifted = {
    for (final MapEntry(:key, :value) in shiftedKeys.entries) value: key,
  };

  /// [key] as written in a chord: the key ⇧ was pressed with, `backslash`
  /// for `bar`. A chord recorded from a key event goes through it.
  static LogicalKeyboardKey unshifted(LogicalKeyboardKey key) =>
      _unshifted[key] ?? key;

  /// Flutter activator for [platform].
  SingleActivator toActivator(TargetPlatform platform) {
    final isMac = platform == TargetPlatform.macOS;
    return SingleActivator(
      key,
      meta: primary && isMac,
      control: control || (primary && !isMac),
      shift: shift,
      alt: alt,
    );
  }

  /// Human-readable label: `⌘⇧K` on macOS, `Ctrl+Shift+K` elsewhere; a
  /// sequence reads as Vim writes it, `dd`, its second key as ⇧ makes it
  /// (`gE`).
  String label(TargetPlatform platform) {
    final prefix = this.prefix;
    if (prefix != null) {
      final second = keyLabel(key, platform);
      return '${keyLabel(prefix, platform).toLowerCase()}'
          '${shift ? second.toUpperCase() : second.toLowerCase()}';
    }
    // A key Vim names by what ⇧ makes of it: `$`, `{`, `}`.
    if (shift && !primary && !alt && !control) {
      final glyph = _shiftedGlyphs[key];
      if (glyph != null) return glyph;
    }
    final isMac = platform == TargetPlatform.macOS;
    final parts = <String>[];
    if (isMac) {
      if (control) parts.add('⌃');
      if (alt) parts.add('⌥');
      if (shift) parts.add('⇧');
      if (primary) parts.add('⌘');
      parts.add(keyLabel(key, platform));
      return parts.join();
    }
    if (primary || control) parts.add('Ctrl');
    if (alt) parts.add('Alt');
    if (shift) parts.add('Shift');
    parts.add(keyLabel(key, platform));
    return parts.join('+');
  }

  /// The label Vim's help gives the chord: a letter as it is typed (`w`,
  /// `W` with ⇧, `⌃d` on macOS), a sequence as one word (`gg`, `iW`), a key
  /// Vim names by what ⇧ makes of it (`$`). A chord with ⌘ or ⌥, or with
  /// Ctrl where Ctrl is the command key, reads as [label] has it.
  String vimLabel(TargetPlatform platform) {
    if (prefix != null || primary || alt) return label(platform);
    final letter = isLetter(key);
    if (control) {
      return platform == TargetPlatform.macOS && letter && !shift
          ? '⌃${keyLabel(key, platform).toLowerCase()}'
          : label(platform);
    }
    if (!letter) return label(platform);
    final name = keyLabel(key, platform);
    return shift ? name.toUpperCase() : name.toLowerCase();
  }

  /// Whether Vim names the chord by one key as typed: no modifier, or ⇧
  /// on a letter (`G`) or on a key whose shifted glyph Vim writes (`$`).
  bool get isVimKey =>
      !primary &&
      !alt &&
      !control &&
      (!shift || isLetter(key) || _shiftedGlyphs.containsKey(key));

  /// Whether [key] is one of the letters `a` to `z`.
  static bool isLetter(LogicalKeyboardKey key) =>
      key.keyId >= LogicalKeyboardKey.keyA.keyId &&
      key.keyId <= LogicalKeyboardKey.keyZ.keyId;

  static final _shiftedGlyphs = {
    LogicalKeyboardKey.digit3: '#',
    LogicalKeyboardKey.digit4: r'$',
    LogicalKeyboardKey.digit6: '^',
    LogicalKeyboardKey.digit8: '*',
    LogicalKeyboardKey.digit9: '(',
    LogicalKeyboardKey.digit0: ')',
    LogicalKeyboardKey.bracketLeft: '{',
    LogicalKeyboardKey.bracketRight: '}',
  };

  /// The key a platform's users call delete, for actions that take either
  /// Delete or Backspace: ⌫ on a Mac keyboard (which has no Delete key of
  /// that name), Del elsewhere.
  static String deleteLabel(TargetPlatform platform) => keyLabel(
    platform == TargetPlatform.macOS
        ? LogicalKeyboardKey.backspace
        : LogicalKeyboardKey.delete,
    platform,
  );

  /// Whether the platform's primary modifier (⌘, elsewhere Ctrl) is held:
  /// a click with it opens in a new tab.
  static bool primaryHeld(TargetPlatform platform) =>
      platform == TargetPlatform.macOS
      ? HardwareKeyboard.instance.isMetaPressed
      : HardwareKeyboard.instance.isControlPressed;

  /// Label of a single key.
  static String keyLabel(LogicalKeyboardKey key, TargetPlatform platform) {
    final isMac = platform == TargetPlatform.macOS;
    if (key == LogicalKeyboardKey.arrowUp) return '↑';
    if (key == LogicalKeyboardKey.arrowDown) return '↓';
    if (key == LogicalKeyboardKey.arrowLeft) return '←';
    if (key == LogicalKeyboardKey.arrowRight) return '→';
    if (key == LogicalKeyboardKey.enter) return isMac ? '↩' : 'Enter';
    if (key == LogicalKeyboardKey.escape) return 'Esc';
    if (key == LogicalKeyboardKey.tab) return 'Tab';
    if (key == LogicalKeyboardKey.space) return isMac ? 'Space' : 'Space';
    if (key == LogicalKeyboardKey.backspace) return isMac ? '⌫' : 'Backspace';
    if (key == LogicalKeyboardKey.delete) return isMac ? '⌦' : 'Del';
    if (key == LogicalKeyboardKey.backslash) return r'\';
    if (key == LogicalKeyboardKey.slash) return '/';
    if (key == LogicalKeyboardKey.period) return '.';
    if (key == LogicalKeyboardKey.semicolon) return ';';
    if (key == LogicalKeyboardKey.quoteSingle) return "'";
    if (key == LogicalKeyboardKey.comma) return ',';
    if (key == LogicalKeyboardKey.bracketLeft) return '[';
    if (key == LogicalKeyboardKey.bracketRight) return ']';
    if (key == LogicalKeyboardKey.equal) return '=';
    if (key == LogicalKeyboardKey.minus) return '−';
    if (key == LogicalKeyboardKey.f2) return 'F2';
    if (key == LogicalKeyboardKey.pageUp) return isMac ? '⇞' : 'PgUp';
    if (key == LogicalKeyboardKey.pageDown) return isMac ? '⇟' : 'PgDn';
    if (key == LogicalKeyboardKey.shift ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight) {
      return isMac ? '⇧' : 'Shift';
    }
    if (key == LogicalKeyboardKey.alt ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight) {
      return isMac ? '⌥' : 'Alt';
    }
    if (key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight) {
      return isMac ? '⌃' : 'Ctrl';
    }
    if (key == LogicalKeyboardKey.contextMenu) return 'Menu';
    final label = key.keyLabel;
    return label.length == 1 ? label.toUpperCase() : label;
  }

  @override
  List<Object?> get props => [
    key.keyId,
    primary,
    shift,
    alt,
    control,
    prefix?.keyId,
  ];
}

/// Either of two activators: a key with ⇧ under its own name or under the
/// glyph ⇧ makes of it.
class _EitherActivator extends ShortcutActivator {
  const _EitherActivator(this.first, this.second);

  final SingleActivator first;
  final SingleActivator second;

  @override
  Iterable<LogicalKeyboardKey>? get triggers => [
    ...first.triggers,
    ...second.triggers,
  ];

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) =>
      first.accepts(event, state) || second.accepts(event, state);

  @override
  String debugDescribeKeys() =>
      '${first.debugDescribeKeys()} | ${second.debugDescribeKeys()}';
}
