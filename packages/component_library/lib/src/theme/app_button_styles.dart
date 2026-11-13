import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'extensions/build_context_ext.dart';

/// Button sizes besides the theme's own, the platform's control height.
abstract final class AppButtonStyles {
  /// Room above and below a button's label at the default size: with the
  /// label's line it makes the platform's control height, and it stays
  /// when the line grows with the text size, as a field's does. A button
  /// that sets its own padding keeps this above and below.
  static double labelRoom(BuildContext context) => _room(
    context,
    context.metrics.controlHeight,
  );

  /// The platform's small control height, for an action on a row of a
  /// list; the label's room grows with the text size as at the default.
  static ButtonStyle small(BuildContext context) {
    final height = context.metrics.controlHeightSmall;
    return ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, height)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: _horizontal(context),
          vertical: _room(context, height),
        ),
      ),
    );
  }

  /// A button in a top bar, beside its icon buttons: the platform's control
  /// height at text scale 1, and with a larger text only as tall as its
  /// label, since the bar keeps its height.
  static ButtonStyle bar(BuildContext context) => ButtonStyle(
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: _horizontal(context)),
    ),
  );

  static double _horizontal(BuildContext context) {
    final themed = Theme.of(
      context,
    ).outlinedButtonTheme.style?.padding?.resolve(const {});
    return (themed?.horizontal ?? 0) / 2;
  }

  static double _room(BuildContext context, double height) {
    final label = context.text.labelLarge!;
    return math.max(0, (height - label.fontSize! * label.height!) / 2);
  }
}
