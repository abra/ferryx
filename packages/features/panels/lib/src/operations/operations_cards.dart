import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';

import '../path_text.dart';

/// The operations under way, as cards floating over the panels' corner:
/// a title, a progress bar, the speed and the time left, pause and stop.
/// A finished one stays until dismissed when it had errors, else goes
/// after a moment.
class OperationsCards extends StatelessWidget {
  const OperationsCards({
    required this.operations,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onDismiss,
    required this.onAnswer,
    this.titles = const {},
    super.key,
  });

  /// Titles that say more than the operation's kind (an undo names its
  /// step), by operation id.
  final Map<int, String> titles;

  /// A card's width: room for a title with its destination and the
  /// buttons beside it.
  static const double cardWidth = AppSizes.operationCardWidth;

  /// Cards shown at once, the latest first; older ones wait their turn.
  static const int shownAtMost = 4;

  final List<OperationProgress> operations;
  final ValueChanged<int> onPause;
  final ValueChanged<int> onResume;
  final ValueChanged<int> onCancel;
  final ValueChanged<int> onDismiss;

  /// The card's question needs an answer: opens the dialog.
  final ValueChanged<OperationProgress> onAnswer;

  @override
  Widget build(BuildContext context) {
    if (operations.isEmpty) return const SizedBox.shrink();
    final shown = operations.reversed.take(shownAtMost).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: AppSpacing.sm,
      children: [
        for (final operation in shown)
          _OperationCard(
            key: ValueKey(operation.id),
            progress: operation,
            title: titles[operation.id],
            onPause: () => onPause(operation.id),
            onResume: () => onResume(operation.id),
            onCancel: () => onCancel(operation.id),
            onDismiss: () => onDismiss(operation.id),
            onAnswer: () => onAnswer(operation),
          ),
      ],
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({
    required this.progress,
    this.title,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onDismiss,
    required this.onAnswer,
    super.key,
  });

  final OperationProgress progress;

  /// The title instead of the kind's own, when there is one.
  final String? title;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;
  final VoidCallback onAnswer;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final finished = progress.state.isFinished;
    final waiting = progress.state == OpState.waiting;
    final paused = progress.state == OpState.paused;
    final failed =
        progress.state == OpState.failed ||
        progress.state == OpState.doneWithErrors;
    final destination = progress.destination;
    final title = this.title ?? l10n.operationTitle(progress);
    final detail = finished
        ? l10n.operationState(progress.state)
        : waiting
        ? l10n.opStateWaiting
        : [
            if (progress.bytesTotal > 0)
              l10n.opProgressBytes(
                l10n.fileSize(progress.bytesDone),
                l10n.fileSize(progress.bytesTotal),
              )
            else if (progress.itemsTotal > 0)
              l10n.opProgressItems(progress.itemsDone, progress.itemsTotal),
            if (progress.bytesPerSecond > 0 && !paused)
              l10n.opSpeed(l10n.fileSize(progress.bytesPerSecond)),
            if (progress.remaining != null && !paused)
              l10n.opRemaining(l10n.duration(progress.remaining!)),
            if (paused) l10n.opStatePaused,
          ].fold<String?>(
            null,
            (a, b) => a == null ? b : l10n.joinedDetails(a, b),
          );
    final firstError = progress.errors.firstOrNull;
    return PixelSnap(
      child: Container(
        width: OperationsCards.cardWidth,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        // The menus' plate, rounded as a card is.
        decoration: AppMenuPanel.plate(context).copyWith(
          borderRadius: BorderRadius.circular(context.metrics.radius.card),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  finished
                      ? (failed ? AppIcons.warning : AppIcons.checkCircle)
                      : waiting
                      ? AppIcons.info
                      : _iconOf(progress.kind),
                  size: AppIconSize.md,
                  color: failed ? colors.danger : colors.textMuted,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    destination != null && !finished
                        ? l10n.opTitleTo(title, PathText.baseName(destination))
                        : title,
                    style: context.text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (waiting)
                  HintTarget(
                    onActivate: onAnswer,
                    child: OutlinedButton(
                      style: AppButtonStyles.small(context),
                      onPressed: onAnswer,
                      child: Text(l10n.actionView),
                    ),
                  )
                else if (!finished) ...[
                  AppIconButton(
                    icon: paused ? AppIcons.play : AppIcons.pause,
                    tooltip: paused ? l10n.actionResume : l10n.actionPause,
                    onPressed: paused ? onResume : onPause,
                  ),
                  AppIconButton(
                    icon: AppIcons.cancel,
                    tooltip: l10n.actionStop,
                    onPressed: onCancel,
                  ),
                ] else
                  AppIconButton(
                    icon: AppIcons.close,
                    tooltip: l10n.actionClose,
                    onPressed: onDismiss,
                  ),
              ],
            ),
            if (!finished) ...[
              const SizedBox(height: AppSpacing.sm),
              AppProgressBar(value: waiting ? 0 : (progress.fraction ?? 0)),
            ],
            if (detail != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                detail,
                style: context.text.bodySmall?.copyWith(
                  color: colors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (!finished && progress.current.isNotEmpty)
              AppMiddleEllipsis(
                PathText.baseName(progress.current),
                style: context.text.bodySmall!.copyWith(
                  color: colors.textFaint,
                ),
              ),
            if (firstError != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.joinedDetails(
                  l10n.opErrorsCount(progress.errors.length),
                  l10n.opFirstError(
                    PathText.baseName(firstError.path),
                    firstError.message,
                  ),
                ),
                style: context.text.bodySmall?.copyWith(color: colors.danger),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _iconOf(OpKind kind) => switch (kind) {
    OpKind.copy => AppIcons.copy,
    OpKind.move => AppIcons.scissors,
    OpKind.delete || OpKind.trash => AppIcons.trash,
    OpKind.duplicate => AppIcons.documents,
    OpKind.compress => AppIcons.fileArchive,
    OpKind.extract => AppIcons.fileArchive,
    OpKind.calcSizes => AppIcons.calculator,
    OpKind.synchronize => AppIcons.synchronize,
    OpKind.compareContents => AppIcons.compareFolders,
    OpKind.undo => AppIcons.undo,
    OpKind.redo => AppIcons.redo,
  };
}
