import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/build_context_ext.dart';
import '../theme/tokens/app_spacing.dart';
import 'hint_registry.dart';
import '../theme/hairlines.dart';

/// Hint mode (⌘J): draws a letter label on every visible target of
/// [registry] and runs the target whose label is typed.
///
/// Takes keyboard focus while shown; the host removes it through
/// [onDismiss]. Esc, a click or an unknown key cancels, Shift+label runs the
/// target's alternative action, chords with ⌘/Ctrl pass through.
class HintOverlay extends StatefulWidget {
  const HintOverlay({
    required this.registry,
    required this.onDismiss,
    required this.message,
    super.key,
  });

  final HintRegistry registry;
  final VoidCallback onDismiss;

  /// Footer explaining the keys.
  final String message;

  @override
  State<HintOverlay> createState() => _HintOverlayState();
}

class _HintOverlayState extends State<HintOverlay> {
  final _focus = FocusNode(debugLabel: 'hints');
  FocusNode? _previousFocus;
  List<HintAnchor> _anchors = const [];
  List<String> _labels = const [];
  String _typed = '';

  @override
  void initState() {
    super.initState();
    _previousFocus = widget.registry.focusBefore =
        FocusManager.instance.primaryFocus;
    // Targets are measured after this frame, once the overlay has a size.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject()! as RenderBox;
      final anchors = widget.registry.collect(box);
      setState(() {
        _anchors = anchors;
        _labels = hintLabels(anchors.length);
      });
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    final previous = _previousFocus;
    // A target that took the focus itself (a panel edge, a field) keeps it;
    // otherwise it goes back to where it was.
    if (_focus.hasFocus &&
        previous != null &&
        previous.context?.mounted == true) {
      previous.requestFocus();
    }
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed || keyboard.isControlPressed) {
      // Chords (⌘J, ⌘K…) keep working; hint mode gives way to them.
      widget.onDismiss();
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (_modifiers.contains(key)) return KeyEventResult.handled;
    if (key == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      if (_typed.isNotEmpty) {
        setState(() => _typed = _typed.substring(0, _typed.length - 1));
      }
      return KeyEventResult.handled;
    }
    final letter = _letters[event.physicalKey];
    if (letter == null) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }
    final typed = _typed + letter;
    final matches = [
      for (var i = 0; i < _labels.length; i++)
        if (_labels[i].startsWith(typed)) i,
    ];
    if (matches.isEmpty) return KeyEventResult.handled;
    if (matches.length == 1 && _labels[matches.single] == typed) {
      _activate(matches.single, alt: keyboard.isShiftPressed);
    } else {
      setState(() => _typed = typed);
    }
    return KeyEventResult.handled;
  }

  void _activate(int index, {required bool alt}) {
    final anchor = _anchors[index];
    final action = alt
        ? anchor.onActivateAlt ?? anchor.onActivate
        : anchor.onActivate;
    widget.onDismiss();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final labelStyle = context.metrics.typeScale.keyCap.copyWith(
      color: colors.hintForeground,
    );
    // Above the app's Material: without a style of its own the labels
    // would take Flutter's fallback, a yellow double underline.
    return DefaultTextStyle(
      style: context.text.bodyMedium!,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerDown: (_) => widget.onDismiss(),
          behavior: HitTestBehavior.translucent,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned.fill(child: SizedBox.expand()),
              for (var i = 0; i < _anchors.length; i++)
                if (_labels[i].startsWith(_typed))
                  Positioned(
                    left: (_anchors[i].rect.left - 4).clamp(
                      0.0,
                      double.infinity,
                    ),
                    top: (_anchors[i].rect.top - 2).clamp(0.0, double.infinity),
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                        decoration: appEdgedBox(
                          color: colors.hintBackground,
                          edge: colors.hintBorder,
                          radius: context.metrics.radius.chip,
                        ),
                        child: Text(_labels[i], style: labelStyle),
                      ),
                    ),
                  ),
              Positioned(
                left: 0,
                right: 0,
                bottom: AppSpacing.lg,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs + 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.toastBackground,
                        borderRadius: BorderRadius.circular(
                          context.metrics.radius.card,
                        ),
                      ),
                      child: Text(
                        widget.message,
                        style: context.text.bodySmall?.copyWith(
                          color: colors.toastForeground,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final _modifiers = <LogicalKeyboardKey>{
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.capsLock,
};

final _letters = <PhysicalKeyboardKey, String>{
  PhysicalKeyboardKey.keyA: 'a',
  PhysicalKeyboardKey.keyB: 'b',
  PhysicalKeyboardKey.keyC: 'c',
  PhysicalKeyboardKey.keyD: 'd',
  PhysicalKeyboardKey.keyE: 'e',
  PhysicalKeyboardKey.keyF: 'f',
  PhysicalKeyboardKey.keyG: 'g',
  PhysicalKeyboardKey.keyH: 'h',
  PhysicalKeyboardKey.keyI: 'i',
  PhysicalKeyboardKey.keyJ: 'j',
  PhysicalKeyboardKey.keyK: 'k',
  PhysicalKeyboardKey.keyL: 'l',
  PhysicalKeyboardKey.keyM: 'm',
  PhysicalKeyboardKey.keyN: 'n',
  PhysicalKeyboardKey.keyO: 'o',
  PhysicalKeyboardKey.keyP: 'p',
  PhysicalKeyboardKey.keyQ: 'q',
  PhysicalKeyboardKey.keyR: 'r',
  PhysicalKeyboardKey.keyS: 's',
  PhysicalKeyboardKey.keyT: 't',
  PhysicalKeyboardKey.keyU: 'u',
  PhysicalKeyboardKey.keyV: 'v',
  PhysicalKeyboardKey.keyW: 'w',
  PhysicalKeyboardKey.keyX: 'x',
  PhysicalKeyboardKey.keyY: 'y',
  PhysicalKeyboardKey.keyZ: 'z',
};
