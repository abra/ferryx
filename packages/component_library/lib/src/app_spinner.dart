import 'package:flutter/material.dart';

import 'theme/app_platform_style.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_icon_size.dart';

/// Work under way with no known end: the platform's small spinner, the
/// size of an icon, grey on macOS (NSProgressIndicator's spinning style),
/// in the accent elsewhere (ProgressRing, a GTK spinner).
class AppSpinner extends StatelessWidget {
  const AppSpinner({this.size = AppIconSize.md, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CircularProgressIndicator(
      strokeWidth: size / 8,
      color: context.metrics.style == AppPlatformStyle.macos
          ? context.appColors.textMuted
          : context.appColors.accent,
    ),
  );
}
