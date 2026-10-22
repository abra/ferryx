import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sync_cubit.dart';
import 'sync_plan.dart';

/// The comparison's rows: the path, the left side's size and date, the
/// action, the right side's. The keys: the arrows and ⇧ select, Space
/// walks a row's actions (all selected rows alike), → and ← send them to
/// a side, Backspace leaves them alone; a click on the action walks it,
/// the menu (right click, the menu key) offers every action.
class SyncTable extends StatelessWidget {
  const SyncTable({
    required this.tableKey,
    required this.state,
    required this.controller,
    required this.focusNode,
    required this.onCycle,
    required this.onAction,
    required this.onCycleTargets,
    required this.onReset,
    required this.allowedFor,
    super.key,
  });

  final GlobalKey<AppRowListState> tableKey;
  final SyncState state;
  final AppRowListController controller;
  final FocusNode focusNode;

  /// A click on the action of the row shown at this index.
  final ValueChanged<int> onCycle;

  /// Sets an action on the rows shown at these indexes.
  final void Function(Iterable<int> shown, RowAction action) onAction;

  /// Space: the selected rows' next action.
  final VoidCallback onCycleTargets;

  /// The suggested action again for the rows shown at these indexes.
  final void Function(Iterable<int> shown) onReset;
  final List<RowAction> Function(CompareRow row) allowedFor;

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final targets = controller.targets;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        onCycleTargets();
      case LogicalKeyboardKey.arrowRight:
        onAction(targets, RowAction.copyToRight);
      case LogicalKeyboardKey.arrowLeft:
        onAction(targets, RowAction.copyToLeft);
      case LogicalKeyboardKey.backspace:
        onAction(targets, RowAction.skip);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Future<void> _menu(BuildContext context, int index, Rect anchor) async {
    final l10n = context.l10n;
    final targets = controller.targets;
    final shown = targets.isEmpty ? [index] : targets;
    bool any(RowAction action) =>
        shown.any((i) => allowedFor(state.rowAt(i)).contains(action));
    AppMenuAction<_Pick> item(
      RowAction action,
      String label,
      IconData icon,
    ) => AppMenuAction(
      value: _Pick(action),
      label: label,
      icon: icon,
      enabled: any(action),
    );
    final picked = await showAppMenu<_Pick>(
      context: context,
      anchor: anchor,
      entries: [
        item(
          RowAction.copyToRight,
          l10n.syncActionCopyRight,
          AppIcons.forward,
        ),
        item(RowAction.copyToLeft, l10n.syncActionCopyLeft, AppIcons.back),
        if (any(RowAction.deleteLeft) || any(RowAction.deleteRight)) ...[
          const AppMenuSeparator(),
          item(
            RowAction.deleteLeft,
            l10n.syncActionDeleteLeft,
            AppIcons.trash,
          ),
          item(
            RowAction.deleteRight,
            l10n.syncActionDeleteRight,
            AppIcons.trash,
          ),
        ],
        const AppMenuSeparator(),
        item(RowAction.skip, l10n.syncActionSkip, AppIcons.minus),
        AppMenuAction(
          value: const _Pick(null),
          label: l10n.syncActionDefault,
          icon: AppIcons.undo,
        ),
      ],
    );
    if (!context.mounted || picked == null) return;
    switch (picked.action) {
      case final action?:
        onAction(shown, action);
      case null:
        onReset(shown);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textStyle = context.text.bodyMedium!;
    return AppRowList(
      key: tableKey,
      controller: controller,
      focusNode: focusNode,
      itemExtent: AppRowList.extentOf(context, style: textStyle),
      semanticLabel: l10n.syncTitle,
      header: const _Header(),
      empty: _Empty(state: state),
      onKey: _onKey,
      onMenu: (index, anchor) => _menu(context, index, anchor),
      itemBuilder: (context, index, look) => _Row(
        row: state.rowAt(index),
        action: state.actionOf(state.visible[index]),
        look: look,
        onCycle: () => onCycle(index),
      ),
    );
  }
}

/// A choice of the row menu: an action, or the suggested one (`null`).
class _Pick {
  const _Pick(this.action);

  final RowAction? action;

  @override
  bool operator ==(Object other) => other is _Pick && other.action == action;

  @override
  int get hashCode => action.hashCode;
}

/// The columns' titles: the name, then each side's name centred over its
/// size and date.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = context.text.labelSmall?.copyWith(
      color: context.appColors.textMuted,
    );
    final inset = context.metrics.rowInset + AppSpacing.sm;
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, AppSpacing.xs, inset, AppSpacing.xs),
      child: Row(
        children: [
          const SizedBox(width: AppIconSize.md + AppSpacing.sm),
          Expanded(
            flex: _Row.nameFlex,
            child: Text(l10n.columnName, style: style),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: _Row.sideFlex,
            child: Text(
              l10n.syncColumnLeft,
              style: style,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: AppSizes.glyphColumnWidth),
          Expanded(
            flex: _Row.sideFlex,
            child: Text(
              l10n.syncColumnRight,
              style: style,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.state});

  final SyncState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final String? text = switch (state.phase) {
      SyncPhase.idle => l10n.syncStartHint,
      SyncPhase.comparing => null,
      SyncPhase.compared when state.rowCount == 0 => l10n.syncIdentical,
      SyncPhase.compared => l10n.syncNoRows,
    };
    if (text == null) return const SizedBox.shrink();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(
            color: context.appColors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// One row: the item's icon and path (its middle gives way), each side's
/// size and date in figures of one width, the newer date in the text's
/// colour, and the action between the sides.
class _Row extends StatelessWidget {
  const _Row({
    required this.row,
    required this.action,
    required this.look,
    required this.onCycle,
  });

  static const nameFlex = 5;
  static const sizeFlex = 2;
  static const dateFlex = 3;
  static const sideFlex = sizeFlex + dateFlex;

  final CompareRow row;
  final RowAction action;
  final AppRowState look;
  final VoidCallback onCycle;

  @override
  Widget build(BuildContext context) {
    final ink = look.ink(context);
    final muted = look.muted(context);
    final text = context.text.bodyMedium!.copyWith(color: ink);
    return Row(
      children: [
        Icon(
          row.isDir ? AppIcons.folder : AppIcons.file,
          size: AppIconSize.md,
          color: muted,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: nameFlex,
          child: AppMiddleEllipsis(row.path, style: text),
        ),
        const SizedBox(width: AppSpacing.md),
        _Side(
          side: row.left,
          newer: row.state == CompareState.leftNewer,
          ink: ink,
          muted: muted,
        ),
        SizedBox(
          width: AppSizes.glyphColumnWidth,
          child: Center(
            child: _ActionGlyph(
              row: row,
              action: action,
              look: look,
              onTap: onCycle,
            ),
          ),
        ),
        _Side(
          side: row.right,
          newer: row.state == CompareState.rightNewer,
          ink: ink,
          muted: muted,
        ),
      ],
    );
  }
}

/// A side's size and date, or nothing where the item is not.
class _Side extends StatelessWidget {
  const _Side({
    required this.side,
    required this.newer,
    required this.ink,
    required this.muted,
  });

  final SideInfo? side;
  final bool newer;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final small = context.text.bodySmall!.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final side = this.side;
    final modified = side?.modified;
    return Expanded(
      flex: _Row.sideFlex,
      child: Row(
        children: [
          Expanded(
            flex: _Row.sizeFlex,
            child: Text(
              side == null || side.isDir ? '' : l10n.fileSize(side.size),
              style: small.copyWith(color: muted),
              textAlign: TextAlign.end,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: _Row.dateFlex,
            child: Text(
              modified == null ? '' : l10n.dateTime(modified),
              style: small.copyWith(color: newer ? ink : muted),
              textAlign: TextAlign.end,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
            ),
          ),
        ],
      ),
    );
  }
}

/// The row's action between its sides: an arrow toward the side copied
/// to, the trash on the side deleted from; left alone, `=` for identical
/// items, `≠` for items that differ, a dash otherwise. A click walks the
/// actions.
class _ActionGlyph extends StatelessWidget {
  const _ActionGlyph({
    required this.row,
    required this.action,
    required this.look,
    required this.onTap,
  });

  final CompareRow row;
  final RowAction action;
  final AppRowState look;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final onAccent = look.emphasized;
    final (
      IconData icon,
      Color color,
      Alignment align,
      String label,
    ) = switch (action) {
      RowAction.copyToRight => (
        AppIcons.forward,
        onAccent ? colors.onAccent : colors.accent,
        Alignment.center,
        l10n.syncActionCopyRight,
      ),
      RowAction.copyToLeft => (
        AppIcons.back,
        onAccent ? colors.onAccent : colors.accent,
        Alignment.center,
        l10n.syncActionCopyLeft,
      ),
      RowAction.deleteLeft => (
        AppIcons.trash,
        onAccent ? colors.onAccent : colors.danger,
        Alignment.centerLeft,
        l10n.syncActionDeleteLeft,
      ),
      RowAction.deleteRight => (
        AppIcons.trash,
        onAccent ? colors.onAccent : colors.danger,
        Alignment.centerRight,
        l10n.syncActionDeleteRight,
      ),
      RowAction.skip => switch (row.state) {
        CompareState.equal => (
          AppIcons.equal,
          look.muted(context),
          Alignment.center,
          l10n.syncStateEqual,
        ),
        CompareState.different => (
          AppIcons.notEqual,
          look.ink(context),
          Alignment.center,
          l10n.syncStateDifferent,
        ),
        CompareState.conflict => (
          AppIcons.notEqual,
          onAccent ? colors.onAccent : colors.danger,
          Alignment.center,
          l10n.syncStateConflict,
        ),
        _ => (
          AppIcons.minus,
          look.muted(context),
          Alignment.center,
          l10n.syncStateSkipped,
        ),
      },
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        label: label,
        child: AppTooltip(
          message: label,
          child: SizedBox(
            width: AppSizes.glyphColumnWidth,
            height: double.infinity,
            child: Align(
              alignment: align,
              child: Icon(icon, size: AppIconSize.md, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
