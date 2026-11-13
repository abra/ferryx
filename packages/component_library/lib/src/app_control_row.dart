import 'package:material_ui/material_ui.dart';

import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_spacing.dart';

/// A row of a form or a settings group: the label at the start, the
/// control at the end at its own size. A long label wraps to a second
/// line; the control is never squeezed or dropped. ([AppLabelRow] is for
/// a label with secondary text after it, not for a control.) A [note]
/// under the label says what the choice does.
class AppControlRow extends StatelessWidget {
  const AppControlRow({
    required this.label,
    required this.control,
    this.note,
    super.key,
  });

  final String label;
  final Widget control;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: context.metrics.controlHeight),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: context.text.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (note != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    note,
                    style: context.text.bodySmall?.copyWith(
                      color: context.appColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          control,
        ],
      ),
    );
  }
}
