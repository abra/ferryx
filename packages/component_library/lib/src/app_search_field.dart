import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_icons.dart';
import 'theme/app_platform_style.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/hairlines.dart';
import 'theme/tokens/app_icon_size.dart';

/// The platform's search field: a text field with the magnifier before the
/// hint, shaped as the platform shapes search fields (rounded where a text
/// field is square on macOS 15, a capsule on macOS 26, a text field's
/// corners elsewhere: `context.metrics.radius.search`).
/// While there is text, a clear button at its end and Esc empty it, as an
/// NSSearchField does; Esc on an empty field goes on to whatever owns it.
/// [sidebar]: the field heads a sidebar's list, where macOS draws it as a
/// quiet fill with a fine edge instead of a white bezel.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    required this.hintText,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.sidebar = false,
    super.key,
  });

  final String hintText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool sidebar;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  TextEditingController? _own;

  TextEditingController get _controller =>
      widget.controller ?? (_own ??= TextEditingController());

  @override
  void didUpdateWidget(AppSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != null && _own != null) {
      _own!.dispose();
      _own = null;
    }
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  void _clear() {
    if (_controller.text.isEmpty) return;
    _controller.clear();
    widget.onChanged?.call('');
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _controller.text.isNotEmpty) {
      _clear();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final radius = metrics.radius;
    final colors = context.appColors;
    final theme = Theme.of(context).inputDecorationTheme;
    // An NSSearchField over a sidebar's vibrancy (measured on macOS 15):
    // the fill and edge of the sidebar's own greys, no lighter bezel; in
    // the dark its lower edge stays the lighter one.
    final quiet = widget.sidebar && metrics.style == AppPlatformStyle.macos;
    final dark = Theme.of(context).brightness == Brightness.dark;
    InputBorder? onSidebar(InputBorder? border) =>
        quiet && border is AppOutlineInputBorder
        ? AppOutlineInputBorder(
            borderSide: border.borderSide.copyWith(color: colors.line),
            borderRadius: border.borderRadius,
            gapPadding: border.gapPadding,
            halo: border.halo,
            shade: dark ? border.shade : null,
          )
        : border;
    // The theme's borders, rounded as a search field when the platform
    // rounds one otherwise than a text field.
    InputBorder? shaped(InputBorder? border) => onSidebar(
      radius.search != radius.field && border is OutlineInputBorder
          ? border.copyWith(borderRadius: BorderRadius.circular(radius.search))
          : border,
    );
    return Focus(
      onKeyEvent: _onKey,
      skipTraversal: true,
      canRequestFocus: false,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _controller,
        builder: (context, value, _) => TextField(
          controller: _controller,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          decoration: InputDecoration(
            hintText: widget.hintText,
            fillColor: quiet ? colors.hoverFill : null,
            prefixIcon: Icon(
              AppIcons.search,
              size: AppIconSize.md,
              color: colors.textFaint,
            ),
            suffixIcon: value.text.isEmpty
                ? null
                : _ClearButton(onTap: _clear, color: colors.textFaint),
            border: shaped(theme.border),
            enabledBorder: shaped(theme.enabledBorder),
            disabledBorder: shaped(theme.disabledBorder),
            focusedBorder: shaped(theme.focusedBorder),
            errorBorder: shaped(theme.errorBorder),
            focusedErrorBorder: shaped(theme.focusedErrorBorder),
          ),
          onChanged: widget.onChanged,
          onEditingComplete: () {},
          onSubmitted: widget.onSubmitted,
        ),
      ),
    );
  }
}

/// The cancel button of a search field: a filled circle with a cross,
/// which takes no focus of its own (the field keeps it).
class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.onTap, required this.color});

  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeFocus(
    child: Semantics(
      button: true,
      label: MaterialLocalizations.of(context).deleteButtonTooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Icon(AppIcons.cancel, size: AppIconSize.sm, color: color),
        ),
      ),
    ),
  );
}
