import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';

/// The age ranges explained in the panel's existing status line.
class RecentEntriesLegend extends StatelessWidget {
  const RecentEntriesLegend({super.key});

  static double widthOf(BuildContext context, {bool withTitle = true}) {
    final l10n = context.l10n;
    final labels = [
      l10n.panelRecentHour,
      l10n.panelRecentThreeHours,
      l10n.panelRecentDay,
    ];
    final text = TextPainter(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          if (withTitle) TextSpan(text: l10n.panelRecentAdded),
          for (final label in labels) TextSpan(text: label),
        ],
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width =
        text.width +
        AppIconSize.xs * labels.length +
        AppSpacing.xs * labels.length +
        AppSpacing.sm * (labels.length - (withTitle ? 0 : 1));
    text.dispose();
    return width.ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final titleFits = widthOf(context) <= constraints.maxWidth;
        final labelsFit =
            titleFits ||
            widthOf(context, withTitle: false) <= constraints.maxWidth;
        final keys = [
          _AgeKey(
            color: colors.recentHour,
            label: l10n.panelRecentHour,
            help: l10n.panelRecentHourHelp,
          ),
          _AgeKey(
            color: colors.recentThreeHours,
            label: l10n.panelRecentThreeHours,
            help: l10n.panelRecentThreeHoursHelp,
          ),
          _AgeKey(
            color: colors.recentDay,
            label: l10n.panelRecentDay,
            help: l10n.panelRecentDayHelp,
          ),
        ];
        return Row(
          spacing: AppSpacing.sm,
          children: [
            if (titleFits) Text(l10n.panelRecentAdded),
            for (final key in keys)
              if (labelsFit) key else Flexible(child: key),
          ],
        );
      },
    );
  }
}

class _AgeKey extends StatelessWidget {
  const _AgeKey({required this.color, required this.label, required this.help});

  final Color color;
  final String label;
  final String help;

  @override
  Widget build(BuildContext context) => AppTooltip(
    message: help,
    child: Semantics(
      label: help,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: AppIconSize.xs,
              height: AppIconSize.xs,
              decoration: appEdgedBox(
                color: color,
                edge: context.appColors.recentBorder,
                radius: context.metrics.radius.chip,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
