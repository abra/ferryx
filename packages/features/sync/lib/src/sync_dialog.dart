import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operations_service/operations_service.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

import 'sync_cubit.dart';
import 'sync_plan.dart';
import 'sync_table.dart';

/// Synchronize Folders (Total Commander's Synchronize Directories): the two
/// folders, the options, Compare; then a table of what differs with an
/// action for each row, and Synchronize, which runs as an operation (the
/// dialog closes; its card shows the progress). [options] are the last
/// used ones and [onOptions] keeps the new ones.
Future<void> showSyncDialog(
  BuildContext context, {
  required String left,
  required String right,
  required FolderSyncService service,
  required CompareOptions options,
  required void Function(CompareOptions options) onOptions,
  required bool preserveAttributes,
  required bool verify,
  required ShortcutMap shortcutMap,
}) => showAppDialog<void>(
  context,
  (context) => BlocProvider(
    create: (_) =>
        SyncCubit(service: service, options: options, onOptions: onOptions),
    child: SyncDialog(
      left: left,
      right: right,
      preserveAttributes: preserveAttributes,
      verify: verify,
      shortcutMap: shortcutMap,
    ),
  ),
);

class SyncDialog extends StatefulWidget {
  const SyncDialog({
    required this.left,
    required this.right,
    required this.preserveAttributes,
    required this.verify,
    required this.shortcutMap,
    super.key,
  });

  final String left;
  final String right;
  final bool preserveAttributes;
  final bool verify;
  final ShortcutMap shortcutMap;

  @override
  State<SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<SyncDialog> {
  late final _left = TextEditingController(text: widget.left);
  late final _right = TextEditingController(text: widget.right);
  final _mask = TextEditingController();
  final _rows = AppRowListController();
  final _tableKey = GlobalKey<AppRowListState>();
  final _tableFocus = FocusNode(debugLabel: 'sync table');

  SyncCubit get _cubit => context.read<SyncCubit>();

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    _mask.dispose();
    _rows.dispose();
    _tableFocus.dispose();
    super.dispose();
  }

  Future<void> _compare() async {
    _rows.reset(0);
    _tableFocus.requestFocus();
    await _cubit.compare(
      left: _left.text.trim(),
      right: _right.text.trim(),
      mask: _mask.text,
    );
  }

  /// The button: compares, or stops a comparison under way.
  Future<void> _toggle() async {
    if (_cubit.state.running) {
      await _cubit.stop();
    } else {
      await _compare();
    }
  }

  void _swap() {
    final left = _left.text;
    _left.text = _right.text;
    _right.text = left;
  }

  /// The rows shown last time: rows that only grow keep the selection, a
  /// new filter (another list) starts over.
  List<int>? _shown;

  void _onState(BuildContext context, SyncState state) {
    if (!identical(state.visible, _shown)) {
      _shown = state.visible;
      _rows.reset(state.visibleCount);
    } else {
      _rows.count = state.visibleCount;
    }
  }

  Future<void> _synchronize() async {
    final l10n = context.l10n;
    final summary = _cubit.state.summary;
    if (summary.isEmpty) return;
    final platform = Theme.of(context).platform;
    final undo = widget.shortcutMap.labelOf(AppCommand.undo, platform) ?? '';
    final message = [
      l10n.joinedDetails(
        l10n.joinedDetails(
          l10n.syncToRight(l10n.count(summary.toRight)),
          l10n.syncToLeft(l10n.count(summary.toLeft)),
        ),
        l10n.syncBytes(l10n.fileSize(summary.bytes)),
      ),
      if (summary.toDelete > 0) l10n.syncConfirmDelete(summary.toDelete),
      if (summary.overwrites > 0) l10n.syncConfirmOverwrite(summary.overwrites),
      l10n.syncConfirmUndo(undo),
    ].join('\n');
    final confirmed = await AppDialog.confirm(
      context,
      title: l10n.syncConfirmTitle,
      message: message,
      confirmLabel: l10n.syncSynchronizeNow,
      cancelLabel: l10n.actionCancel,
      destructive: summary.toDelete > 0,
    );
    if (!confirmed || !mounted) return;
    try {
      await _cubit.synchronize(
        preserveAttributes: widget.preserveAttributes,
        verify: widget.verify,
      );
      if (mounted) Navigator.of(context).pop();
    } on FerryxException catch (error) {
      if (mounted) showAppNotice(context, l10n.errorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocConsumer<SyncCubit, SyncState>(
      listener: _onState,
      builder: (context, state) => AppDialog(
        title: l10n.syncTitle,
        width: AppSizes.resultsDialogWidth,
        body: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: appDialogBodyMaxHeight(context),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FolderFields(
                left: _left,
                right: _right,
                onSwap: _swap,
                onSubmit: () => unawaited(_compare()),
              ),
              const SizedBox(height: AppSpacing.md),
              _Options(
                options: state.options,
                mask: _mask,
                onChanged: _cubit.setOptions,
                onSubmit: () => unawaited(_compare()),
              ),
              const SizedBox(height: AppSpacing.md),
              _Filters(
                options: state.options,
                groups: state.groups,
                onChanged: _cubit.setOptions,
              ),
              const SizedBox(height: AppSpacing.sm),
              _Status(state: state),
              const SizedBox(height: AppSpacing.xs),
              Flexible(
                child: SizedBox(
                  height: AppSizes.resultsTableHeight,
                  child: CommandHandlers(
                    handlers: {
                      AppCommand.selectAll: _rows.selectAll,
                      AppCommand.deselectAll: _rows.clear,
                      AppCommand.contextMenu: () =>
                          _tableKey.currentState?.openMenu(),
                    },
                    child: SyncTable(
                      tableKey: _tableKey,
                      state: state,
                      controller: _rows,
                      focusNode: _tableFocus,
                      onCycle: (index) => _cubit.cycleAction([index]),
                      onAction: _cubit.setAction,
                      onCycleTargets: () => _cubit.cycleAction(_rows.targets),
                      onReset: _cubit.resetActions,
                      allowedFor: _cubit.allowedFor,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              const _KeysHint(),
            ],
          ),
        ),
        // Compare (or Stop) is the default: Return never synchronizes.
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionClose),
          ),
          OutlinedButton(
            onPressed: state.running || state.summary.isEmpty
                ? null
                : () => unawaited(_synchronize()),
            child: Text(l10n.syncSynchronize),
          ),
          FilledButton.icon(
            onPressed: () => unawaited(_toggle()),
            icon: Icon(
              state.running ? AppIcons.cancel : AppIcons.compareFolders,
              size: AppIconSize.sm,
            ),
            label: Text(state.running ? l10n.findStop : l10n.syncCompare),
          ),
        ],
      ),
    );
  }
}

/// The two folders side by side, as the table shows their rows, with a
/// button between them that swaps them.
class _FolderFields extends StatelessWidget {
  const _FolderFields({
    required this.left,
    required this.right,
    required this.onSwap,
    required this.onSubmit,
  });

  final TextEditingController left;
  final TextEditingController right;
  final VoidCallback onSwap;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: _Field(
            label: l10n.syncLeft,
            controller: left,
            onSubmit: onSubmit,
          ),
        ),
        SizedBox(width: context.metrics.toolbarSpacing),
        SizedBox(
          height: context.metrics.controlHeight,
          child: AppIconButton(
            icon: AppIcons.swap,
            tooltip: l10n.syncSwap,
            onPressed: onSwap,
          ),
        ),
        SizedBox(width: context.metrics.toolbarSpacing),
        Expanded(
          child: _Field(
            label: l10n.syncRight,
            controller: right,
            onSubmit: onSubmit,
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.onSubmit,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: context.text.labelMedium),
      const SizedBox(height: AppSpacing.xs),
      TextField(
        controller: controller,
        style: context.mono,
        onSubmitted: (_) => onSubmit(),
      ),
    ],
  );
}

/// How the folders are compared and which way they are made alike.
class _Options extends StatelessWidget {
  const _Options({
    required this.options,
    required this.mask,
    required this.onChanged,
    required this.onSubmit,
  });

  final CompareOptions options;
  final TextEditingController mask;
  final ValueChanged<CompareOptions> onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final oneWay = options.direction != SyncDirection.bothWays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          children: [
            AppCheckbox(
              label: l10n.syncSubfolders,
              value: options.recursive,
              onChanged: (v) => onChanged(options.copyWith(recursive: v)),
            ),
            AppCheckbox(
              label: l10n.syncByContent,
              value: options.byContent,
              onChanged: (v) => onChanged(options.copyWith(byContent: v)),
            ),
            AppCheckbox(
              label: l10n.syncFatTime,
              value: options.fatTime,
              onChanged: (v) => onChanged(options.copyWith(fatTime: v)),
            ),
            AppCheckbox(
              label: l10n.syncHidden,
              value: options.includeHidden,
              onChanged: (v) => onChanged(options.copyWith(includeHidden: v)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: context.metrics.toolbarSpacing,
              children: [
                Text(l10n.syncDirection, style: context.text.labelMedium),
                AppPopupButton<SyncDirection>(
                  value: options.direction,
                  items: [
                    (SyncDirection.bothWays, l10n.syncBothWays),
                    (SyncDirection.leftToRight, l10n.syncLeftToRight),
                    (SyncDirection.rightToLeft, l10n.syncRightToLeft),
                  ],
                  onChanged: (d) => onChanged(options.copyWith(direction: d)),
                ),
              ],
            ),
            AppCheckbox(
              label: l10n.syncDelete,
              value: oneWay && options.deleteMissing,
              onChanged: oneWay
                  ? (v) => onChanged(options.copyWith(deleteMissing: v))
                  : null,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: context.metrics.toolbarSpacing,
              children: [
                Text(l10n.syncMask, style: context.text.labelMedium),
                SizedBox(
                  width: AppSizes.maskFieldWidth,
                  child: TextField(
                    controller: mask,
                    style: context.mono,
                    decoration: InputDecoration(hintText: l10n.syncMaskHint),
                    onSubmitted: (_) => onSubmit(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Which rows the table shows, each with how many there are.
class _Filters extends StatelessWidget {
  const _Filters({
    required this.options,
    required this.groups,
    required this.onChanged,
  });

  final CompareOptions options;
  final Map<RowGroup, int> groups;
  final ValueChanged<CompareOptions> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(l10n.syncShow, style: context.text.labelMedium),
        _Filter(
          label: l10n.syncFilterLeftOnly,
          count: groups[RowGroup.leftOnly] ?? 0,
          value: options.showLeftOnly,
          onChanged: (v) => onChanged(options.copyWith(showLeftOnly: v)),
        ),
        _Filter(
          label: l10n.syncFilterRightOnly,
          count: groups[RowGroup.rightOnly] ?? 0,
          value: options.showRightOnly,
          onChanged: (v) => onChanged(options.copyWith(showRightOnly: v)),
        ),
        _Filter(
          label: l10n.syncFilterNewer,
          count: groups[RowGroup.newer] ?? 0,
          value: options.showNewer,
          onChanged: (v) => onChanged(options.copyWith(showNewer: v)),
        ),
        _Filter(
          label: l10n.syncFilterDifferent,
          count: groups[RowGroup.different] ?? 0,
          value: options.showDifferent,
          onChanged: (v) => onChanged(options.copyWith(showDifferent: v)),
        ),
        _Filter(
          label: l10n.syncFilterIdentical,
          count: groups[RowGroup.identical] ?? 0,
          value: options.showIdentical,
          onChanged: (v) => onChanged(options.copyWith(showIdentical: v)),
        ),
      ],
    );
  }
}

class _Filter extends StatelessWidget {
  const _Filter({
    required this.label,
    required this.count,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int count;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: AppSpacing.xs,
    children: [
      AppCheckbox(label: label, value: value, onChanged: onChanged),
      Text(
        context.l10n.count(count),
        style: context.text.bodySmall?.copyWith(
          color: context.appColors.textMuted,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

/// Where the comparison is, or what it found and what Synchronize would
/// do; the core's word when it could not run.
class _Status extends StatelessWidget {
  const _Status({required this.state});

  final SyncState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final problem = switch (state.problem) {
      SyncProblem.sameFolder => l10n.syncSameFolder,
      SyncProblem.missingFolder => l10n.syncStartHint,
      null => null,
    };
    final error = state.error;
    final failed = error != null || state.problem == SyncProblem.sameFolder;
    final style = context.text.bodySmall?.copyWith(
      color: failed ? colors.danger : colors.textMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final String? left;
    if (error != null) {
      left = l10n.syncError(error);
    } else if (problem != null) {
      left = problem;
    } else if (state.phase == SyncPhase.idle) {
      left = null;
    } else {
      final compared = l10n.syncItemsCompared(state.rowCount);
      left = state.unreadable > 0
          ? l10n.joinedDetails(compared, l10n.syncUnreadable(state.unreadable))
          : compared;
    }
    final summary = state.summary;
    final String? right;
    if (state.phase != SyncPhase.compared || error != null) {
      right = state.running && state.current != null
          ? l10n.findScanning(
              state.current!.isEmpty ? state.left : state.current!,
            )
          : null;
    } else if (summary.isEmpty) {
      right =
          state.rowCount == 0 ||
              (state.groups.length == 1 &&
                  state.groups.containsKey(RowGroup.identical))
          ? l10n.syncIdentical
          : l10n.syncNothingToDo;
    } else {
      right = [
        if (summary.toRight > 0) l10n.syncToRight(l10n.count(summary.toRight)),
        if (summary.toLeft > 0) l10n.syncToLeft(l10n.count(summary.toLeft)),
        if (summary.toDelete > 0)
          l10n.syncToDelete(l10n.count(summary.toDelete)),
        if (summary.bytes > 0) l10n.syncBytes(l10n.fileSize(summary.bytes)),
      ].reduce(l10n.joinedDetails);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppIconSize.sm),
      child: Row(
        children: [
          if (state.running) ...[
            const AppSpinner(size: AppIconSize.sm),
            const SizedBox(width: AppSpacing.sm),
          ],
          if (left != null)
            Flexible(
              child: Text(
                left,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (right != null) ...[
            const SizedBox(width: AppSpacing.md),
            // The plan at the row's end, whatever the left side holds.
            Expanded(
              flex: 2,
              child: Text(
                right,
                style: style?.copyWith(color: colors.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The table's keys, as a quiet line under it.
class _KeysHint extends StatelessWidget {
  const _KeysHint();

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    String key(LogicalKeyboardKey k) => Chord.keyLabel(k, platform);
    return Text(
      context.l10n.syncKeysHint(
        key(LogicalKeyboardKey.space),
        key(LogicalKeyboardKey.arrowRight),
        key(LogicalKeyboardKey.arrowLeft),
      ),
      style: context.text.bodySmall?.copyWith(
        color: context.appColors.textMuted,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
