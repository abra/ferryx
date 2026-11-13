import 'package:material_ui/material_ui.dart';

import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_spacing.dart';

/// Small heading above a group: `Documents`, `References · 3`. In the
/// platform's small bold style and as written, never upper-cased: no
/// desktop sets section headings in capitals.
class AppSectionLabel extends StatelessWidget {
  const AppSectionLabel(
    this.text, {
    this.trailing,
    this.inset = true,
    super.key,
  });

  final String text;
  final Widget? trailing;

  /// Inset as the text of rows with a fill of their own (a list, a menu);
  /// false lines it up with content set flush to the column (setting
  /// rows, a chart).
  final bool inset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      inset ? AppSpacing.sm : 0,
      AppSpacing.md,
      inset ? AppSpacing.sm : 0,
      AppSpacing.xs,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: context.text.labelSmall?.copyWith(
              color: context.appColors.textMuted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ?trailing,
      ],
    ),
  );
}
