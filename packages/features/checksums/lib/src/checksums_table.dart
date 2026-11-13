import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:material_ui/material_ui.dart';

import 'checksums_cubit.dart';

/// The files and their hashes: the name (its middle gives way), the hash
/// in monospace (or why there is none); checking, the outcome too. Rows
/// whose hash matches the pasted one are lit.
class ChecksumsTable extends StatelessWidget {
  const ChecksumsTable({
    required this.tableKey,
    required this.state,
    required this.controller,
    required this.focusNode,
    required this.matches,
    required this.onMenu,
    super.key,
  });

  final GlobalKey<AppRowListState> tableKey;
  final ChecksumsState state;
  final AppRowListController controller;
  final FocusNode focusNode;

  /// Rows whose hash is the one looked for.
  final Set<int> matches;
  final void Function(int index, Rect anchor) onMenu;

  @override
  Widget build(BuildContext context) {
    final verifying = state.mode == ChecksumMode.verify;
    return AppRowList(
      key: tableKey,
      controller: controller,
      focusNode: focusNode,
      itemExtent: AppRowList.extentOf(context, style: context.mono),
      semanticLabel: context.l10n.checksumTitle,
      header: _Header(verifying: verifying),
      empty: _Empty(state: state),
      onMenu: onMenu,
      itemBuilder: (context, index, look) => _Row(
        file: state.files[index],
        outcome: state.outcomeOf(index),
        verifying: verifying,
        matched: matches.contains(index),
        look: look,
      ),
    );
  }
}

const _nameFlex = 4;
const _statusFlex = 2;
const _hashFlex = 6;

class _Header extends StatelessWidget {
  const _Header({required this.verifying});

  final bool verifying;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = context.text.labelSmall?.copyWith(
      color: context.appColors.textMuted,
    );
    final inset = context.metrics.tableRowInset + AppSpacing.sm;
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, AppSpacing.xs, inset, AppSpacing.xs),
      child: Row(
        children: [
          const SizedBox(width: AppIconSize.md + AppSpacing.sm),
          Expanded(
            flex: _nameFlex,
            child: Text(l10n.columnName, style: style),
          ),
          const SizedBox(width: AppSpacing.md),
          if (verifying) ...[
            Expanded(
              flex: _statusFlex,
              child: Text(l10n.checksumColumnStatus, style: style),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            flex: _hashFlex,
            child: Text(l10n.checksumColumnHash, style: style),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.state});

  final ChecksumsState state;

  @override
  Widget build(BuildContext context) {
    if (state.running || state.error != null) return const SizedBox.shrink();
    return Center(
      child: Text(
        context.l10n.checksumNoFiles,
        style: context.text.bodyMedium?.copyWith(
          color: context.appColors.textMuted,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.file,
    required this.outcome,
    required this.verifying,
    required this.matched,
    required this.look,
  });

  final ChecksumFile file;
  final ChecksumOutcome? outcome;
  final bool verifying;
  final bool matched;
  final AppRowState look;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final ink = look.ink(context);
    final muted = look.muted(context);
    final outcome = this.outcome;
    final failed = outcome != null && outcome.status != ChecksumStatus.ok;
    final alarm = look.emphasized ? ink : colors.danger;
    // A file not there shows the hash listed for it, greyed; one that
    // could not be read says why.
    final error = outcome?.error;
    final listed = outcome?.status == ChecksumStatus.missing
        ? file.expected
        : null;
    final hashText = switch (outcome) {
      null => l10n.checksumPending,
      ChecksumOutcome(:final hash?) => hash,
      _ when listed != null => listed,
      _ when error != null => l10n.errorMessage(error),
      _ => '',
    };
    final mono = outcome?.hash != null || listed != null;
    final hashStyle = (mono ? context.mono : context.text.bodySmall!).copyWith(
      color: switch (outcome) {
        null => muted,
        _ when listed != null => muted,
        ChecksumOutcome(hash: null) => alarm,
        _ => verifying && failed ? alarm : ink,
      },
    );
    final row = Row(
      children: [
        Icon(
          matched ? AppIcons.checkCircle : AppIcons.file,
          size: AppIconSize.md,
          color: matched && !look.emphasized ? colors.accent : muted,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: _nameFlex,
          child: AppMiddleEllipsis(
            file.name,
            style: context.text.bodyMedium!.copyWith(color: ink),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        if (verifying) ...[
          Expanded(
            flex: _statusFlex,
            child: Text(
              outcome == null
                  ? l10n.checksumPending
                  : l10n.checksumStatusLabel(outcome.status),
              style: context.text.bodySmall?.copyWith(
                color: failed ? alarm : muted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          flex: _hashFlex,
          child: Text(
            hashText,
            style: hashStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    if (!matched || look.selected) return row;
    // A match lights its row, under the selection's plate.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: BorderRadius.circular(context.metrics.radius.tableRow),
      ),
      child: row,
    );
  }
}
