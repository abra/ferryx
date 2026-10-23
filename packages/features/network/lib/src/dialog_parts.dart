import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A labelled text field of the network's dialogs.
class NetworkField extends StatelessWidget {
  const NetworkField({
    required this.label,
    required this.controller,
    this.hint,
    this.focusNode,
    this.autofocus = false,
    this.obscure = false,
    this.monospace = false,
    this.enabled = true,
    this.readOnly = false,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.keyboardType,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool obscure;
  final bool monospace;
  final bool enabled;

  /// Shown but not edited (a connection under way): unlike a disabled
  /// field it keeps the focus, so Esc still reaches the dialog.
  final bool readOnly;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: context.text.labelMedium),
      const SizedBox(height: AppSpacing.xs),
      TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        enabled: enabled,
        readOnly: readOnly,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: !obscure,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: monospace ? context.mono : null,
        decoration: InputDecoration(hintText: hint),
        onChanged: onChanged,
        // Return submits and the field keeps the focus: Esc still reaches
        // the dialog, and a second try needs no click.
        onEditingComplete: () {},
        onSubmitted: onSubmitted,
      ),
    ],
  );
}

/// A line with an icon in a tone: a warning, an error, a state.
class NetworkNote extends StatelessWidget {
  const NetworkNote({
    required this.icon,
    required this.text,
    required this.color,
    this.maxLines = 3,
    super.key,
  });

  /// The danger colour for an error, the warning one for a caution.
  factory NetworkNote.error(BuildContext context, String text) => NetworkNote(
    icon: AppIcons.error,
    text: text,
    color: context.appColors.danger,
  );

  /// A connection that is not encrypted.
  factory NetworkNote.insecure(BuildContext context, String text) =>
      NetworkNote(
        icon: AppIcons.unlocked,
        text: text,
        // The tag palette's orange: a caution, not an error.
        color: context.appColors.ink(1),
      );

  final IconData icon;
  final String text;
  final Color color;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final style = context.text.bodySmall!;
    final line = MediaQuery.textScalerOf(
      context,
    ).scale(style.fontSize! * (style.height ?? 1.2));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The icon sits on the first line, whatever the text's size.
        SizedBox(
          height: line,
          child: Icon(icon, size: AppIconSize.sm, color: color),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: style.copyWith(color: color),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The gap between a dialog's rows.
const networkRowGap = SizedBox(height: AppSpacing.md);
