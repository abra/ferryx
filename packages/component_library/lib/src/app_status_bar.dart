import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'theme/extensions/build_context_ext.dart';
import 'theme/hairlines.dart';
import 'theme/tokens/app_spacing.dart';

/// A single footer row shared by neighboring panes and workspace hints.
/// The border is inside the height, so their content edges meet exactly.
class AppStatusBar extends StatelessWidget {
  const AppStatusBar({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  static double heightOf(BuildContext context) {
    final line = context.text.bodySmall!;
    final textHeight =
        MediaQuery.textScalerOf(context).scale(line.fontSize!) * line.height!;
    return (math.max(
              context.metrics.iconButtonSize.height,
              textHeight + AppSpacing.sm,
            ) +
            AppSpacing.xs)
        .ceilToDouble();
  }

  @override
  Widget build(BuildContext context) => Container(
    height: heightOf(context),
    padding:
        padding ??
        EdgeInsets.symmetric(
          horizontal: context.metrics.tableRowInset + AppSpacing.sm,
        ),
    decoration: BoxDecoration(
      color: context.appColors.windowChrome,
      border: AppBorder(top: BorderSide(color: context.appColors.line)),
    ),
    child: DefaultTextStyle(
      style: context.text.bodySmall!.copyWith(
        color: context.appColors.textMuted,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      child: Align(alignment: AlignmentDirectional.centerStart, child: child),
    ),
  );
}
