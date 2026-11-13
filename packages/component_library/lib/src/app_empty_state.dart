import 'package:material_ui/material_ui.dart';

import 'app_icons.dart';

import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_icon_size.dart';
import 'theme/tokens/app_spacing.dart';

/// Centered message for empty lists and finished queues.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.title,
    this.message,
    this.icon,
    this.action,
    super.key,
  });

  final String title;
  final String? message;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: AppIconSize.xl, color: colors.textFaint),
                const SizedBox(height: AppSpacing.md),
              ],
              Text(
                title,
                style: context.text.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message!,
                  style: context.text.bodySmall?.copyWith(
                    color: colors.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: AppSpacing.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Error variant with a retry action.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    required this.title,
    this.details,
    this.onRetry,
    this.retryLabel,
    super.key,
  });

  final String title;
  final String? details;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) => AppEmptyState(
    icon: AppIcons.error,
    title: title,
    message: details,
    action: onRetry == null
        ? null
        : OutlinedButton(
            onPressed: onRetry,
            child: Text(retryLabel ?? 'Retry'),
          ),
  );
}
