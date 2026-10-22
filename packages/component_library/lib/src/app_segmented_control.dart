import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_divider.dart';
import 'focus_ring.dart';
import 'hints/hint_registry.dart';
import 'theme/app_platform_style.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_radius.dart';
import 'theme/tokens/app_spacing.dart';
import 'theme/hairlines.dart';

/// Compact choice between a few options; ←/→ move the selection.
///
/// Drawn as the platform's own: an NSSegmentedControl (a sunken track with
/// a raised white segment), the Fluent segmented control (a raised segment
/// with an accent pill under its label), a libadwaita toggle group.
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    required this.options,
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// Value and label pairs, in display order.
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = context.metrics;
    final style = metrics.style;
    final index = options.indexWhere((o) => o.$1 == value);
    final outer = metrics.radius.control;
    final pad = style == AppPlatformStyle.gnome ? 3.0 : 2.0;
    // Fluent's track has a 1 px edge; the whole control keeps the height
    // of the platform's buttons beside it.
    final edge = style == AppPlatformStyle.windows ? 1.0 : 0.0;
    // Taller with the text by what the label's line grows, as a field is,
    // so the two keep one height at every text size.
    final label = context.text.bodyMedium!;
    final line = label.fontSize! * label.height!;
    final grown =
        MediaQuery.textScalerOf(context).scale(label.fontSize!) * label.height!;
    final segmentHeight =
        metrics.controlHeight - 2 * (pad + edge) + math.max(0, grown - line);
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.basic,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowLeft): _StepIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowRight): _StepIntent(1),
      },
      actions: {
        _StepIntent: CallbackAction<_StepIntent>(
          onInvoke: (intent) {
            final next = (index + intent.delta).clamp(0, options.length - 1);
            if (next != index) onChanged(options[next].$1);
            return null;
          },
        ),
      },
      child: Builder(
        builder: (context) => FocusRing(
          radius: outer,
          child: Container(
            padding: EdgeInsets.all(pad),
            decoration: BoxDecoration(
              color: style == AppPlatformStyle.windows
                  ? colors.surfaceSunken
                  : colors.selectionFill,
              borderRadius: BorderRadius.circular(outer),
              border: style == AppPlatformStyle.windows
                  ? AppBorder.all(color: colors.line)
                  : null,
            ),
            // Each segment takes its label's width; short of room they
            // share it and the labels end in an ellipsis, never overflow.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < options.length; i++) ...[
                  // NSSegmentedControl parts two plain segments with a
                  // hairline, none beside the raised one.
                  if (i > 0 &&
                      style != AppPlatformStyle.windows &&
                      options[i].$1 != value &&
                      options[i - 1].$1 != value)
                    SizedBox(
                      height: segmentHeight - 2 * AppSpacing.xs,
                      child: AppRule(axis: Axis.vertical, color: colors.line),
                    ),
                  Flexible(
                    child: _Segment(
                      label: options[i].$2,
                      selected: options[i].$1 == value,
                      height: segmentHeight,
                      radius: (outer - pad).clamp(2, outer).toDouble(),
                      onTap: () => onChanged(options[i].$1),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Height of Fluent's selection pill and the gap above it.
const double _pillRoom = 4;

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.height,
    required this.radius,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final double height;
  final double radius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final windows = context.metrics.style == AppPlatformStyle.windows;
    final raised = selected
        ? BoxDecoration(
            color: context.isDark && !windows
                ? colors.controlFill
                : context.colors.surface,
            borderRadius: BorderRadius.circular(radius),
            border: windows ? AppBorder.all(color: colors.line) : null,
            boxShadow: windows
                ? null
                : const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 2,
                      offset: Offset(0, 0.5),
                    ),
                  ],
          )
        : null;
    return Semantics(
      button: true,
      selected: selected,
      // Each segment its own ⌘J label: the label picks it.
      child: HintTarget(
        onActivate: onTap,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: raised,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Padding(
                  // Fluent's pill sits under the label: every label moves up
                  // by the pill's room, so none shifts when the choice does.
                  padding: EdgeInsets.only(bottom: windows ? _pillRoom : 0),
                  child: Text(
                    label,
                    // The platforms set every segment's label in the
                    // label colour; the raised segment tells the choice.
                    style: context.text.bodyMedium?.copyWith(
                      color: context.colors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (selected && windows)
                  Positioned(
                    bottom: 1,
                    child: Container(
                      width: 16,
                      height: 3,
                      decoration: BoxDecoration(
                        color: colors.accent,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepIntent extends Intent {
  const _StepIntent(this.delta);

  final int delta;
}
