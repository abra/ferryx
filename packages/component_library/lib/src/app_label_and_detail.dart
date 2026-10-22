import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'app_middle_ellipsis.dart';
import 'theme/tokens/app_spacing.dart';

/// A name and a muted detail after it on one line (a command and its
/// section, a file and its folder): the label whole while it fits beside
/// the detail, the detail in what is left; when both are long the label
/// keeps three fifths. Each loses its middle, not its end, and draws the
/// ranges of [labelHighlights] and [detailHighlights] in its matched
/// style.
class AppLabelAndDetail extends StatelessWidget {
  const AppLabelAndDetail({
    required this.label,
    required this.labelStyle,
    required this.labelHighlights,
    required this.labelMatched,
    required this.detail,
    required this.detailStyle,
    required this.detailHighlights,
    required this.detailMatched,
    super.key,
  });

  final String label;
  final TextStyle labelStyle;
  final List<(int, int)> labelHighlights;
  final TextStyle labelMatched;
  final String? detail;
  final TextStyle detailStyle;
  final List<(int, int)> detailHighlights;
  final TextStyle detailMatched;

  static const _gap = AppSpacing.sm;

  @override
  Widget build(BuildContext context) {
    final labelText = AppMiddleEllipsis(
      label,
      style: labelStyle,
      highlights: labelHighlights,
      highlightStyle: labelMatched,
    );
    final detail = this.detail;
    if (detail == null || detail.isEmpty) return labelText;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        double widthOf(String text, TextStyle style) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: direction,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        final room = constraints.maxWidth;
        // Bold highlights are wider: measure the label in their weight.
        final natural =
            widthOf(
              label,
              labelHighlights.isEmpty ? labelStyle : labelMatched,
            ) +
            1;
        final wanted = widthOf(detail, detailStyle);
        final labelWidth = math.min(
          natural,
          math.max(room * 0.6, room - wanted - _gap),
        );
        return Row(
          children: [
            SizedBox(width: labelWidth, child: labelText),
            const SizedBox(width: _gap),
            Expanded(
              child: AppMiddleEllipsis(
                detail,
                style: detailStyle,
                highlights: detailHighlights,
                highlightStyle: detailMatched,
              ),
            ),
          ],
        );
      },
    );
  }
}
