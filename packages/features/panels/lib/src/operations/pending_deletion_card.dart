import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shortcuts/shortcuts.dart';

import '../workspace/pending_deletions_controller.dart';

/// The animation is presentation only; the workspace owns the actual deadline.
class PendingDeletionCard extends StatefulWidget {
  const PendingDeletionCard({
    required this.deletion,
    required this.remaining,
    required this.onCancel,
    super.key,
  });

  final PendingDeletion deletion;
  final Duration remaining;
  final VoidCallback onCancel;

  @override
  State<PendingDeletionCard> createState() => _PendingDeletionCardState();
}

class _PendingDeletionCardState extends State<PendingDeletionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _countdown;

  @override
  void initState() {
    super.initState();
    _countdown = AnimationController(
      vsync: this,
      // Accessibility settings must not shorten a real grace period's display.
      animationBehavior: AnimationBehavior.preserve,
      value:
          (widget.remaining.inMicroseconds /
                  widget.deletion.delay.inMicroseconds)
              .clamp(0.0, 1.0),
    )..animateTo(0, duration: widget.remaining);
  }

  @override
  void dispose() {
    _countdown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final deletion = widget.deletion;
    final title = deletion.request.kind == OpKind.trash
        ? l10n.pendingTrashTitle(deletion.request.sources.length)
        : l10n.pendingDeleteTitle(deletion.request.sources.length);
    final escape = Chord.keyLabel(LogicalKeyboardKey.escape, context.platform);
    return PixelSnap(
      child: Container(
        width: AppSizes.operationCardWidth,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: AppMenuPanel.plate(
          context,
          radius: context.metrics.radius.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  AppIcons.trash,
                  size: AppIconSize.md,
                  color: colors.textMuted,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppTooltip(
                    message: deletion.location.display,
                    child: Text(
                      title,
                      style: context.text.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                HintTarget(
                  onActivate: widget.onCancel,
                  child: AppTooltip(
                    message: l10n.pendingDeleteCancelHint(escape),
                    child: OutlinedButton(
                      style: AppButtonStyles.small(context),
                      onPressed: widget.onCancel,
                      child: Text(l10n.actionCancel),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            AnimatedBuilder(
              animation: _countdown,
              builder: (context, _) {
                final seconds = (_countdown.value * deletion.delay.inSeconds)
                    .ceil()
                    .clamp(1, deletion.delay.inSeconds);
                final fraction = MediaQuery.disableAnimationsOf(context)
                    ? seconds / deletion.delay.inSeconds
                    : _countdown.value;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        l10n.joinedDetails(
                          l10n.pendingDeleteRemaining(seconds),
                          l10n.pendingDeleteNotStarted,
                        ),
                        style: context.text.bodySmall?.copyWith(
                          color: colors.textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ExcludeSemantics(
                      child: AppProgressBar(value: fraction, animate: false),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
