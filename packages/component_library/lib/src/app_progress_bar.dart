import 'package:flutter/material.dart';

import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_motion.dart';
import 'theme/tokens/app_radius.dart';

/// Thin progress bar; a null value indicates work with an unknown total.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    required this.value,
    this.height = 4,
    this.animate = true,
    super.key,
  });

  /// 0..1, or null when the total is unknown.
  final double? value;
  final double height;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      value: value == null ? null : '${(value!.clamp(0, 1) * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: SizedBox(
          height: height,
          child: value == null
              ? ExcludeSemantics(
                  // A static activity cue must not announce a false percentage.
                  child: LinearProgressIndicator(
                    value: !animate || MediaQuery.disableAnimationsOf(context)
                        ? 0.3
                        : null,
                    color: colors.accent,
                    backgroundColor: colors.surfaceSunken,
                  ),
                )
              : Stack(
                  children: [
                    Container(color: colors.surfaceSunken),
                    AnimatedFractionallySizedBox(
                      duration: context.motion(AppMotion.short),
                      widthFactor: value!.clamp(0, 1).toDouble(),
                      child: Container(color: colors.accent),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
