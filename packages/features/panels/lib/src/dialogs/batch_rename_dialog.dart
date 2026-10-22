import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operations_service/operations_service.dart';

import 'attributes_dialog.dart' show dialogBodyMaxHeight;
import 'dialog_support.dart';

/// Batch Rename (⌃M): the pattern, search and replace, case and counter
/// with a live preview; answers whether names were changed.
Future<bool> showBatchRenameDialog(
  BuildContext context, {
  required List<String> paths,
  required RenameService rename,
}) async {
  final applied = await showWorkspaceDialog<bool>(
    context,
    (context) => _BatchRenameDialog(paths: paths, rename: rename),
  );
  return applied ?? false;
}

/// How long typing is let settle before the preview is asked for.
const _previewDelay = Duration(milliseconds: 150);

class _BatchRenameDialog extends StatefulWidget {
  const _BatchRenameDialog({required this.paths, required this.rename});

  final List<String> paths;
  final RenameService rename;

  @override
  State<_BatchRenameDialog> createState() => _BatchRenameDialogState();
}

class _BatchRenameDialogState extends State<_BatchRenameDialog> {
  final _pattern = TextEditingController(text: '[N].[E]');
  final _search = TextEditingController();
  final _replace = TextEditingController();
  final _counterStart = TextEditingController(text: '1');
  final _counterStep = TextEditingController(text: '1');
  final _counterWidth = TextEditingController(text: '1');
  RenameOptions _options = const RenameOptions();
  List<RenameOutcome> _preview = const [];

  /// The core's refusal of the pattern or the search expression.
  FerryxException? _error;
  bool _helpShown = false;
  bool _applying = false;
  Timer? _debounce;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    for (final controller in [_pattern, _search, _replace]) {
      controller.addListener(_scheduleSearchPreview);
    }
    for (final controller in [_counterStart, _counterStep, _counterWidth]) {
      controller.addListener(_scheduleSearchPreview);
    }
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pattern.dispose();
    _search.dispose();
    _replace.dispose();
    _counterStart.dispose();
    _counterStep.dispose();
    _counterWidth.dispose();
    super.dispose();
  }

  RenameOptions get _current => _options.copyWith(
    pattern: _pattern.text,
    search: _search.text,
    replace: _replace.text,
    counterStart: int.tryParse(_counterStart.text.trim()) ?? 1,
    counterStep: int.tryParse(_counterStep.text.trim()) ?? 1,
    counterWidth: (int.tryParse(_counterWidth.text.trim()) ?? 1).clamp(1, 20),
  );

  void _scheduleSearchPreview() {
    _debounce?.cancel();
    _debounce = Timer(_previewDelay, () => unawaited(_refresh()));
  }

  void _update(RenameOptions Function(RenameOptions options) change) {
    setState(() => _options = change(_options));
    _scheduleSearchPreview();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    final options = _current;
    try {
      final preview = await widget.rename.preview(widget.paths, options);
      if (!mounted || request != _request) return;
      setState(() {
        _preview = preview;
        _error = null;
      });
    } on FerryxException catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _preview = const [];
        _error = error;
      });
    }
  }

  /// The core refuses an expression, not a pattern, only while one is
  /// looked for: the error goes under the search field then.
  bool get _errorInSearch =>
      _error != null && _options.searchRegex && _search.text.isNotEmpty;

  bool get _hasProblem => _preview.any((o) => o.problem != null);

  bool get _changes => _preview.any((o) => o.changes);

  bool get _canApply =>
      !_applying && _error == null && !_hasProblem && _changes;

  Future<void> _apply() async {
    if (!_canApply) return;
    setState(() => _applying = true);
    final l10n = context.l10n;
    try {
      final failures = await widget.rename.apply(_preview);
      if (!mounted) return;
      if (failures.isNotEmpty) {
        showAppNotice(context, l10n.renameFailed(failures.length));
      }
      Navigator.of(context).pop(failures.length < _preview.length);
    } on FerryxException catch (error) {
      if (!mounted) return;
      setState(() => _applying = false);
      showAppNotice(context, l10n.errorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final parts = [
      (NamePart.whole, l10n.partWhole),
      (NamePart.name, l10n.partName),
      (NamePart.extension, l10n.partExtension),
    ];
    final error = _error;
    final errorText = error == null ? null : l10n.errorMessage(error);
    return AppDialog(
      title: l10n.batchRenameTitle(widget.paths.length),
      width: AppSizes.panelDialogWidth,
      body: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: dialogBodyMaxHeight(context)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DialogField(
                label: l10n.renamePatternLabel,
                hint: l10n.renamePatternHint,
                controller: _pattern,
                autofocus: true,
                monospace: true,
                onSubmitted: (_) => _apply(),
              ),
              if (errorText != null && !_errorInSearch) _FieldError(errorText),
              const SizedBox(height: AppSpacing.xs),
              _HelpDisclosure(
                shown: _helpShown,
                onToggle: () => setState(() => _helpShown = !_helpShown),
              ),
              dialogRowGap,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DialogField(
                          label: l10n.renameSearchLabel,
                          controller: _search,
                          monospace: true,
                          onSubmitted: (_) => _apply(),
                        ),
                        if (errorText != null && _errorInSearch)
                          _FieldError(errorText),
                        const SizedBox(height: AppSpacing.sm),
                        DialogField(
                          label: l10n.renameReplaceLabel,
                          controller: _replace,
                          monospace: true,
                          onSubmitted: (_) => _apply(),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        DialogChoice<NamePart>(
                          label: l10n.renameSearchPartLabel,
                          value: _options.searchPart,
                          items: parts,
                          onChanged: (v) =>
                              _update((o) => o.copyWith(searchPart: v)),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        DialogToggle(
                          label: l10n.renameRegex,
                          value: _options.searchRegex,
                          onChanged: (v) =>
                              _update((o) => o.copyWith(searchRegex: v)),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        DialogToggle(
                          label: l10n.renameCaseSensitive,
                          value: _options.searchCaseSensitive,
                          onChanged: (v) => _update(
                            (o) => o.copyWith(searchCaseSensitive: v),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        DialogToggle(
                          label: l10n.renameOnce,
                          value: _options.searchOnce,
                          onChanged: (v) =>
                              _update((o) => o.copyWith(searchOnce: v)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DialogChoice<CaseTransform>(
                          label: l10n.renameCaseLabel,
                          value: _options.caseTransform,
                          items: [
                            (CaseTransform.unchanged, l10n.caseUnchanged),
                            (CaseTransform.lower, l10n.caseLower),
                            (CaseTransform.upper, l10n.caseUpper),
                            (CaseTransform.capitalize, l10n.caseCapitalize),
                          ],
                          onChanged: (v) =>
                              _update((o) => o.copyWith(caseTransform: v)),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        DialogChoice<NamePart>(
                          label: l10n.renameCasePartLabel,
                          value: _options.casePart,
                          items: parts,
                          onChanged: (v) =>
                              _update((o) => o.copyWith(casePart: v)),
                        ),
                        dialogRowGap,
                        Text(
                          l10n.renameCounterLabel,
                          style: context.text.labelMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          spacing: AppSpacing.sm,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _NumberField(
                                label: l10n.renameCounterStart,
                                controller: _counterStart,
                                onSubmitted: _apply,
                              ),
                            ),
                            Expanded(
                              child: _NumberField(
                                label: l10n.renameCounterStep,
                                controller: _counterStep,
                                onSubmitted: _apply,
                              ),
                            ),
                            Expanded(
                              child: _NumberField(
                                label: l10n.renameCounterWidth,
                                controller: _counterWidth,
                                onSubmitted: _apply,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              dialogRowGap,
              _PreviewTable(preview: _preview),
              if (!_changes && _error == null && !_hasProblem) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.renameNoChanges,
                  style: context.text.bodySmall?.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _canApply ? _apply : null,
          child: Text(l10n.actionRename),
        ),
      ],
    );
  }
}

/// What the core refused, under the field it refused.
class _FieldError extends StatelessWidget {
  const _FieldError(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xs),
    child: Text(
      text,
      style: context.text.bodySmall?.copyWith(
        color: context.appColors.danger,
      ),
    ),
  );
}

/// A counter's field: a dialog field that takes digits, in the
/// monospace face as the pattern is.
class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    required this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) => DialogField(
    label: label,
    controller: controller,
    monospace: true,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))],
    onSubmitted: (_) => onSubmitted(),
  );
}

/// The placeholders, shown on request under the pattern.
class _HelpDisclosure extends StatelessWidget {
  const _HelpDisclosure({required this.shown, required this.onToggle});

  final bool shown;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: AppButtonStyles.small(context),
            onPressed: onToggle,
            icon: Icon(
              shown ? AppIcons.chevronDown : AppIcons.chevronRight,
              size: AppIconSize.sm,
            ),
            label: Text(l10n.renamePlaceholdersHelp),
          ),
        ),
        if (shown)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              l10n.renamePlaceholdersText,
              style: context.text.bodySmall?.copyWith(color: colors.textMuted),
            ),
          ),
      ],
    );
  }
}

/// Old names against new ones; a problem in red beside the new name.
class _PreviewTable extends StatelessWidget {
  const _PreviewTable({required this.preview});

  final List<RenameOutcome> preview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final rowHeight = context.metrics.listRowHeight;
    return Container(
      decoration: BoxDecoration(
        border: AppBorder.fromBorderSide(BorderSide(color: colors.line)),
        borderRadius: BorderRadius.circular(context.metrics.radius.card),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              border: AppBorder(bottom: BorderSide(color: colors.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.renamePreviewOld,
                    style: context.text.labelMedium?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    l10n.renamePreviewNew,
                    style: context.text.labelMedium?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: AppSizes.pickerListMaxHeight,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemExtent: rowHeight,
              itemCount: preview.length,
              itemBuilder: (context, index) => _PreviewRow(
                key: ValueKey(preview[index].path),
                outcome: preview[index],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.outcome, super.key});

  final RenameOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final problem = switch (outcome.problem) {
      null => null,
      RenameProblem.empty => l10n.renameProblemEmpty,
      RenameProblem.invalid => l10n.renameProblemInvalid,
      RenameProblem.duplicate => l10n.renameProblemDuplicate,
    };
    final style = context.text.bodySmall!;
    final newStyle = style.copyWith(
      color: problem != null
          ? colors.danger
          : outcome.changes
          ? context.colors.onSurface
          : colors.textFaint,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              outcome.oldName,
              style: style.copyWith(color: colors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(AppIcons.forward, size: AppIconSize.xs, color: colors.textFaint),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              problem == null
                  ? outcome.newName
                  : l10n.joinedDetails(outcome.newName, problem),
              style: outcome.changes
                  ? newStyle.weight(FontWeight.w500)
                  : newStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
