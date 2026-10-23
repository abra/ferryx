import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows [builder]'s dialog over the window the platform's way (the
/// theme's barrier, no dismissal by a click beside it) and gives the focus
/// back to what had it when the dialog closes.
Future<T?> showWorkspaceDialog<T>(
  BuildContext context,
  WidgetBuilder builder,
) => showAppDialog<T>(context, builder);

/// A labelled field of a dialog.
class DialogField extends StatelessWidget {
  const DialogField({
    required this.label,
    required this.controller,
    this.hint,
    this.autofocus = false,
    this.focusNode,
    this.onSubmitted,
    this.obscure = false,
    this.monospace = false,
    this.enabled = true,
    this.readOnly = false,
    this.trailing,
    this.keyboardType,
    this.inputFormatters,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final bool obscure;
  final bool monospace;
  final bool enabled;

  /// Kept from edits, focus and all: a field waiting on what was typed
  /// (a password being tried) is read-only, never disabled, as a disabled
  /// field gives the focus away and the keys would go to the window.
  final bool readOnly;
  final Widget? trailing;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      readOnly: readOnly,
      // The dialog sets the selection it wants (a name's stem, the caret
      // after `*.`); the desktop's select-all on focus would undo it.
      selectAllOnFocus: false,
      // Return submits and the field keeps the keys: Flutter's default
      // drops the focus, and a dialog that stays (a wrong password, a
      // name taken) would leave the keys to the window behind it.
      onEditingComplete: onSubmitted == null ? null : () {},
      obscureText: obscure,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: monospace ? context.mono : null,
      decoration: InputDecoration(hintText: hint),
      onSubmitted: onSubmitted,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.text.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        trailing == null
            ? field
            : Row(
                children: [
                  Expanded(child: field),
                  SizedBox(width: context.metrics.toolbarSpacing),
                  trailing!,
                ],
              ),
      ],
    );
  }
}

/// An option of a dialog: the platform's check box with its label, which
/// takes effect with the dialog's button.
class DialogToggle extends StatelessWidget {
  const DialogToggle({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) =>
      AppCheckbox(value: value, onChanged: onChanged, label: label);
}

/// A row of a dialog with a label and a pop-up choice at its end; the
/// pop-up is never squeezed.
class DialogChoice<T> extends StatelessWidget {
  const DialogChoice({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final String label;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => AppControlRow(
    label: label,
    control: AppPopupButton<T>(
      value: value,
      items: items,
      onChanged: onChanged,
    ),
  );
}

/// A dialog's default button, disabled while any of [controllers] is
/// empty, so Return never submits nothing.
class DialogSubmitButton extends StatelessWidget {
  const DialogSubmitButton({
    required this.label,
    required this.controllers,
    required this.onPressed,
    this.enabled = true,
    super.key,
  });

  final String label;
  final List<TextEditingController> controllers;
  final VoidCallback onPressed;

  /// A further condition, besides the fields being filled.
  final bool enabled;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge(controllers),
    builder: (context, _) {
      final filled = controllers.every((c) => c.text.trim().isNotEmpty);
      return FilledButton(
        onPressed: enabled && filled ? onPressed : null,
        child: Text(label),
      );
    },
  );
}

/// The gap between a dialog's rows.
const dialogRowGap = SizedBox(height: AppSpacing.md);

/// The names of [items] for a title: the single name, else their count.
String firstName(List<String> names) => names.isEmpty ? '' : names.first;
