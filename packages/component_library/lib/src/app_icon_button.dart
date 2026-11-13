import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoButton;
import 'package:material_ui/material_ui.dart';

import 'app_tooltip.dart';
import 'focus_ring.dart';
import 'hints/hint_registry.dart';
import 'theme/app_platform_style.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_icon_size.dart';

/// A borderless icon button of the platform's toolbar size, with a tooltip
/// that also shows its shortcut. A rounded fill marks hover, press and
/// [selected] (a toggled panel), as toolbar buttons do on all three
/// desktops.
class AppIconButton extends StatefulWidget {
  const AppIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.shortcut,
    this.selected = false,
    this.focusNode,
    this.glyph,
    super.key,
  });

  final IconData icon;

  /// Drawn in place of [icon], at its size: a state the icon font has no
  /// glyph for (a filled star).
  final Widget? glyph;
  final String tooltip;
  final VoidCallback? onPressed;
  final String? shortcut;
  final bool selected;
  final FocusNode? focusNode;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = context.metrics;
    final enabled = widget.onPressed != null;
    final fill = !enabled
        ? null
        : _pressed
        ? colors.pressedFill
        : widget.selected
        ? colors.selectionFill
        : _hovered
        ? colors.hoverFill
        : null;
    final radius = BorderRadius.circular(metrics.radius.control);
    final ink = !enabled
        ? colors.textFaint
        : widget.selected
        ? context.colors.onSurface
        : colors.textMuted;
    final face = Builder(
      builder: (context) => FocusRing(
        radius: metrics.radius.control,
        child: Container(
          width: metrics.iconButtonSize.width,
          height: metrics.iconButtonSize.height,
          decoration: BoxDecoration(color: fill, borderRadius: radius),
          child:
              widget.glyph ??
              Icon(widget.icon, size: AppIconSize.md, color: ink),
        ),
      ),
    );
    return AppTooltip(
      message: widget.tooltip,
      shortcut: widget.shortcut,
      child: MergeSemantics(
        child: Semantics(
          button: true,
          enabled: enabled,
          toggled: widget.selected ? true : null,
          label: widget.tooltip,
          child: HintTarget(
            onActivate: widget.onPressed,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() {
                _hovered = false;
                _pressed = false;
              }),
              child: Listener(
                onPointerDown: enabled
                    ? (_) => setState(() => _pressed = true)
                    : null,
                onPointerUp: (_) => setState(() => _pressed = false),
                onPointerCancel: (_) => setState(() => _pressed = false),
                child: metrics.style == AppPlatformStyle.macos
                    ? CupertinoButton(
                        focusNode: widget.focusNode,
                        onPressed: widget.onPressed,
                        padding: EdgeInsets.zero,
                        minimumSize: metrics.iconButtonSize,
                        borderRadius: radius,
                        mouseCursor: SystemMouseCursors.basic,
                        foregroundColor: ink,
                        // Desktop feedback comes from the shared fill and ring.
                        focusColor: Colors.transparent,
                        pressedOpacity: 1,
                        child: face,
                      )
                    : InkWell(
                        focusNode: widget.focusNode,
                        onTap: widget.onPressed,
                        borderRadius: radius,
                        mouseCursor: SystemMouseCursors.basic,
                        hoverColor: Colors.transparent,
                        focusColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        child: face,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
