import 'dart:async';
import 'dart:math' as math;

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:operations_service/operations_service.dart';
import 'package:shortcuts/shortcuts.dart';

import 'duplicates_cubit.dart';
import 'duplicates_table.dart';

/// Find Duplicates under [root] (and [other], the other panel's folder,
/// on request): the conditions, then the groups of identical files as
/// they are settled, the most space to free first. Files are marked by
/// hand or by a rule; Move to Trash goes through the operations (so Undo
/// puts them back). Answers the path of a file to show in the panel.
Future<String?> showDuplicatesDialog(
  BuildContext context, {
  required String root,
  String? other,
  required DuplicatesService service,
  required OperationsService operations,
  required ShortcutMap shortcutMap,
}) => showAppDialog<String>(
  context,
  (context) => BlocProvider(
    create: (_) => DuplicatesCubit(service: service),
    child: DuplicatesDialog(
      root: root,
      other: other,
      operations: operations,
      shortcutMap: shortcutMap,
    ),
  ),
);

/// The size units offered, as multipliers of a byte.
const _units = [1, 1024, 1024 * 1024, 1024 * 1024 * 1024];

class DuplicatesDialog extends StatefulWidget {
  const DuplicatesDialog({
    required this.root,
    required this.other,
    required this.operations,
    required this.shortcutMap,
    super.key,
  });

  final String root;
  final String? other;
  final OperationsService operations;
  final ShortcutMap shortcutMap;

  @override
  State<DuplicatesDialog> createState() => _DuplicatesDialogState();
}

class _DuplicatesDialogState extends State<DuplicatesDialog> {
  late final _root = TextEditingController(text: widget.root);
  final _mask = TextEditingController();
  final _minSize = TextEditingController(text: '1');
  final _rows = AppRowListController();
  final _tableKey = GlobalKey<AppRowListState>();
  final _tableFocus = FocusNode(debugLabel: 'duplicates table');
  final _markKey = GlobalKey(debugLabel: 'mark button');
  int _unit = _units[0];
  bool _withOther = false;
  bool _hidden = false;

  DuplicatesCubit get _cubit => context.read<DuplicatesCubit>();

  @override
  void dispose() {
    _root.dispose();
    _mask.dispose();
    _minSize.dispose();
    _rows.dispose();
    _tableFocus.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final size = int.tryParse(_minSize.text.trim()) ?? 1;
    final other = widget.other;
    _rows.reset(0);
    _tableFocus.requestFocus();
    await _cubit.start(
      DuplicatesRequest(
        roots: [
          _root.text.trim().isEmpty ? widget.root : _root.text.trim(),
          if (_withOther && other != null) other,
        ],
        minSize: math.max(1, size * _unit),
        nameMask: _mask.text.trim(),
        includeHidden: _hidden,
      ),
    );
  }

  Future<void> _toggle() async {
    if (_cubit.state.running) {
      await _cubit.stop();
    } else {
      await _start();
    }
  }

  void _onState(BuildContext context, DuplicatesState state) {
    if (state.rows.isEmpty) {
      _rows.reset(0);
    } else {
      _rows.count = state.rows.length;
    }
  }

  List<String> _pathsOf(Iterable<int> rows) => [
    for (final row in rows) ?_cubit.state.fileAt(row)?.path,
  ];

  Future<void> _copyPaths() async {
    final state = _cubit.state;
    final paths = state.marked.isNotEmpty
        ? state.marked.toList()
        : _pathsOf(_rows.targets);
    if (paths.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: paths.join('\n')));
    if (mounted) {
      showAppNotice(context, context.l10n.noticePathsCopied(paths.length));
    }
  }

  void _reveal() {
    final paths = _pathsOf([if (_rows.lead >= 0) _rows.lead]);
    if (paths.isNotEmpty) Navigator.of(context).pop(paths.first);
  }

  Future<void> _trash() async {
    final l10n = context.l10n;
    final state = _cubit.state;
    final marked = state.marked;
    if (marked.isEmpty) return;
    final platform = Theme.of(context).platform;
    final undo = widget.shortcutMap.labelOf(AppCommand.undo, platform) ?? '';
    final full = state.fullyMarkedGroups;
    final confirmed = await AppDialog.confirm(
      context,
      title: l10n.dupesTrashTitle(marked.length),
      message: [
        l10n.dupesTrashBody(l10n.fileSize(state.markedBytes), undo),
        if (full > 0) l10n.dupesTrashAllCopies(full),
      ].join('\n'),
      confirmLabel: l10n.cmdMoveToTrash,
      cancelLabel: l10n.actionCancel,
      destructive: full > 0,
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.operations.start(
        OperationRequest(kind: OpKind.trash, sources: marked.toList()),
      );
      _cubit.removeFiles(marked);
    } on FerryxException catch (error) {
      if (mounted) showAppNotice(context, l10n.errorMessage(error));
    }
  }

  Future<void> _markMenu() async {
    final l10n = context.l10n;
    final box = _markKey.currentContext?.findRenderObject();
    final anchor = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : keyboardMenuAnchor(context);
    final picked = await showAppMenu<_Marks>(
      context: context,
      anchor: anchor,
      entries: [
        AppMenuAction(
          value: const _Marks(KeepRule.newest),
          label: l10n.dupesMarkAllButNewest,
          icon: AppIcons.clock,
        ),
        AppMenuAction(
          value: const _Marks(KeepRule.oldest),
          label: l10n.dupesMarkAllButOldest,
          icon: AppIcons.history,
        ),
        AppMenuAction(
          value: const _Marks(KeepRule.shortestPath),
          label: l10n.dupesMarkAllButShortest,
          icon: AppIcons.folderUp,
        ),
        const AppMenuSeparator(),
        AppMenuAction(
          value: const _Marks(null),
          label: l10n.dupesUnmarkAll,
          icon: AppIcons.close,
        ),
      ],
    );
    if (!mounted || picked == null) return;
    switch (picked.keep) {
      case final rule?:
        _cubit.markAllBut(rule);
      case null:
        _cubit.unmarkAll();
    }
  }

  Future<void> _rowMenu(int index, Rect anchor) async {
    final l10n = context.l10n;
    final file = _cubit.state.fileAt(index);
    if (file == null) return;
    final picked = await showAppMenu<int>(
      context: context,
      anchor: anchor,
      entries: [
        AppMenuAction(
          value: 0,
          label: _cubit.state.marked.contains(file.path)
              ? l10n.dupesUnmark
              : l10n.dupesMark,
          icon: AppIcons.check,
        ),
        AppMenuAction(value: 1, label: l10n.dupesReveal, icon: AppIcons.reveal),
        AppMenuAction(
          value: 2,
          label: l10n.dupesCopyPaths,
          icon: AppIcons.link,
        ),
      ],
    );
    if (!mounted) return;
    switch (picked) {
      case 0:
        _cubit.toggleMarks(_rows.targets.isEmpty ? [index] : _rows.targets);
      case 1:
        Navigator.of(context).pop(file.path);
      case 2:
        await _copyPaths();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocConsumer<DuplicatesCubit, DuplicatesState>(
      listener: _onState,
      builder: (context, state) => AppDialog(
        title: l10n.dupesTitle,
        width: AppSizes.resultsDialogWidth,
        body: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: appDialogBodyMaxHeight(context),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Conditions(
                root: _root,
                other: widget.other,
                withOther: _withOther,
                mask: _mask,
                minSize: _minSize,
                unit: _unit,
                hidden: _hidden,
                onWithOther: (v) => setState(() => _withOther = v),
                onUnit: (v) => setState(() => _unit = v),
                onHidden: (v) => setState(() => _hidden = v),
                onSubmit: () => unawaited(_start()),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(child: _Status(state: state)),
                  const SizedBox(width: AppSpacing.md),
                  // A pull-down: its chevron after the label.
                  OutlinedButton.icon(
                    key: _markKey,
                    style: AppButtonStyles.small(context),
                    iconAlignment: IconAlignment.end,
                    onPressed: state.groups.isEmpty
                        ? null
                        : () => unawaited(_markMenu()),
                    icon: const Icon(
                      AppIcons.chevronDown,
                      size: AppIconSize.sm,
                    ),
                    label: Text(l10n.dupesMark),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Flexible(
                child: SizedBox(
                  height: AppSizes.resultsTableHeight,
                  child: CommandHandlers(
                    handlers: {
                      AppCommand.selectAll: _rows.selectAll,
                      AppCommand.deselectAll: _rows.clear,
                      AppCommand.copyPaths: () => unawaited(_copyPaths()),
                      AppCommand.contextMenu: () =>
                          _tableKey.currentState?.openMenu(),
                    },
                    child: DuplicatesTable(
                      tableKey: _tableKey,
                      state: state,
                      controller: _rows,
                      focusNode: _tableFocus,
                      onToggle: (rows) => _cubit.toggleMarks(rows),
                      onActivate: (row) {
                        final file = state.fileAt(row);
                        if (file != null) Navigator.of(context).pop(file.path);
                      },
                      onMenu: (index, anchor) =>
                          unawaited(_rowMenu(index, anchor)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              _Footer(state: state),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionClose),
          ),
          OutlinedButton(
            onPressed: state.groups.isEmpty ? null : _reveal,
            child: Text(l10n.dupesReveal),
          ),
          OutlinedButton(
            onPressed: state.marked.isEmpty || state.running
                ? null
                : () => unawaited(_trash()),
            child: Text(l10n.cmdMoveToTrash),
          ),
          FilledButton.icon(
            onPressed: () => unawaited(_toggle()),
            icon: Icon(
              state.running ? AppIcons.cancel : AppIcons.search,
              size: AppIconSize.sm,
            ),
            label: Text(state.running ? l10n.findStop : l10n.findStart),
          ),
        ],
      ),
    );
  }
}

/// A choice of the Mark menu: all but the copy a rule keeps, or none
/// (`null`).
class _Marks {
  const _Marks(this.keep);

  final KeepRule? keep;

  @override
  bool operator ==(Object other) => other is _Marks && other.keep == keep;

  @override
  int get hashCode => keep.hashCode;
}

/// Where to look and what counts.
class _Conditions extends StatelessWidget {
  const _Conditions({
    required this.root,
    required this.other,
    required this.withOther,
    required this.mask,
    required this.minSize,
    required this.unit,
    required this.hidden,
    required this.onWithOther,
    required this.onUnit,
    required this.onHidden,
    required this.onSubmit,
  });

  final TextEditingController root;
  final String? other;
  final bool withOther;
  final TextEditingController mask;
  final TextEditingController minSize;
  final int unit;
  final bool hidden;
  final ValueChanged<bool> onWithOther;
  final ValueChanged<int> onUnit;
  final ValueChanged<bool> onHidden;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final other = this.other;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppFormField(
          label: l10n.dupesIn,
          child: AppTextField(
            controller: root,
            monospace: true,
            onSubmitted: (_) => onSubmit(),
          ),
        ),
        if (other != null) ...[
          const SizedBox(height: AppSpacing.sm),
          AppCheckbox(
            label: l10n.dupesAlsoIn(other),
            value: withOther,
            onChanged: onWithOther,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: context.metrics.toolbarSpacing,
              children: [
                Text(l10n.dupesNames, style: context.text.labelMedium),
                SizedBox(
                  width: AppSizes.maskFieldWidth,
                  child: AppTextField(
                    controller: mask,
                    monospace: true,
                    hintText: l10n.findNameHint,
                    onSubmitted: (_) => onSubmit(),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: context.metrics.toolbarSpacing,
              children: [
                Text(l10n.dupesMinSize, style: context.text.labelMedium),
                SizedBox(
                  width: AppSizes.settingsNumberFieldWidth,
                  child: AppTextField(
                    controller: minSize,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.end,
                    onSubmitted: (_) => onSubmit(),
                  ),
                ),
                AppPopupButton<int>(
                  value: unit,
                  items: [
                    (_units[0], l10n.findUnitBytes),
                    (_units[1], l10n.findUnitKilobytes),
                    (_units[2], l10n.findUnitMegabytes),
                    (_units[3], l10n.findUnitGigabytes),
                  ],
                  onChanged: onUnit,
                ),
              ],
            ),
            AppCheckbox(
              label: l10n.findIncludeHidden,
              value: hidden,
              onChanged: onHidden,
            ),
          ],
        ),
      ],
    );
  }
}

/// Where the search is, or what it found.
class _Status extends StatelessWidget {
  const _Status({required this.state});

  final DuplicatesState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final error = state.error;
    final String? text;
    if (error != null) {
      text = l10n.dupesError(error);
    } else if (state.running) {
      text = switch (state.phase) {
        DuplicatesPhase.scanning || null => l10n.dupesScanning(
          l10n.count(state.filesScanned),
        ),
        DuplicatesPhase.comparing ||
        DuplicatesPhase.hashing => l10n.joinedDetails(
          l10n.dupesComparing(
            l10n.count(state.filesHashed),
            l10n.count(state.candidates),
          ),
          l10n.dupesRead(l10n.fileSize(state.bytesDone)),
        ),
      };
    } else if (state.started) {
      text = state.groups.isEmpty
          ? l10n.dupesNone
          : l10n.joinedDetails(
              l10n.dupesGroups(state.groups.length),
              l10n.dupesWasted(l10n.fileSize(state.wasted)),
            );
    } else {
      text = null;
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppIconSize.sm),
      child: Row(
        children: [
          if (state.running) ...[
            const AppSpinner(size: AppIconSize.sm),
            const SizedBox(width: AppSpacing.sm),
          ],
          if (text != null)
            Flexible(
              child: Text(
                text,
                style: context.text.bodySmall?.copyWith(
                  color: error != null ? colors.danger : colors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (state.running && state.current != null) ...[
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppMiddleEllipsis(
                state.current!,
                style: context.text.bodySmall!.copyWith(
                  color: colors.textFaint,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The marks so far, and the key that marks.
class _Footer extends StatelessWidget {
  const _Footer({required this.state});

  final DuplicatesState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final platform = Theme.of(context).platform;
    final style = context.text.bodySmall?.copyWith(
      color: context.appColors.textMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.dupesKeysHint(
              Chord.keyLabel(LogicalKeyboardKey.space, platform),
            ),
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (state.marked.isNotEmpty)
          Text(
            l10n.joinedDetails(
              l10n.dupesMarked(state.marked.length),
              l10n.fileSize(state.markedBytes),
            ),
            style: style,
          ),
      ],
    );
  }
}
