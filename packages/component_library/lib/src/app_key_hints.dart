import 'package:flutter/material.dart';

import 'app_key_cap.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_spacing.dart';

/// One entry of [AppKeyHints]: the keys and what they do.
@immutable
class AppKeyHint {
  const AppKeyHint(this.keys, this.label);

  /// Key labels, each drawn as its own cap (`['←', '→']`); build them with
  /// `Chord.keyLabel` so they read right on every desktop.
  final List<String> keys;
  final String label;
}

/// The keys that work right now, as a strip of caps and words that wraps:
/// `← → width   ⇧ step 64   ↩ done   esc cancel`. Shown where a mode takes
/// keys the rest of the app does not (resizing a panel, the PDF area).
class AppKeyHints extends StatelessWidget {
  const AppKeyHints(this.hints, {super.key});

  final List<AppKeyHint> hints;

  @override
  Widget build(BuildContext context) {
    final style = context.text.bodySmall?.copyWith(
      color: context.appColors.textMuted,
    );
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final hint in hints)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final key in hint.keys) ...[
                AppKeyCap(key),
                const SizedBox(width: AppSpacing.xxs),
              ],
              const SizedBox(width: AppSpacing.xxs),
              Text(hint.label, style: style),
            ],
          ),
      ],
    );
  }
}
