import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_spacing.dart';

/// A field in a form, a bezel around an inline name, or text inside an editor.
enum AppTextFieldAppearance { standard, inline, embedded }

/// Shared desktop input metrics and editing behavior. Monospace changes the
/// face, keeping the body's size and line height. Return keeps focus unless
/// the owner explicitly hands it elsewhere; supplied controllers remain owned
/// by the caller.
class AppTextField extends StatelessWidget {
  const AppTextField({
    this.controller,
    this.focusNode,
    this.hintText,
    this.errorText,
    this.monospace = false,
    this.appearance = AppTextFieldAppearance.standard,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.selectAllOnFocus,
    this.autocorrect = false,
    this.enableSuggestions,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.textAlign = TextAlign.start,
    this.minLines,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.style,
    this.strutStyle,
    this.decoration = const InputDecoration(),
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final String? errorText;
  final bool monospace;
  final AppTextFieldAppearance appearance;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final bool? selectAllOnFocus;
  final bool autocorrect;
  final bool? enableSuggestions;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final TextAlign textAlign;
  final int? minLines;
  final int? maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;

  /// Embedded editors may align text to their surrounding rows.
  final TextStyle? style;
  final StrutStyle? strutStyle;

  /// Component-library variants use this for search adornments and borders.
  /// Forms use [hintText] and [errorText] instead of overriding decoration.
  final InputDecoration decoration;

  static void _keepFocus() {}

  @override
  Widget build(BuildContext context) {
    final body = context.text.bodyLarge!;
    final base = style ?? body;
    final text = monospace ? context.metrics.monospace(base) : base;
    final resolved = text.copyWith(
      color: enabled ? text.color : context.theme.disabledColor,
    );
    var input = decoration.copyWith(
      hintText: hintText ?? decoration.hintText,
      errorText: errorText ?? decoration.errorText,
      hintStyle:
          decoration.hintStyle ??
          text.copyWith(color: context.appColors.textFaint),
    );
    switch (appearance) {
      case AppTextFieldAppearance.standard:
        break;
      case AppTextFieldAppearance.inline:
        input = input.copyWith(
          filled: true,
          fillColor: context.colors.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        );
      case AppTextFieldAppearance.embedded:
        input = input.copyWith(
          isCollapsed: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        );
    }
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      readOnly: readOnly,
      obscureText: obscureText,
      selectAllOnFocus: selectAllOnFocus,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions ?? !(monospace || obscureText),
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textInputAction: textInputAction,
      textAlign: textAlign,
      minLines: minLines,
      maxLines: maxLines,
      style: resolved,
      strutStyle: strutStyle,
      decoration: input,
      onChanged: onChanged,
      onEditingComplete: onEditingComplete ?? _keepFocus,
      onSubmitted: onSubmitted,
    );
  }
}
