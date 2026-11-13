import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoTextField;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'theme/extensions/build_context_ext.dart';
import 'theme/app_platform_style.dart';
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
    if (context.metrics.style == AppPlatformStyle.macos) {
      return _MacTextField(field: this, style: resolved, decoration: input);
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

/// Cupertino owns editing and desktop selection; the existing decorator keeps
/// the macOS bezel, validation, adornments and control metrics consistent.
class _MacTextField extends StatefulWidget {
  const _MacTextField({
    required this.field,
    required this.style,
    required this.decoration,
  });

  final AppTextField field;
  final TextStyle style;
  final InputDecoration decoration;

  @override
  State<_MacTextField> createState() => _MacTextFieldState();
}

class _MacTextFieldState extends State<_MacTextField> {
  TextEditingController? _ownController;
  FocusNode? _ownFocus;

  TextEditingController get _controller =>
      widget.field.controller ?? (_ownController ??= TextEditingController());
  FocusNode get _focus =>
      widget.field.focusNode ??
      (_ownFocus ??= FocusNode(debugLabel: 'macOS field'));

  @override
  void didUpdateWidget(_MacTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.field.controller != widget.field.controller) {
      if (widget.field.controller == null) {
        _ownController = TextEditingController.fromValue(
          oldWidget.field.controller?.value,
        );
      } else {
        _ownController?.dispose();
        _ownController = null;
      }
    }
  }

  @override
  void dispose() {
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, _focus]),
      builder: (context, child) => MouseRegion(
        cursor: field.enabled
            ? SystemMouseCursors.text
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          // The editor owns accessibility; the bezel just extends its hit area.
          excludeFromSemantics: true,
          onTap: field.enabled ? _focus.requestFocus : null,
          child: InputDecorator(
            decoration: widget.decoration.copyWith(
              enabled: field.enabled,
              hintMaxLines: widget.decoration.hintMaxLines ?? field.maxLines,
            ),
            baseStyle: widget.style,
            isEmpty: _controller.text.isEmpty,
            isFocused: _focus.hasFocus,
            textAlign: field.textAlign,
            child: child,
          ),
        ),
      ),
      child: CupertinoTextField(
        controller: _controller,
        focusNode: _focus,
        autofocus: field.autofocus,
        enabled: field.enabled,
        readOnly: field.readOnly,
        obscureText: field.obscureText,
        selectAllOnFocus: field.selectAllOnFocus,
        autocorrect: field.autocorrect,
        enableSuggestions:
            field.enableSuggestions ?? !(field.monospace || field.obscureText),
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        keyboardType: field.keyboardType,
        inputFormatters: field.inputFormatters,
        textInputAction: field.textInputAction,
        textAlign: field.textAlign,
        minLines: field.minLines,
        maxLines: field.maxLines,
        style: widget.style,
        strutStyle: field.strutStyle,
        // An empty decoration also suppresses Cupertino's disabled background.
        decoration: const BoxDecoration(),
        padding: EdgeInsets.zero,
        cursorColor: context.theme.textSelectionTheme.cursorColor,
        onChanged: field.onChanged,
        onEditingComplete: field.onEditingComplete ?? AppTextField._keepFocus,
        onSubmitted: field.onSubmitted,
      ),
    );
  }
}
