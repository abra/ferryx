import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operations_service/operations_service.dart';
import 'package:shortcuts/shortcuts.dart';

import 'checksums_cubit.dart';
import 'checksums_table.dart';

/// Checksums of [paths] (folders walked), named relative to [base]: the
/// algorithm, a table of the hashes as they come, a field to paste an
/// expected hash into, copying and saving a checksum file. A single
/// checksum file among [paths] is checked instead: OK, mismatch, missing.
Future<void> showChecksumsDialog(
  BuildContext context, {
  required List<String> paths,
  required String base,
  required ChecksumService service,
  ChecksumAlgorithm? algorithm,
}) => showAppDialog<void>(
  context,
  (context) => BlocProvider(
    create: (_) => ChecksumsCubit(
      service: service,
      paths: paths,
      base: base,
      algorithm: algorithm,
    )..start(),
    child: const ChecksumsDialog(),
  ),
);

class ChecksumsDialog extends StatefulWidget {
  const ChecksumsDialog({super.key});

  @override
  State<ChecksumsDialog> createState() => _ChecksumsDialogState();
}

class _ChecksumsDialogState extends State<ChecksumsDialog> {
  final _expected = TextEditingController();
  final _rows = AppRowListController();
  final _tableKey = GlobalKey<AppRowListState>();
  final _tableFocus = FocusNode(debugLabel: 'checksums table');

  ChecksumsCubit get _cubit => context.read<ChecksumsCubit>();

  @override
  void initState() {
    super.initState();
    _expected.addListener(_onExpected);
  }

  @override
  void dispose() {
    _expected.dispose();
    _rows.dispose();
    _tableFocus.dispose();
    super.dispose();
  }

  /// A pasted hash brings its first match into view.
  void _onExpected() {
    setState(() {});
    final matches = _cubit.state.matching(_expected.text);
    if (matches.isNotEmpty) _rows.moveTo(matches.first);
  }

  void _onState(BuildContext context, ChecksumsState state) {
    if (state.files.isEmpty) {
      _rows.reset(0);
    } else {
      _rows.count = state.files.length;
    }
  }

  Future<void> _copy(List<String> lines) async {
    if (lines.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) {
      showAppNotice(context, context.l10n.checksumCopied(lines.length));
    }
  }

  List<String> _hashesOf(Iterable<int> indexes) => [
    for (final i in indexes) ?_cubit.state.outcomeOf(i)?.hash,
  ];

  List<String> _linesOf(Iterable<int> indexes) {
    final state = _cubit.state;
    return [
      for (final i in indexes)
        if (state.outcomeOf(i)?.hash case final hash?)
          '$hash  ${state.files[i].name}',
    ];
  }

  Future<void> _menu(int index, Rect anchor) async {
    final l10n = context.l10n;
    final targets = _rows.targets.isEmpty ? [index] : _rows.targets;
    final picked = await showAppMenu<bool>(
      context: context,
      anchor: anchor,
      entries: [
        AppMenuAction(
          value: false,
          label: l10n.checksumCopyHash,
          icon: AppIcons.copy,
          enabled: _hashesOf(targets).isNotEmpty,
        ),
        AppMenuAction(
          value: true,
          label: l10n.checksumCopyLine,
          icon: AppIcons.text,
          enabled: _hashesOf(targets).isNotEmpty,
        ),
      ],
    );
    if (picked == null || !mounted) return;
    await _copy(picked ? _linesOf(targets) : _hashesOf(targets));
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final name = await AppDialog.prompt(
      context,
      title: l10n.checksumSaveTitle,
      confirmLabel: l10n.actionSave,
      cancelLabel: l10n.actionCancel,
      initialValue: _cubit.defaultFileName,
    );
    if (name == null || name.contains('/') || !mounted) return;
    try {
      await _saveAs(name, overwrite: false);
    } on FerryxException catch (error) {
      if (!mounted) return;
      if (error.kind != FerryxErrorKind.alreadyExists) {
        showAppNotice(context, l10n.errorMessage(error));
        return;
      }
      final replace = await AppDialog.confirm(
        context,
        title: l10n.checksumSaveExists(name),
        confirmLabel: l10n.checksumReplace,
        cancelLabel: l10n.actionCancel,
        destructive: true,
      );
      if (!replace || !mounted) return;
      await _saveAs(name, overwrite: true).catchError((Object e) {
        if (mounted && e is FerryxException) {
          showAppNotice(context, l10n.errorMessage(e));
        }
      });
    }
  }

  Future<void> _saveAs(String name, {required bool overwrite}) async {
    await _cubit.save(name, overwrite: overwrite);
    if (mounted) showAppNotice(context, context.l10n.checksumSaved(name));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocConsumer<ChecksumsCubit, ChecksumsState>(
      listener: _onState,
      builder: (context, state) {
        final verifying = state.mode == ChecksumMode.verify;
        final matches = verifying
            ? const <int>[]
            : state.matching(_expected.text);
        return AppDialog(
          title: verifying
              ? l10n.checksumVerifyTitle(_cubit.sumsName)
              : l10n.checksumTitle,
          width: AppSizes.resultsDialogWidth,
          body: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: appDialogBodyMaxHeight(context),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Controls(
                  state: state,
                  canVerify: ChecksumsCubit.verifiable(_cubit.paths),
                  onMode: (mode) => unawaited(_cubit.setMode(mode)),
                  onAlgorithm: (a) => unawaited(_cubit.setAlgorithm(a)),
                  onRecursive: (v) => unawaited(_cubit.setRecursive(v)),
                ),
                if (!verifying) ...[
                  const SizedBox(height: AppSpacing.md),
                  _Expected(
                    controller: _expected,
                    matches: matches,
                    state: state,
                  ),
                ],
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
                        AppCommand.copyPaths: () =>
                            unawaited(_copy(_hashesOf(_rows.targets))),
                        AppCommand.contextMenu: () =>
                            _tableKey.currentState?.openMenu(),
                      },
                      child: ChecksumsTable(
                        tableKey: _tableKey,
                        state: state,
                        controller: _rows,
                        focusNode: _tableFocus,
                        matches: matches.toSet(),
                        onMenu: (index, anchor) =>
                            unawaited(_menu(index, anchor)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: state.lines.isEmpty
                  ? null
                  : () => unawaited(
                      _copy([
                        for (final line in state.lines)
                          '${line.hash}  ${line.name}',
                      ]),
                    ),
              child: Text(l10n.checksumCopyAll),
            ),
            if (!verifying)
              OutlinedButton(
                onPressed: state.running || state.lines.isEmpty
                    ? null
                    : () => unawaited(_save()),
                child: Text(l10n.checksumSave),
              ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.actionDone),
            ),
          ],
        );
      },
    );
  }
}

/// Calculate or check (for a checksum file), the algorithm, the
/// subfolders.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.state,
    required this.canVerify,
    required this.onMode,
    required this.onAlgorithm,
    required this.onRecursive,
  });

  final ChecksumsState state;
  final bool canVerify;
  final ValueChanged<ChecksumMode> onMode;
  final ValueChanged<ChecksumAlgorithm> onAlgorithm;
  final ValueChanged<bool> onRecursive;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final verifying = state.mode == ChecksumMode.verify;
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (canVerify)
          AppSegmentedControl<ChecksumMode>(
            options: [
              (ChecksumMode.verify, l10n.checksumModeVerify),
              (ChecksumMode.calculate, l10n.checksumModeCalculate),
            ],
            value: state.mode,
            onChanged: onMode,
          ),
        if (!verifying) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: context.metrics.toolbarSpacing,
            children: [
              Text(l10n.checksumAlgorithm, style: context.text.labelMedium),
              AppSegmentedControl<ChecksumAlgorithm>(
                options: [
                  for (final a in ChecksumAlgorithm.values) (a, a.label),
                ],
                value: state.algorithm,
                onChanged: onAlgorithm,
              ),
            ],
          ),
          AppCheckbox(
            label: l10n.checksumSubfolders,
            value: state.recursive,
            onChanged: onRecursive,
          ),
        ] else
          Text(
            state.algorithm.label,
            style: context.text.labelMedium?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
      ],
    );
  }
}

/// A field for a hash to look for, and whether a file has it.
class _Expected extends StatelessWidget {
  const _Expected({
    required this.controller,
    required this.matches,
    required this.state,
  });

  final TextEditingController controller;
  final List<int> matches;
  final ChecksumsState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final typed = controller.text.trim().length >= 8;
    final String? verdict = !typed
        ? null
        : matches.length == 1
        ? l10n.checksumMatch(state.files[matches.single].name)
        : matches.isNotEmpty
        ? l10n.checksumMatchMany(matches.length)
        : state.running
        ? null
        : l10n.checksumNoMatch;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.checksumExpected, style: context.text.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            // Room for a SHA-256 in full; the verdict takes what is left.
            Expanded(
              flex: 3,
              child: TextField(
                controller: controller,
                style: context.mono,
                decoration: InputDecoration(
                  hintText: l10n.checksumExpectedHint,
                ),
              ),
            ),
            if (verdict != null) ...[
              const SizedBox(width: AppSpacing.md),
              Icon(
                matches.isEmpty ? AppIcons.error : AppIcons.checkCircle,
                size: AppIconSize.sm,
                color: matches.isEmpty ? colors.danger : colors.accent,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                flex: 2,
                child: Text(
                  verdict,
                  style: context.text.bodySmall?.copyWith(
                    color: matches.isEmpty ? colors.danger : colors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// How far the hashing is, or how a check came out.
class _Status extends StatelessWidget {
  const _Status({required this.state});

  final ChecksumsState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final error = state.error;
    final style = context.text.bodySmall?.copyWith(
      color: error != null ? colors.danger : colors.textMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final String text;
    if (error != null) {
      text = l10n.checksumError(error);
    } else if (state.running) {
      text = [
        l10n.opProgressItems(state.filesDone, state.files.length),
        if (state.bytesTotal > 0)
          l10n.opProgressBytes(
            l10n.fileSize(state.bytesDone),
            l10n.fileSize(state.bytesTotal),
          ),
      ].reduce(l10n.joinedDetails);
    } else if (state.mode == ChecksumMode.verify) {
      final counts = state.statusCounts;
      final summary = l10n.checksumVerifySummary(
        l10n.count(counts[ChecksumStatus.ok] ?? 0),
        l10n.count(counts[ChecksumStatus.mismatch] ?? 0),
        l10n.count(counts[ChecksumStatus.missing] ?? 0),
      );
      text = state.badLines > 0
          ? l10n.joinedDetails(summary, l10n.checksumBadLines(state.badLines))
          : summary;
    } else {
      text = l10n.checksumFiles(state.files.length);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppIconSize.sm),
      child: Row(
        children: [
          if (state.running) ...[
            const AppSpinner(size: AppIconSize.sm),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Text(
              text,
              style: style,
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
