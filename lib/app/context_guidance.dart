import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/widgets.dart';

/// Keeps shared control guidance in the application's current language.
class ContextGuidance extends StatelessWidget {
  const ContextGuidance({required this.child, this.enabled = true, super.key});

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppGuidanceScope(
      enabled: enabled,
      labels: AppGuidanceLabels(
        navigate: l10n.hintNavigate,
        choose: l10n.hintChoose,
        dismiss: l10n.actionClose,
        clear: l10n.actionClear,
        nextControl: l10n.hintNextControl,
        previousControl: l10n.hintPreviousControl,
        toggle: l10n.hintToggle,
        adjust: l10n.hintAdjust,
        activate: l10n.hintActivate,
      ),
      child: child,
    );
  }
}
