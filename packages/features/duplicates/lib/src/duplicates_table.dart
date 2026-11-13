import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'duplicates_cubit.dart';

/// The groups of identical files: a heading (each file's size × the
/// copies, what could be freed) over the group's files, each with its
/// mark, name, folder and date. Space marks the selected files; a click
/// on a mark flips it; a double click shows the file in the panel.
class DuplicatesTable extends StatelessWidget {
  const DuplicatesTable({
    required this.tableKey,
    required this.state,
    required this.controller,
    required this.focusNode,
    required this.onToggle,
    required this.onActivate,
    required this.onMenu,
    super.key,
  });

  final GlobalKey<AppRowListState> tableKey;
  final DuplicatesState state;
  final AppRowListController controller;
  final FocusNode focusNode;
  final ValueChanged<List<int>> onToggle;
  final ValueChanged<int> onActivate;
  final void Function(int index, Rect anchor) onMenu;

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    onToggle(controller.targets);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => AppRowList(
    key: tableKey,
    controller: controller,
    focusNode: focusNode,
    itemExtent: AppRowList.extentOf(context),
    semanticLabel: context.l10n.dupesTitle,
    empty: _Empty(state: state),
    onKey: _onKey,
    onActivate: onActivate,
    onMenu: onMenu,
    itemBuilder: (context, index, look) => switch (state.rows[index]) {
      GroupRow(:final group) => _GroupHeading(
        group: state.groups[group],
        look: look,
      ),
      FileRow(:final group, :final file) => _FileLine(
        file: state.groups[group].files[file],
        roots: state.roots,
        marked: state.marked.contains(state.groups[group].files[file].path),
        look: look,
        onToggle: () => onToggle([index]),
      ),
    },
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.state});

  final DuplicatesState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final String? text = state.running || state.error != null
        ? null
        : state.started
        ? l10n.dupesNone
        : l10n.dupesStartHint;
    if (text == null) return const SizedBox.shrink();
    return Center(
      child: Text(
        text,
        style: context.text.bodyMedium?.copyWith(
          color: context.appColors.textMuted,
        ),
      ),
    );
  }
}

/// A group's heading: the size of each copy times the copies, and what
/// removing all but one would free.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.group, required this.look});

  final DuplicateGroup group;
  final AppRowState look;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = context.text.labelMedium?.copyWith(
      color: look.ink(context),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        Icon(
          AppIcons.duplicates,
          size: AppIconSize.md,
          color: look.muted(context),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            l10n.joinedDetails(
              l10n.dupesGroupHeader(
                l10n.fileSize(group.size),
                group.files.length,
              ),
              l10n.dupesWasted(l10n.fileSize(group.wasted)),
            ),
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// One copy: its mark, its name, its folder (the middle gives way) and its
/// date in figures of one width.
class _FileLine extends StatelessWidget {
  const _FileLine({
    required this.file,
    required this.roots,
    required this.marked,
    required this.look,
    required this.onToggle,
  });

  final DuplicateFile file;
  final List<String> roots;
  final bool marked;
  final AppRowState look;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final ink = look.ink(context);
    final muted = look.muted(context);
    final small = context.text.bodySmall!.copyWith(
      color: muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final modified = file.modified;
    // Its end tells the copies apart, so the cut keeps half of it.
    final folder = shownFolder(file.parentPath, roots);
    return Row(
      children: [
        const SizedBox(width: AppSpacing.md),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: Semantics(
            checked: marked,
            label: l10n.dupesMarkColumn,
            child: SizedBox(
              width: AppSizes.glyphColumnWidth,
              height: double.infinity,
              child: Icon(
                marked ? AppIcons.todo : AppIcons.taskOpen,
                size: AppIconSize.md,
                color: marked && !look.emphasized ? colors.danger : muted,
              ),
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: AppMiddleEllipsis(
            file.name,
            style: context.text.bodyMedium!.copyWith(color: ink),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          flex: 6,
          child: AppMiddleEllipsis(
            folder,
            style: small,
            tail: folder.length ~/ 2,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          flex: 2,
          child: Text(
            modified == null ? '' : l10n.dateTime(modified),
            style: small,
            textAlign: TextAlign.end,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
          ),
        ),
      ],
    );
  }
}
