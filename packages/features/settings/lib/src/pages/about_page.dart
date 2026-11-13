import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// The app's name, version and a word about it.
class AboutPage extends StatelessWidget {
  const AboutPage({required this.version, super.key});

  final String version;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    return ListView(
      padding: EdgeInsets.all(context.metrics.contentMargin),
      children: [
        Text(l10n.appTitle, style: context.text.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.aboutVersion(version),
          style: context.text.bodyMedium?.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.aboutDescription, style: context.text.bodyMedium),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.aboutLicense,
          style: context.text.bodyMedium?.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }
}
