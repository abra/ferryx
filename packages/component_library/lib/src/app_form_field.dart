import 'package:flutter/material.dart';

import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_spacing.dart';

/// The shared label, action spacing and help text of fields and choices in a
/// form. Labels and help wrap; the input retains the available width.
class AppFormField extends StatelessWidget {
  const AppFormField({
    required this.label,
    required this.child,
    this.helpText,
    this.trailing,
    super.key,
  });

  final String label;
  final Widget child;
  final String? helpText;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: context.text.labelMedium),
      const SizedBox(height: AppSpacing.xs),
      trailing == null
          ? child
          : Row(
              children: [
                Expanded(child: child),
                SizedBox(width: context.metrics.toolbarSpacing),
                trailing!,
              ],
            ),
      if (helpText != null) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          helpText!,
          style: context.text.bodySmall?.copyWith(
            color: context.appColors.textMuted,
          ),
        ),
      ],
    ],
  );
}
