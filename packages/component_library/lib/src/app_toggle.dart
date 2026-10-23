import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'focus_ring.dart';
import 'theme/app_platform_style.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_motion.dart';
import 'theme/tokens/app_radius.dart';
import 'theme/hairlines.dart';
import 'pixel_snap.dart';

/// The platform's on/off switch: AppKit's NSSwitch at the regular size (a
/// pill for a knob from macOS 26), Fluent's ToggleSwitch (an outlined
/// track with a dark knob when off), libadwaita's switch. Space and Enter
/// flip it.
///
/// The size is the platform's whatever the text size: a switch holds no
/// text, as AppKit's keeps its size in a larger font.
class AppToggle extends StatelessWidget {
  const AppToggle({required this.value, required this.onChanged, super.key});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = context.metrics;
    final enabled = onChanged != null;
    final windows = metrics.style == AppPlatformStyle.windows;
    final size = metrics.toggleSize;
    // Fluent's knob is smaller while off and grows when on; macOS 26's is
    // a pill, wider than tall.
    final shrink = windows && !value ? 2 : 0;
    final knob = metrics.toggleKnob - shrink;
    final knobWidth = metrics.toggleKnobWidth - shrink;
    final inset = (size.height - knob) / 2;
    final Color track;
    final Color? outline;
    final Color knobColor;
    // Through macOS 15 AppKit greys the knob in the dark and deepens the
    // track; macOS 26 draws both as the accent and white, as the other
    // desktops do.
    final tahoe = metrics.generation == MacGeneration.tahoe;
    final knobFill = tahoe ? colors.onAccent : colors.switchKnob;
    if (value) {
      track = tahoe ? colors.accent : colors.switchTrack;
      outline = null;
      knobColor = knobFill;
    } else if (windows) {
      track = Colors.transparent;
      outline = colors.textMuted;
      knobColor = colors.textMuted;
    } else {
      // AppKit and libadwaita sink the off track a step below a control.
      track = colors.pressedFill;
      outline = metrics.style == AppPlatformStyle.macos
          ? colors.controlBorder
          : null;
      knobColor = knobFill;
    }
    final raised = !windows;
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: FocusableActionDetector(
        enabled: enabled,
        // Space flips a switch. On macOS Return belongs to the window's
        // default button, so the switch answers no ActivateIntent there
        // (the app maps Return to one); elsewhere Return flips it too.
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.space): _FlipIntent(),
        },
        actions: {
          _FlipIntent: CallbackAction<_FlipIntent>(
            onInvoke: (_) {
              onChanged?.call(!value);
              return null;
            },
          ),
          if (metrics.style != AppPlatformStyle.macos)
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                onChanged?.call(!value);
                return null;
              },
            ),
        },
        mouseCursor: enabled ? SystemMouseCursors.basic : MouseCursor.defer,
        child: Builder(
          builder: (context) => GestureDetector(
            onTap: enabled ? () => onChanged!(!value) : null,
            child: FocusRing(
              radius: AppRadius.full,
              child: PixelSnap(
                child: Opacity(
                  opacity: enabled ? 1 : 0.5,
                  child: AnimatedContainer(
                    duration: context.motion(AppMotion.quick),
                    width: size.width,
                    height: size.height,
                    padding: EdgeInsets.symmetric(horizontal: inset),
                    decoration: appEdgedBox(
                      color: track,
                      edge: outline,
                      radius: AppRadius.full,
                    ),
                    child: AnimatedAlign(
                      duration: context.motion(AppMotion.quick),
                      curve: Curves.easeOut,
                      alignment: value
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: context.motion(AppMotion.quick),
                        width: knobWidth,
                        height: knob,
                        decoration: BoxDecoration(
                          color: knobColor,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          boxShadow: raised
                              ? const [
                                  BoxShadow(
                                    color: Color(0x40000000),
                                    blurRadius: 2,
                                    offset: Offset(0, 1),
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlipIntent extends Intent {
  const _FlipIntent();
}
