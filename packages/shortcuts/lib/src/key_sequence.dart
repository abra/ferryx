import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Two-key sequences in the Vim style (`dd`, `gg`): the first key arms a
/// prefix, the second completes it. The prefix lives here, shared by every
/// activator of the app, and lapses after [timeout] or when any other
/// command runs.
abstract final class KeySequenceState {
  static const timeout = Duration(seconds: 1);

  static LogicalKeyboardKey? _pending;
  static DateTime _armedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static final _changes = _Changes();

  static LogicalKeyboardKey? get pending =>
      DateTime.now().difference(_armedAt) <= timeout ? _pending : null;

  /// How long the armed prefix has left before it lapses.
  static Duration get remaining {
    final left = timeout - DateTime.now().difference(_armedAt);
    return _pending == null || left.isNegative ? Duration.zero : left;
  }

  /// Notifies on every arm and clear, so a view can show what may follow
  /// the prefix ([pending]). The lapse after [timeout] notifies nobody (no
  /// timer runs here): a view that shows the prefix ends that on its own
  /// clock, after [remaining].
  static Listenable get changes => _changes;

  static void arm(LogicalKeyboardKey key) {
    _pending = key;
    _armedAt = DateTime.now();
    _changes.changed();
  }

  static void clear() {
    if (_pending == null) return;
    _pending = null;
    _changes.changed();
  }
}

class _Changes extends ChangeNotifier {
  void changed() => notifyListeners();
}

/// Raised by the first key of a sequence; handled by [KeyPrefixAction] so
/// the key is consumed and does not reach anything below.
class KeyPrefixIntent extends Intent {
  const KeyPrefixIntent(this.key);

  final LogicalKeyboardKey key;
}

class KeyPrefixAction extends Action<KeyPrefixIntent> {
  @override
  Object? invoke(KeyPrefixIntent intent) => null;
}

/// Arms [prefix] when it is pressed on its own (no modifiers).
class PrefixActivator extends ShortcutActivator {
  const PrefixActivator(this.prefix);

  final LogicalKeyboardKey prefix;

  @override
  Iterable<LogicalKeyboardKey>? get triggers => [prefix];

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    if (event is! KeyDownEvent || event.logicalKey != prefix) return false;
    if (state.isShiftPressed ||
        state.isAltPressed ||
        state.isControlPressed ||
        state.isMetaPressed) {
      return false;
    }
    KeySequenceState.arm(prefix);
    return true;
  }

  @override
  String debugDescribeKeys() => '${prefix.debugName} (prefix)';
}

/// Fires on [second] only while [prefix] is armed; registered before the
/// prefix's own activator so the completing key is not re-armed instead.
class SequenceActivator extends ShortcutActivator {
  const SequenceActivator(this.prefix, this.second);

  final LogicalKeyboardKey prefix;
  final ShortcutActivator second;

  @override
  Iterable<LogicalKeyboardKey>? get triggers => second.triggers;

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    if (event is! KeyDownEvent || KeySequenceState.pending != prefix) {
      return false;
    }
    if (!second.accepts(event, state)) return false;
    KeySequenceState.clear();
    return true;
  }

  @override
  String debugDescribeKeys() =>
      '${prefix.debugName} ${second.debugDescribeKeys()}';
}
