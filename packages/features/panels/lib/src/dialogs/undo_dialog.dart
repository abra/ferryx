import 'dart:math' as math;

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:material_ui/material_ui.dart';

import 'dialog_support.dart';

/// What the user chose about a step that cannot be walked back as it was.
enum UndoChoice {
  /// Undo (or redo) what can be.
  proceed,

  /// Drop the step: none of it can be done any more.
  forget,
}

/// Tells what of a step cannot be undone ([redo]: redone) as it was, by
/// path and reason, before anything moves: the rest goes ahead on
/// [UndoChoice.proceed]; a step with nothing left to do can only be
/// forgotten. `null` when dismissed.
Future<UndoChoice?> showUndoDialog(
  BuildContext context, {
  required UndoCheck check,
  required bool redo,
}) => showWorkspaceDialog<UndoChoice>(
  context,
  (context) => UndoDialog(check: check, redo: redo),
);

class UndoDialog extends StatelessWidget {
  const UndoDialog({required this.check, required this.redo, super.key});

  final UndoCheck check;
  final bool redo;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final step = l10n.stepLabel(check.step);
    final blocked = check.issues.any((i) => i.blocks);
    final String message;
    if (check.nothingDoable) {
      message = redo ? l10n.redoNone : l10n.undoNone;
    } else if (blocked) {
      message = redo
          ? l10n.redoPartly(check.doable, check.total)
          : l10n.undoPartly(check.doable, check.total);
    } else {
      message = redo ? l10n.redoWarnings : l10n.undoWarnings;
    }
    final more = check.issuesTotal - check.issues.length;
    return AppDialog(
      title: redo ? l10n.redoDialogTitle(step) : l10n.undoDialogTitle(step),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message),
          const SizedBox(height: AppSpacing.sm),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.min(
                AppSizes.pickerListMaxHeight,
                MediaQuery.sizeOf(context).height / 3,
              ),
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final issue in check.issues)
                  _IssueRow(key: ValueKey(issue), issue: issue),
                if (more > 0) _More(count: more),
              ],
            ),
          ),
        ],
      ),
      actions: check.nothingDoable
          ? [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(UndoChoice.forget),
                child: Text(l10n.undoForget),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.actionOk),
              ),
            ]
          : [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.actionCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(UndoChoice.proceed),
                child: Text(redo ? l10n.redoAction : l10n.undoAction),
              ),
            ],
    );
  }
}

/// One change that cannot be done as it was: the item's path, shortened
/// in the middle, and why; an error mark when it is left out, a note when
/// it is only a warning.
class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue, super.key});

  final UndoIssue issue;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final small = context.text.bodySmall!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            issue.blocks ? AppIcons.error : AppIcons.info,
            size: AppIconSize.sm,
            color: issue.blocks ? colors.danger : colors.textMuted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppMiddleEllipsis(
                  issue.path,
                  style: small.copyWith(color: context.colors.onSurface),
                ),
                Text(
                  context.l10n.undoIssueLabel(issue.kind),
                  style: small.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _More extends StatelessWidget {
  const _More({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xs),
    child: Text(
      context.l10n.undoMoreIssues(count),
      style: context.text.bodySmall?.copyWith(
        color: context.appColors.textMuted,
      ),
    ),
  );
}
