import 'package:flutter/material.dart';

import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_motion.dart';
import 'theme/tokens/app_radius.dart';

/// Thin determinate bar (review progress, retention).
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({required this.value, this.height = 4, super.key});

  /// 0..1.
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      value: '${(value.clamp(0, 1) * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Container(color: colors.surfaceSunken),
              AnimatedFractionallySizedBox(
                duration: context.motion(AppMotion.short),
                widthFactor: value.clamp(0, 1).toDouble(),
                child: Container(color: colors.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
