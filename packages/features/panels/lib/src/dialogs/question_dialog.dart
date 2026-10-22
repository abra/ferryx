import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';

import '../path_text.dart';
import 'dialog_support.dart';
import 'simple_dialogs.dart';

/// An operation's question: a conflict with both sides, or an error, with
/// the answers it offers. "Apply to all" turns an answer into its …All
/// form. Return takes the default (Replace for a conflict, Retry for an
/// error, as Finder has it); Esc stops the operation.
Future<Answer?> showQuestionDialog(
  BuildContext context, {
  required OperationQuestion question,
}) => showWorkspaceDialog<Answer>(
  context,
  (context) => _QuestionDialog(question: question),
);

class _QuestionDialog extends StatefulWidget {
  const _QuestionDialog({required this.question});

  final OperationQuestion question;

  @override
  State<_QuestionDialog> createState() => _QuestionDialogState();
}

class _QuestionDialogState extends State<_QuestionDialog> {
  bool _all = false;

  static const _allOf = {
    Answer.overwrite: Answer.overwriteAll,
    Answer.skip: Answer.skipAll,
    Answer.keepBoth: Answer.keepBothAll,
    Answer.merge: Answer.mergeAll,
  };

  /// The answers shown as buttons: the single forms, with …All reached
  /// through the check box; Overwrite older stays its own button.
  List<Answer> get _buttons => [
    for (final answer in widget.question.answers)
      if (!_allOf.containsValue(answer)) answer,
  ];

  bool get _hasAll => widget.question.answers.any(_allOf.containsValue);

  /// Return's answer: Replace for a conflict, Retry for an error, else the
  /// last one offered.
  Answer? _defaultOf(List<Answer> answers) {
    if (answers.isEmpty) return null;
    for (final preferred in [Answer.overwrite, Answer.retry]) {
      if (answers.contains(preferred)) return preferred;
    }
    return answers.last;
  }

  void _answer(Answer answer) {
    final chosen = _all ? (_allOf[answer] ?? answer) : answer;
    Navigator.of(context).pop(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final question = widget.question;
    final conflict = question.kind == QuestionKind.conflict;
    final buttons = _buttons;
    final dismissive = buttons.contains(Answer.abort) ? Answer.abort : null;
    final rest = buttons.where((a) => a != dismissive).toList();
    final primary = _defaultOf(rest);
    // The dialog wraps its buttons, so no answer is ever cut.
    final others = rest.where((a) => a != primary).toList();
    final subject = PathText.baseName(
      question.existing?.path ?? question.source?.path ?? question.message,
    );
    return AppDialog(
      title: conflict ? l10n.conflictTitle : l10n.questionErrorTitle,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            conflict
                ? l10n.conflictMessage(subject)
                : l10n.questionErrorMessage(subject),
            style: context.text.bodyMedium,
          ),
          if (!conflict && question.message.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            // The core's own words on what went wrong.
            Text(
              question.message,
              style: context.text.bodySmall?.copyWith(
                color: context.appColors.textMuted,
              ),
            ),
          ],
          if (conflict) ...[
            dialogRowGap,
            if (question.source != null)
              _Side(label: l10n.conflictSourceLabel, side: question.source!),
            if (question.existing != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _Side(
                label: l10n.conflictExistingLabel,
                side: question.existing!,
              ),
            ],
          ],
          if (_hasAll) ...[
            dialogRowGap,
            DialogToggle(
              label: l10n.questionApplyToAll,
              value: _all,
              onChanged: (v) => setState(() => _all = v),
            ),
          ],
        ],
      ),
      actions: [
        if (dismissive != null)
          _AnswerButton(answer: dismissive, onPressed: _answer),
        for (final answer in others)
          _AnswerButton(answer: answer, onPressed: _answer),
        if (primary != null)
          _AnswerButton(answer: primary, onPressed: _answer, filled: true),
      ],
    );
  }
}

/// One answer as a push button; the default one filled.
class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.answer,
    required this.onPressed,
    this.filled = false,
  });

  final Answer answer;
  final ValueChanged<Answer> onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final label = Text(context.l10n.answerLabel(answer));
    return filled
        ? FilledButton(onPressed: () => onPressed(answer), child: label)
        : OutlinedButton(onPressed: () => onPressed(answer), child: label);
  }
}

/// One side of a conflict: its path, size and date on a quiet plate.
class _Side extends StatelessWidget {
  const _Side({required this.label, required this.side});

  final String label;
  final ConflictSide side;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(context.metrics.radius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.text.labelSmall?.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (side.path.isNotEmpty)
            AppMiddleEllipsis(
              side.path,
              style: context.mono.copyWith(
                fontSize: context.text.bodySmall?.fontSize,
              ),
            ),
          Text(
            describeSide(l10n, side),
            style: context.text.bodySmall?.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}
