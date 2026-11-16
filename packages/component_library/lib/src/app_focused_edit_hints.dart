import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shortcuts/shortcuts.dart' show Chord;

import 'app_key_hints.dart';
import 'app_text_field.dart';
import 'app_guidance_scope.dart';
import 'popup_focus.dart';

/// Native text-editing keys for the focused field in this route/focus scope.
/// Keeps file or screen hints out of text editing without adding app commands
/// to the component library. It never reads the system clipboard.
class AppFocusedEditHints extends StatelessWidget {
  const AppFocusedEditHints({
    required this.fallback,
    this.builder,
    this.scope,
    super.key,
  });

  final Widget fallback;

  /// Hosts can preserve their existing status-bar/help/overflow presentation.
  final Widget Function(List<AppKeyHint> hints)? builder;

  /// Defaults to this widget's enclosing scope. A sibling footer can pass the
  /// screen context; fields in a dialog or another route do not belong to it.
  final BuildContext? scope;

  @override
  Widget build(BuildContext context) {
    final owner = scope ?? context;
    if (AppGuidanceScope.maybeOf(owner)?.enabled == false) return fallback;
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
            !focus.ancestors.contains(focusScope)) {
          return fallback;
        }
        final editable = focused.findAncestorStateOfType<EditableTextState>();
        if (editable == null) return fallback;
        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: editable.widget.controller,
          builder: (context, value, _) {
            // A field can rebuild its submit label on a text change without
            // rebuilding this footer. Read its current metadata only while
            // the same editor still has attached focus.
            final current = attachedFocusContext(focus);
            if (current == null ||
                !editable.mounted ||
                !identical(FocusManager.instance.primaryFocus, focus) ||
                !identical(
                  current.findAncestorStateOfType<EditableTextState>(),
                  editable,
                )) {
              return fallback;
            }
            final field = current.findAncestorWidgetOfExactType<AppTextField>();
            final l10n = MaterialLocalizations.of(context);
            // These are native editor keys, independent of app key bindings.
            final platform = Theme.of(context).platform;
            final hasSelection =
                value.selection.isValid &&
                !value.selection.isCollapsed &&
                !editable.widget.obscureText;
            final hints = [
              if (field?.submitLabel case final label?
                  when field!.onSubmitted != null &&
                      editable.widget.maxLines == 1 &&
                      !editable.widget.readOnly)
                AppKeyHint(
                  [Chord.keyLabel(LogicalKeyboardKey.enter, platform)],
                  label,
                ),
              if (value.text.isNotEmpty)
                AppKeyHint([
                  const Chord(
                    LogicalKeyboardKey.keyA,
                    primary: true,
                  ).label(platform),
                ], l10n.selectAllButtonLabel),
              if (hasSelection)
                AppKeyHint([
                  const Chord(
                    LogicalKeyboardKey.keyC,
                    primary: true,
                  ).label(platform),
                ], l10n.copyButtonLabel),
              if (hasSelection && !editable.widget.readOnly)
                AppKeyHint([
                  const Chord(
                    LogicalKeyboardKey.keyX,
                    primary: true,
                  ).label(platform),
                ], l10n.cutButtonLabel),
              if (!editable.widget.readOnly)
                AppKeyHint([
                  const Chord(
                    LogicalKeyboardKey.keyV,
                    primary: true,
                  ).label(platform),
                ], l10n.pasteButtonLabel),
            ];
            return builder?.call(hints) ?? AppKeyHints(hints, singleLine: true);
          },
        );
      },
    );
  }
}
