import 'dart:async';
import 'dart:math' as math;

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operations_service/operations_service.dart';
import 'package:shortcuts/shortcuts.dart';

import 'attributes_dialog.dart' show dialogBodyMaxHeight;
import 'dialog_support.dart';
import 'names_check.dart';

/// Rename in an Editor (⌃⇧M): the names of [items] as text, one per line,
/// to edit with everything a text field does (select across lines,
/// paste a column of names); beside each line its name now and what is
/// wrong with the new one. [existing] are the folder's other names. The
/// renames go to the core in one batch (swaps go through temporary
/// names there); answers whether any was made.
Future<bool> showNamesEditor(
  BuildContext context, {
  required List<FileEntry> items,
  required Set<String> existing,
  required RenameService rename,
}) async {
  final applied = await showWorkspaceDialog<bool>(
    context,
    (context) =>
        NamesEditorDialog(items: items, existing: existing, rename: rename),
  );
  return applied ?? false;
}

class NamesEditorDialog extends StatefulWidget {
  const NamesEditorDialog({
    required this.items,
    required this.existing,
    required this.rename,
    super.key,
  });

  final List<FileEntry> items;
  final Set<String> existing;
  final RenameService rename;

  @override
  State<NamesEditorDialog> createState() => _NamesEditorDialogState();
}

class _ApplyIntent extends Intent {
  const _ApplyIntent();
}

class _NamesEditorDialogState extends State<NamesEditorDialog> {
  late final List<String> _originals = [
    for (final item in widget.items) item.name,
  ];
  late final String _start = _originals.join('\n');
  // The caret at the first name: the editor opens at its top.
  late final _controller = TextEditingController.fromValue(
    TextEditingValue(
      text: _start,
      selection: const TextSelection.collapsed(offset: 0),
    ),
  );
  final _editor = FocusNode(debugLabel: 'names editor');

  /// The editor's own scroll, which the columns beside it follow.
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  final _numbers = ScrollController();
  final _names = ScrollController();
  final _status = ScrollController();
  late NamesCheck _check;
  late String _text = _start;
  int _caretLine = 0;
  int _editorLines = 1;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _check = _checkOf(_start);
    _editorLines = _linesIn(_start);
    _controller.addListener(_onEdit);
    _vertical.addListener(_follow);
  }

  @override
  void dispose() {
    _controller.dispose();
    _editor.dispose();
    for (final scroll in [_vertical, _horizontal, _numbers, _names, _status]) {
      scroll.dispose();
    }
    super.dispose();
  }

  NamesCheck _checkOf(String text) => checkNames(
    originals: _originals,
    text: text,
    existing: widget.existing,
  );

  static int _linesIn(String text) => '\n'.allMatches(text).length + 1;

  bool get _dirty => _controller.text != _start;

  /// The text or the caret moved: check again when the text changed, and
  /// follow the caret's line for the summary.
  void _onEdit() {
    final text = _controller.text;
    final offset = _controller.selection.baseOffset.clamp(0, text.length);
    final caretLine = '\n'.allMatches(text.substring(0, offset)).length;
    if (text == _text && caretLine == _caretLine) return;
    setState(() {
      if (text != _text) {
        _text = text;
        _check = _checkOf(text);
        _editorLines = _linesIn(text);
      }
      _caretLine = caretLine;
    });
  }

  /// The numbers, the names now and the problems scroll with the text.
  void _follow() {
    for (final column in [_numbers, _names, _status]) {
      if (!column.hasClients) continue;
      final position = column.position;
      final offset = _vertical.offset.clamp(0.0, position.maxScrollExtent);
      if (position.pixels != offset) position.jumpTo(offset);
    }
  }

  /// A wheel over the columns beside the text scrolls the text.
  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_vertical.hasClients) return;
    final position = _vertical.position;
    position.jumpTo(
      (position.pixels + event.scrollDelta.dy).clamp(
        0.0,
        position.maxScrollExtent,
      ),
    );
  }

  Future<void> _apply() async {
    final check = _check;
    if (!check.canApply || _applying) return;
    final l10n = context.l10n;
    setState(() => _applying = true);
    final outcomes = [
      for (final i in check.changed)
        RenameOutcome(
          path: widget.items[i].path,
          oldName: _originals[i],
          newName: check.newNames[i]!,
        ),
    ];
    try {
      final failures = await widget.rename.apply(outcomes);
      if (!mounted) return;
      if (failures.isNotEmpty) {
        showAppNotice(context, l10n.renameFailed(failures.length));
      }
      Navigator.of(context).pop(failures.length < outcomes.length);
    } on FerryxException catch (error) {
      if (!mounted) return;
      setState(() => _applying = false);
      showAppNotice(context, l10n.errorMessage(error));
    }
  }

  /// Esc, ⌘., Cancel with names edited: ask before they are lost.
  Future<void> _confirmLeave() async {
    final l10n = context.l10n;
    final discard = await AppDialog.confirm(
      context,
      title: l10n.namesDiscardTitle,
      message: l10n.namesDiscardMessage,
      confirmLabel: l10n.namesDiscard,
      cancelLabel: l10n.namesKeepEditing,
      destructive: true,
    );
    if (discard && mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final platform = Theme.of(context).platform;
    final applyChord = const Chord(LogicalKeyboardKey.enter, primary: true);
    final check = _check;
    return PopScope<bool>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmLeave());
      },
      child: Shortcuts(
        shortcuts: {applyChord.toActivator(platform): const _ApplyIntent()},
        child: Actions(
          actions: {
            _ApplyIntent: CallbackAction<_ApplyIntent>(
              onInvoke: (_) {
                unawaited(_apply());
                return null;
              },
            ),
          },
          child: AppDialog(
            title: l10n.namesTitle(widget.items.length),
            width: AppSizes.panelDialogWidth,
            body: SizedBox(
              height: _bodyHeight(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.namesHint(
                      applyChord.label(platform),
                      Chord.keyLabel(LogicalKeyboardKey.enter, platform),
                    ),
                    style: context.text.bodySmall?.copyWith(
                      color: context.appColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Expanded(
                    child: _NamesBox(
                      originals: _originals,
                      check: check,
                      editorLines: _editorLines,
                      controller: _controller,
                      focusNode: _editor,
                      vertical: _vertical,
                      horizontal: _horizontal,
                      numbers: _numbers,
                      names: _names,
                      status: _status,
                      onWheel: _onWheel,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _NamesSummary(check: check, caretLine: _caretLine),
                ],
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(l10n.actionCancel),
              ),
              FilledButton(
                onPressed: check.canApply && !_applying ? _apply : null,
                child: Text(l10n.actionRename),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The body's height: the lines as far as the window allows, never less
  /// than a picker's list.
  double _bodyHeight(BuildContext context) {
    final rows = math.max(_editorLines, _originals.length);
    final wanted =
        rows * _NamesBox.lineHeightOf(context) +
        _NamesBox.headerHeightOf(context) +
        6 * AppSpacing.md;
    return math.max(
      AppSizes.pickerListMaxHeight,
      math.min(wanted, dialogBodyMaxHeight(context)),
    );
  }
}

/// The box of the editor: a header, then side by side the line numbers,
/// the names now, the text, and per line what is wrong. Every column is
/// one line of the text per row, so each name sits beside its line.
class _NamesBox extends StatelessWidget {
  const _NamesBox({
    required this.originals,
    required this.check,
    required this.editorLines,
    required this.controller,
    required this.focusNode,
    required this.vertical,
    required this.horizontal,
    required this.numbers,
    required this.names,
    required this.status,
    required this.onWheel,
  });

  final List<String> originals;
  final NamesCheck check;
  final int editorLines;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ScrollController vertical;
  final ScrollController horizontal;
  final ScrollController numbers;
  final ScrollController names;
  final ScrollController status;
  final ValueChanged<PointerSignalEvent> onWheel;

  /// The text's style: monospace on a fixed line, which every column
  /// keeps.
  static TextStyle styleOf(BuildContext context) => context.mono;

  static double lineHeightOf(BuildContext context) {
    final style = styleOf(context);
    return MediaQuery.textScalerOf(context).scale(style.fontSize!) *
        (style.height ?? 1.3);
  }

  static double headerHeightOf(BuildContext context) =>
      context.metrics.listRowHeight;

  static const _inset = AppSpacing.xs;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final style = styleOf(context);
    final line = lineHeightOf(context);
    final rows = math.max(editorLines, originals.length);
    final digits = '$rows'.length;
    final scaler = MediaQuery.textScalerOf(context);
    final numbersWidth =
        scaler.scale(style.fontSize!) * 0.62 * math.max(digits, 2) +
        2 * AppSpacing.sm;
    final header = context.text.labelMedium?.copyWith(color: colors.textMuted);
    // The text's focus ring goes round the whole box, its field.
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, child) => FocusRing(
        focused: focusNode.hasFocus,
        radius: context.metrics.radius.tableFrame,
        child: child!,
      ),
      child: DecoratedBox(
        decoration: appEdgedBox(
          color: context.colors.surface,
          edge: colors.line,
          radius: context.metrics.radius.tableFrame,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            context.metrics.radius.tableFrame,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              // Narrow, the names now give way first; the problems' words
              // fold to their marks.
              final namesWidth = (width * 0.34).clamp(72.0, 280.0);
              final wide = width >= 560;
              final statusWidth = wide
                  ? scaler.scale(96).clamp(96.0, 140.0)
                  : AppIconSize.sm + 2 * AppSpacing.sm;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: headerHeightOf(context),
                    decoration: BoxDecoration(
                      color: colors.surfaceRaised,
                      border: AppBorder(bottom: BorderSide(color: colors.line)),
                    ),
                    child: Row(
                      children: [
                        SizedBox(width: numbersWidth),
                        SizedBox(
                          width: namesWidth,
                          child: Text(
                            l10n.renamePreviewOld,
                            style: header,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            l10n.renamePreviewNew,
                            style: header,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: statusWidth),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Column(
                          width: numbersWidth,
                          controller: numbers,
                          rows: rows,
                          lineHeight: line,
                          onWheel: onWheel,
                          row: (index) => _LineNumber(
                            number: index + 1,
                            problem: check.problems.elementAtOrNull(index),
                            changed: check.edited(index),
                            style: style,
                          ),
                        ),
                        _Column(
                          width: namesWidth,
                          controller: names,
                          rows: rows,
                          lineHeight: line,
                          onWheel: onWheel,
                          row: (index) => _NameNow(
                            name: originals.elementAtOrNull(index),
                            changed: check.edited(index),
                            style: style,
                          ),
                        ),
                        AppRule(axis: Axis.vertical, color: colors.line),
                        Expanded(
                          child: _Editor(
                            controller: controller,
                            focusNode: focusNode,
                            vertical: vertical,
                            horizontal: horizontal,
                            style: style,
                            minHeight: rows * line,
                          ),
                        ),
                        _Column(
                          width: statusWidth,
                          controller: status,
                          rows: rows,
                          lineHeight: line,
                          onWheel: onWheel,
                          row: (index) => _LineProblem(
                            problem: check.problems.elementAtOrNull(index),
                            message: _messageOf(l10n, check, index),
                            wide: wide,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// What is wrong with row [index], in full; `null` when nothing is.
String? _messageOf(FerryxLocalizations l10n, NamesCheck check, int index) {
  final line = index + 1;
  return switch (check.problems.elementAtOrNull(index)) {
    null => null,
    NameProblem.empty => l10n.namesProblemEmpty(line),
    NameProblem.separator => l10n.namesProblemSeparator(line),
    NameProblem.invalid => l10n.namesProblemInvalid(line),
    NameProblem.duplicate => l10n.namesProblemDuplicate(
      line,
      (check.duplicateOf[index] ?? index) + 1,
    ),
    NameProblem.exists => l10n.namesProblemExists(
      line,
      check.newNames[index] ?? '',
    ),
    NameProblem.extra => l10n.namesProblemExtra(line),
    NameProblem.missing => l10n.namesProblemMissing(line),
  };
}

/// A column beside the text: a row per line, built in view only, moved by
/// the text's scroll (a wheel over it scrolls the text).
class _Column extends StatelessWidget {
  const _Column({
    required this.width,
    required this.controller,
    required this.rows,
    required this.lineHeight,
    required this.onWheel,
    required this.row,
  });

  final double width;
  final ScrollController controller;
  final int rows;
  final double lineHeight;
  final ValueChanged<PointerSignalEvent> onWheel;
  final Widget Function(int index) row;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Listener(
      onPointerSignal: onWheel,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView.builder(
          controller: controller,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: _NamesBox._inset),
          itemExtent: lineHeight,
          itemCount: rows,
          itemBuilder: (context, index) => row(index),
        ),
      ),
    ),
  );
}

class _LineNumber extends StatelessWidget {
  const _LineNumber({
    required this.number,
    required this.problem,
    required this.changed,
    required this.style,
  });

  final int number;
  final NameProblem? problem;
  final bool changed;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        Expanded(
          child: Text(
            '$number',
            textAlign: TextAlign.right,
            maxLines: 1,
            style: style.copyWith(
              color: problem != null ? colors.danger : colors.textFaint,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        // A changed line's mark, as an editor marks a modified line.
        Container(
          width: AppSizes.focusBarHeight,
          color: changed ? colors.accent : const Color(0x00000000),
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }
}

/// A name as it is now, muted; fainter while its line leaves it as is.
class _NameNow extends StatelessWidget {
  const _NameNow({
    required this.name,
    required this.changed,
    required this.style,
  });

  final String? name;
  final bool changed;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final name = this.name;
    if (name == null) return const SizedBox.shrink();
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AppMiddleEllipsis(
          name,
          style: style.copyWith(
            color: changed ? colors.textMuted : colors.textFaint,
          ),
        ),
      ),
    );
  }
}

/// What is wrong with a line: a mark, and its word when there is room;
/// the whole sentence on hover and in the summary below.
class _LineProblem extends StatelessWidget {
  const _LineProblem({
    required this.problem,
    required this.message,
    required this.wide,
  });

  final NameProblem? problem;
  final String? message;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final problem = this.problem;
    final message = this.message;
    if (problem == null || message == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final colors = context.appColors;
    final word = switch (problem) {
      NameProblem.empty => l10n.namesShortEmpty,
      NameProblem.separator => l10n.namesShortSeparator,
      NameProblem.invalid => l10n.namesShortInvalid,
      NameProblem.duplicate => l10n.namesShortDuplicate,
      NameProblem.exists => l10n.namesShortExists,
      NameProblem.extra => l10n.namesShortExtra,
      NameProblem.missing => l10n.namesShortMissing,
    };
    return AppTooltip(
      message: message,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(
          children: [
            Icon(AppIcons.warning, size: AppIconSize.sm, color: colors.danger),
            if (wide) ...[
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  word,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(
                    color: colors.danger,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The text itself: no wrapping (a long name scrolls sideways), each line
/// exactly a row of the columns beside it.
class _Editor extends StatelessWidget {
  const _Editor({
    required this.controller,
    required this.focusNode,
    required this.vertical,
    required this.horizontal,
    required this.style,
    required this.minHeight,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ScrollController vertical;
  final ScrollController horizontal;
  final TextStyle style;

  /// As tall as the rows beside it, when lines are missing.
  final double minHeight;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Scrollbar(
      controller: vertical,
      child: SingleChildScrollView(
        controller: vertical,
        padding: const EdgeInsets.symmetric(vertical: _NamesBox._inset),
        child: Scrollbar(
          controller: horizontal,
          child: SingleChildScrollView(
            controller: horizontal,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: math.max(
                  0,
                  constraints.maxWidth - 2 * AppSpacing.sm,
                ),
                minHeight: minHeight,
              ),
              // As wide as its longest line: nothing wraps.
              child: IntrinsicWidth(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: style,
                  strutStyle: StrutStyle.fromTextStyle(
                    style,
                    forceStrutHeight: true,
                  ),
                  // No bezel: the box around the columns is the field.
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Under the text: how many names change, how many lines are wrong, and
/// the caret's line's problem, else the first one.
class _NamesSummary extends StatelessWidget {
  const _NamesSummary({required this.check, required this.caretLine});

  final NamesCheck check;
  final int caretLine;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final counts = [
      l10n.namesToRename(check.changed.length),
      if (check.errors > 0) l10n.namesErrors(check.errors),
    ].reduce(l10n.joinedDetails);
    final at = check.problems.elementAtOrNull(caretLine) != null
        ? caretLine
        : check.firstProblem;
    final message = !check.linesMatch
        ? l10n.namesLineCount(check.nameCount, check.lineCount)
        : at < 0
        ? null
        : _messageOf(l10n, check, at);
    final style = context.text.bodySmall!.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        Text(
          counts,
          style: style.copyWith(
            color: check.errors > 0 ? colors.danger : colors.textMuted,
          ),
        ),
        if (message != null) ...[
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(color: colors.danger),
            ),
          ),
        ],
      ],
    );
  }
}
