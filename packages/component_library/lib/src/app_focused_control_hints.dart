import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoButton;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shortcuts/shortcuts.dart' show Chord;

import 'app_checkbox.dart';
import 'app_focused_edit_hints.dart';
import 'app_guidance_scope.dart';
import 'app_key_hints.dart';
import 'app_nav_item.dart';
import 'app_popup_button.dart';
import 'app_segmented_control.dart';
import 'app_toggle.dart';
import 'popup_focus.dart';

/// Guidance for the control that currently owns keyboard focus.
///
/// The controls retain their existing key handlers and focus nodes. Only
/// controls with known bindings participate; custom lists supply their own
/// fallback, and fields are handled by [AppFocusedEditHints].
class AppFocusedControlHints extends StatelessWidget {
  const AppFocusedControlHints({
    required this.fallback,
    this.builder,
    this.scope,
    super.key,
  });

  final Widget fallback;
  final Widget Function(List<AppKeyHint> hints)? builder;
  final BuildContext? scope;

  @override
  Widget build(BuildContext context) {
    final owner = scope ?? context;
    final guidance = AppGuidanceScope.maybeOf(owner);
    if (guidance == null || !guidance.enabled) return fallback;
    final route = ModalRoute.of(owner);
    final focusScope = FocusScope.of(owner);
    return ListenableBuilder(
      listenable: FocusManager.instance,
      builder: (context, _) {
        final focus = FocusManager.instance.primaryFocus;
        final focused = attachedFocusContext(focus);
        if (route?.isCurrent == false ||
            focus == null ||
            focused == null ||
            !focus.ancestors.contains(focusScope) ||
            focused.findAncestorStateOfType<EditableTextState>() != null) {
          return fallback;
        }
        final hints = _hintsFor(focused, guidance.labels, context);
        if (hints.isEmpty) return fallback;
        return builder?.call(hints) ?? AppKeyHints(hints, singleLine: true);
      },
    );
  }

  static List<AppKeyHint> _hintsFor(
    BuildContext? focused,
    AppGuidanceLabels labels,
    BuildContext context,
  ) {
    if (focused == null) return const [];
    final platform = Theme.of(context).platform;
    AppKeyHint key(LogicalKeyboardKey key, String label) =>
        AppKeyHint([Chord.keyLabel(key, platform)], label);
    AppKeyHint arrows(String label) => AppKeyHint([
      Chord.keyLabel(LogicalKeyboardKey.arrowLeft, platform),
      Chord.keyLabel(LogicalKeyboardKey.arrowRight, platform),
    ], label);
    List<AppKeyHint>? result;
    // Visit nearest first: a pop-up's button must be classified by the pop-up
    // that owns it rather than reported as an unrelated generic action.
    AppKeyHint? button;
    focused.visitAncestorElements((element) {
      final widget = element.widget;
      switch (widget) {
        case AppCheckbox(:final onChanged):
        case AppToggle(:final onChanged):
          result = onChanged == null
              ? const []
              : [key(LogicalKeyboardKey.space, labels.toggle)];
        case AppPopupButton(:final enabled):
          result = enabled
              ? [key(LogicalKeyboardKey.space, labels.choose)]
              : const [];
        case AppSegmentedControl(:final options):
          result = options.length > 1 ? [arrows(labels.choose)] : const [];
        case Slider(:final onChanged):
          result = onChanged == null ? const [] : [arrows(labels.adjust)];
        case AppNavItem(:final onTap):
          result = onTap == null
              ? const []
              : [key(LogicalKeyboardKey.space, labels.choose)];
        case ButtonStyleButton(:final onPressed):
          if (onPressed != null) {
            button = key(LogicalKeyboardKey.space, labels.activate);
          }
        case CupertinoButton(:final onPressed):
          if (onPressed != null) {
            button = key(LogicalKeyboardKey.space, labels.activate);
          }
      }
      return result == null;
    });
    return result ?? [if (button != null) button!];
  }
}
