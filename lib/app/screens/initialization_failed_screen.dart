import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';

/// Shown instead of the app when dependencies could not be created.
///
/// Deliberately independent of localizations and preferences: those may be
/// the very things that failed.
class InitializationFailedScreen extends StatelessWidget {
  const InitializationFailedScreen({
    required this.error,
    required this.stackTrace,
    required this.onRetry,
    super.key,
  });

  final Object error;
  final StackTrace stackTrace;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    home: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.dialogWidth),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(
                  builder: (context) => Text(
                    'Ferryx could not start',
                    style: context.text.headlineSmall,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Builder(
                  builder: (context) => SelectableText(
                    '$error',
                    style: context.text.bodySmall?.copyWith(
                      color: context.appColors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
