import 'package:flutter/material.dart';

import 'app_colors_ext.dart';
import 'app_metrics.dart';
import 'app_terminal_colors.dart';

/// Convenience accessors so widgets read roles, not values.
///
/// ```dart
/// Text('Hello', style: context.text.bodyMedium);
/// Icon(AppIcons.search, color: context.appColors.textMuted);
/// SizedBox(height: context.metrics.controlHeight);
/// ```
extension BuildContextThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);

  ColorScheme get colors => theme.colorScheme;

  TextTheme get text => theme.textTheme;

  AppColorsExt get appColors => theme.extension<AppColorsExt>()!;

  /// Sizes, radii, type families and control behaviour of the platform
  /// style the theme was built for.
  AppMetrics get metrics => theme.extension<AppMetrics>()!;

  /// The integrated terminal's ANSI colours for the theme's brightness.
  AppTerminalColors get terminalColors => theme.extension<AppTerminalColors>()!;

  /// The platform's monospace face in the body colour.
  TextStyle get mono =>
      metrics.typeScale.mono.copyWith(color: colors.onSurface);

  bool get isDark => theme.brightness == Brightness.dark;

  bool get reduceMotion => MediaQuery.disableAnimationsOf(this);

  /// A motion token, or zero under reduced motion.
  Duration motion(Duration duration) => reduceMotion ? Duration.zero : duration;

  /// ⌘ on macOS, Ctrl elsewhere; for labels only.
  TargetPlatform get platform => theme.platform;
}
