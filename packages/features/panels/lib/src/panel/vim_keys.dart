import 'package:flutter/services.dart';

/// What a key did in Vim mode, as [VimKeys.feed] answers it.
sealed class VimKeyOutcome {
  const VimKeyOutcome();
}

/// The key was not Vim's: it goes on to the shortcuts.
class VimIgnored extends VimKeyOutcome {
  const VimIgnored();
}

/// The key was taken: a digit of a count, or Esc clearing what waited.
class VimConsumed extends VimKeyOutcome {
  const VimConsumed();
}

/// `f`/`F` and the letter: the row whose name starts with it, forward or
/// back.
class VimFindChar extends VimKeyOutcome {
  const VimFindChar(this.char, {required this.forward});

  final String char;
  final bool forward;
}

/// `m` and a letter.
class VimSetMark extends VimKeyOutcome {
  const VimSetMark(this.letter);

  final String letter;
}

/// `'` or `` ` `` and a letter; `''` is the place before.
class VimGoMark extends VimKeyOutcome {
  const VimGoMark(this.letter);

  final String letter;
}

/// A key that waits for the next one.
enum VimPending { findForward, findBackward, setMark, goMark }

/// The part of Vim mode that lives between two keys: a count typed
/// before a motion (`3j`, `10G`), a key waiting for its character (`f`,
/// `m`, `'`), and the last `f` for `;` and `,`. The modes themselves
/// (Visual, Search, the command line) are the panel's state.
class VimKeys {
  static const int maxCount = 9999;

  int? count;
  VimPending? pending;
  VimFindChar? lastFind;

  /// Feeds a key pressed in Normal or Visual mode with no modifier but
  /// Shift, as [character] types it.
  VimKeyOutcome feed({required LogicalKeyboardKey key, String? character}) {
    if (key == LogicalKeyboardKey.escape) {
      if (count == null && pending == null) return const VimIgnored();
      clear();
      return const VimConsumed();
    }
    final waiting = pending;
    if (waiting != null) {
      pending = null;
      if (character == null || character.isEmpty) return const VimConsumed();
      switch (waiting) {
        case VimPending.findForward:
          lastFind = VimFindChar(character, forward: true);
          return lastFind!;
        case VimPending.findBackward:
          lastFind = VimFindChar(character, forward: false);
          return lastFind!;
        case VimPending.setMark:
          return _isLetter(character)
              ? VimSetMark(character)
              : const VimConsumed();
        case VimPending.goMark:
          if (character == "'" || character == '`') return const VimGoMark("'");
          return _isLetter(character)
              ? VimGoMark(character)
              : const VimConsumed();
      }
    }
    if (character != null && character.length == 1) {
      final digit = int.tryParse(character);
      if (digit != null) {
        // `0` alone is no count; after a digit it is one.
        if (count == null && digit == 0) return const VimIgnored();
        count = ((count ?? 0) * 10 + digit).clamp(0, maxCount);
        return const VimConsumed();
      }
    }
    return const VimIgnored();
  }

  /// The count typed, or [fallback], and the count is spent.
  int takeCount([int fallback = 1]) {
    final value = count ?? fallback;
    count = null;
    return value;
  }

  /// Whether a count was typed (a plain `G` goes to the end, `3G` to row 3).
  bool get hasCount => count != null;

  /// `;` repeats the last `f`/`F`; `,` repeats it the other way.
  VimFindChar? repeatFind({required bool reverse}) {
    final last = lastFind;
    if (last == null) return null;
    return VimFindChar(
      last.char,
      forward: reverse ? !last.forward : last.forward,
    );
  }

  void clear() {
    count = null;
    pending = null;
  }

  /// What waits, as typed: `3`, `f`, `3f`, `m`, `'`.
  String get pendingText {
    final buffer = StringBuffer();
    if (count != null) buffer.write(count);
    switch (pending) {
      case null:
        break;
      case VimPending.findForward:
        buffer.write('f');
      case VimPending.findBackward:
        buffer.write('F');
      case VimPending.setMark:
        buffer.write('m');
      case VimPending.goMark:
        buffer.write("'");
    }
    return buffer.toString();
  }

  static bool _isLetter(String c) =>
      c.length == 1 && RegExp(r'^[A-Za-z]$').hasMatch(c);
}
