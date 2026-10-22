import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_icons.dart';
import 'focus_ring.dart';
import 'hints/hint_registry.dart';
import 'theme/app_platform_style.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/hairlines.dart';
import 'theme/tokens/app_icon_size.dart';
import 'theme/tokens/app_spacing.dart';

/// The platform's check box with its label: an option of a dialog or a
/// form that takes effect with the dialog's button (a switch is for a
/// setting that acts at once). The label is part of the target, Space
/// flips it, the ring shows keyboard focus, ⌘J labels it.
class AppCheckbox extends StatefulWidget {
  const AppCheckbox({
    required this.value,
    required this.onChanged,
    this.label,
    this.mixed = false,
    super.key,
  });

  final bool value;

  /// `null` disables the box.
  final ValueChanged<bool>? onChanged;
  final String? label;

  /// On for some of several items and off for the rest: a dash in the
  /// box, as NSControl.StateValue.mixed draws it; a press turns it on.
  final bool mixed;

  @override
  State<AppCheckbox> createState() => _AppCheckboxState();
}

class _AppCheckboxState extends State<AppCheckbox> {
  bool _focused = false;
  bool _pressed = false;

  bool get _enabled => widget.onChanged != null;

  void _flip() => widget.onChanged?.call(widget.mixed ? true : !widget.value);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = context.metrics;
    final style = metrics.style;
    // NSButton's check box is 14 pt with soft corners; Fluent's 20 with a
    // 4 pt radius; a GtkCheckButton 14 with 4.
    final (box, radius) = switch (style) {
      AppPlatformStyle.macos => (14.0, 3.5),
      AppPlatformStyle.windows => (20.0, 4.0),
      AppPlatformStyle.gnome => (14.0, 4.0),
    };
    final on = widget.value || widget.mixed;
    final fill = !_enabled
        ? (on ? colors.selectionMuted : colors.surfaceSunken)
        : on
        ? (_pressed ? colors.selectionAccent : colors.accent)
        : _pressed
        ? colors.pressedFill
        : colors.controlFill;
    final edge = !on && _enabled ? colors.controlBorder : null;
    final ink = !_enabled
        ? colors.textFaint
        : on
        ? colors.onAccent
        : context.colors.onSurface;
    final label = widget.label;
    return Semantics(
      checked: widget.value,
      mixed: widget.mixed,
      enabled: _enabled,
      label: label,
      child: FocusableActionDetector(
        enabled: _enabled,
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        // Space flips the box. On macOS Return belongs to the window's
        // default button, so the box answers no ActivateIntent there (the
        // app maps Return to one); elsewhere Return flips it too.
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.space): _FlipIntent(),
        },
        actions: {
          _FlipIntent: CallbackAction<_FlipIntent>(
            onInvoke: (_) {
              _flip();
              return null;
            },
          ),
          if (style != AppPlatformStyle.macos)
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _flip();
                return null;
              },
            ),
        },
        mouseCursor: SystemMouseCursors.basic,
        child: HintTarget(
          onActivate: _enabled ? _flip : null,
          child: Listener(
            onPointerDown: _enabled
                ? (_) => setState(() => _pressed = true)
                : null,
            onPointerUp: (_) => setState(() => _pressed = false),
            onPointerCancel: (_) => setState(() => _pressed = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _enabled ? _flip : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FocusRing(
                    focused: _focused,
                    radius: radius,
                    child: Container(
                      width: box,
                      height: box,
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(radius),
                        border: edge == null
                            ? null
                            : AppBorder.all(color: edge),
                      ),
                      child: on
                          ? Icon(
                              widget.mixed ? AppIcons.minus : AppIcons.check,
                              size: box - AppSpacing.xs,
                              color: ink,
                            )
                          : null,
                    ),
                  ),
                  if (label != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        label,
                        style: context.text.bodyMedium?.copyWith(
                          color: _enabled
                              ? context.colors.onSurface
                              : colors.textFaint,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The size of a check box's glyph column, for aligning text beside a
/// row of boxes.
double checkboxExtent(BuildContext context) =>
    context.metrics.style == AppPlatformStyle.windows
    ? AppIconSize.lg
    : AppIconSize.sm;

class _FlipIntent extends Intent {
  const _FlipIntent();
}
