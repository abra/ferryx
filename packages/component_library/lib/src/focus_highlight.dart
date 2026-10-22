import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Shows keyboard focus only while the keyboard is in use, as macOS,
/// Windows 11 and GNOME do: a pointer press hides every focus ring, the
/// next key brings it back on whatever has the focus. Flutter's automatic
/// strategy hides rings only after a touch, so a mouse click left the ring
/// on the control that last had the focus.
///
/// It drives [FocusManager.highlightStrategy], so Material's own focus
/// highlights follow as well. One per app, attached for its lifetime; the
/// app starts with rings hidden, as the platforms do until a key is used.
final class FocusHighlightTracker {
  FocusHighlightTracker.attach()
    : _previous = FocusManager.instance.highlightStrategy {
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
    _use(FocusHighlightStrategy.alwaysTouch);
  }

  final FocusHighlightStrategy _previous;

  /// Keys that only modify a click or another key: holding ⌘ to ⌘-click
  /// must not show the rings.
  static final _modifiers = {
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.fn,
    LogicalKeyboardKey.fnLock,
  };

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) _use(FocusHighlightStrategy.alwaysTouch);
  }

  bool _onKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyDownEvent &&
        !_modifiers.contains(event.logicalKey) &&
        // A ⌘ or ⌃ chord runs a command; it is not the keyboard taking
        // over the controls.
        !keyboard.isMetaPressed &&
        !keyboard.isControlPressed) {
      _use(FocusHighlightStrategy.alwaysTraditional);
    }
    return false; // Only listening: the key goes on to its handler.
  }

  static void _use(FocusHighlightStrategy strategy) {
    final manager = FocusManager.instance;
    if (manager.highlightStrategy != strategy) {
      manager.highlightStrategy = strategy;
    }
  }

  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    HardwareKeyboard.instance.removeHandler(_onKey);
    FocusManager.instance.highlightStrategy = _previous;
  }
}
