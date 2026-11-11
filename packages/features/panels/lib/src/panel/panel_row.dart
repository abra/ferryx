import 'dart:math' as math;

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';

import 'file_icon.dart';
import 'recent_entries.dart';

/// How a row is drawn: under the cursor, selected, or plain, in the panel
/// the keys are in or in the other one.
///
/// Orthodox managers tell the cursor from the selection: the cursor row
/// takes a stronger fill and an accent edge; marked rows have a soft tint
/// and a check mark. Where the keys are not (the other panel, a window
/// that is not active) both grey to the unemphasized selection with the
/// normal text, as macOS greys a selection without focus.
@immutable
class RowLook {
  const RowLook({
    required this.cursor,
    required this.active,
    required this.selected,
    required this.match,
    this.dimmed = false,
    this.dropTarget = false,
    this.recentAge,
  });

  final bool cursor;

  /// The row's panel has the keys and the window is active
  /// (`AppFocusArea.activeOf` with the panel's own flag).
  final bool active;
  final bool selected;

  /// Quick-search ranges to underline, or none.
  final List<(int, int)>? match;

  /// A row that does not match the quick search while all rows show.
  final bool dimmed;

  /// A folder row files hang over and would be dropped into: the
  /// emphasized selection, as Finder lights it, wherever the keys are.
  final bool dropTarget;
  final RecentEntryAge? recentAge;

  /// The cursor row in the active panel, or the drop's folder.
  bool get emphasized => (cursor && active) || dropTarget;

  Color? background(AppColorsExt colors) {
    if (dropTarget) return colors.selectionAccent;
    if (cursor) return active ? colors.cursorFill : colors.selectionMuted;
    if (selected) return active ? colors.accentSoft : colors.selectionMuted;
    return switch (recentAge) {
      RecentEntryAge.hour => colors.recentHour,
      RecentEntryAge.day => colors.recentDay,
      null => null,
    };
  }

  /// Painted over the fill without changing column positions or row size.
  /// The check mark remains independent when the cursor crosses a selection.
  Decoration? cursorDecoration(AppColorsExt colors) => emphasized
      ? BoxDecoration(
          border: AppBorder(
            left: BorderSide(
              color: colors.accent,
              width: dropTarget
                  ? AppSizes.focusBarHeight
                  : AppSizes.cursorBarWidth,
            ),
          ),
        )
      : null;

  /// The name's colour; [ink] is the row's own when nothing overrides it.
  Color foreground(BuildContext context, {Color? ink}) {
    final colors = context.appColors;
    if (dropTarget) return colors.onSelection;
    if (cursor && active) return colors.onCursor;
    if (selected && active) return colors.link;
    if (dimmed) return colors.textFaint;
    return ink ?? context.colors.onSurface;
  }

  /// The colour of a row's details (size, date) and of its check mark's
  /// companions.
  Color secondary(AppColorsExt colors) {
    if (dropTarget) return colors.onSelectionMuted;
    if (cursor && active) return colors.onCursorMuted;
    if (dimmed) return colors.textFaint;
    return colors.textMuted;
  }

  /// The selection's check mark.
  Color checkMark(AppColorsExt colors) {
    if (dropTarget) return colors.onSelection;
    if (cursor && active) return colors.onCursor;
    return active ? colors.accent : colors.textMuted;
  }
}

/// Room above the first row and below the last, so the inset highlight
/// of a row at either end stands clear of the header's line and the
/// footer's.
const double rowsInset = AppSpacing.xs;

/// The height of a row at the current text size: the platform's table
/// row, grown with the text.
double panelRowHeight(BuildContext context) {
  final line = context.text.bodyMedium!;
  final text = MediaQuery.textScalerOf(
    context,
  ).scale(line.fontSize! * line.height!);
  final base = context.metrics.listRowHeight;
  return (text + AppSpacing.xs).clamp(base, base * 2).roundToDouble();
}

/// A row's name with its icon, the quick-search match underlined; while
/// the row is renamed, [field] takes the name's place and the icon stays.
class RowName extends StatelessWidget {
  const RowName({
    required this.entry,
    required this.look,
    this.field,
    this.iconSize = AppIconSize.md,
    super.key,
  });

  final FileEntry entry;
  final RowLook look;
  final Widget? field;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (icon, tint) = FileIcon.describe(entry, colors);
    // The row drops its fill under a rename's field: the icon keeps its
    // own colour, not the one for the accent.
    final iconColor = look.emphasized && field == null
        ? look.foreground(context)
        : tint;
    final base = context.text.bodyMedium!.copyWith(
      color: look.foreground(context),
      fontStyle: entry.isSymlink ? FontStyle.italic : null,
    );
    final style = entry.isHidden && !look.cursor && !look.dropTarget
        ? base.copyWith(color: colors.textFaint)
        : base;
    final match = look.match;
    // A long name loses its middle, so the extension stays in view; with
    // a search on, the underlined letters stay instead.
    final plainName = match == null || match.isEmpty
        ? AppMiddleEllipsis(entry.isParent ? '..' : entry.name, style: style)
        : Text.rich(
            _spans(entry.name, match, style, colors),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          );
    // Finder tags: their colours as dots right after the name, their
    // names in the dots' tip.
    final dots = [
      for (final tag in entry.tags)
        if (tag.color > 0) tag.color,
    ];
    final dotSize = ((base.fontSize ?? AppIconSize.sm) * 0.75).roundToDouble();
    final Widget name = dots.isEmpty
        ? plainName
        : Row(
            children: [
              Flexible(child: plainName),
              const SizedBox(width: AppSpacing.xs),
              AppTooltip(
                message: context.l10n.tagNames(entry.tags.map((t) => t.name)),
                child: AppTagDots(
                  colors: dots,
                  // A contrasting ring separates tags from the cursor fill.
                  ring: look.emphasized
                      ? look.foreground(context)
                      : look.background(colors) ?? colors.window,
                  size: dotSize,
                ),
              ),
            ],
          );
    final dotsWidth = dots.isEmpty
        ? 0.0
        : AppTagDots.widthOf(dots.length, dotSize) + AppSpacing.xs;
    return Row(
      children: [
        Icon(icon, size: iconSize, color: iconColor),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child:
              field ??
              (entry.folder.isEmpty
                  ? name
                  : _NameWithFolder(
                      name: name,
                      nameText: entry.name,
                      nameExtra: dotsWidth,
                      nameStyle: style,
                      folder: entry.folder,
                      folderStyle: base.copyWith(
                        color: look.secondary(colors),
                        fontStyle: FontStyle.normal,
                      ),
                    )),
        ),
      ],
    );
  }

  /// The name with its matched ranges underlined; no change of weight, so
  /// the name keeps its width while the search is typed.
  TextSpan _spans(
    String name,
    List<(int, int)> match,
    TextStyle style,
    AppColorsExt colors,
  ) {
    final chars = name.characters.toList();
    final underline = style.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: look.emphasized ? style.color : colors.accent,
      decorationThickness: 2,
    );
    final spans = <TextSpan>[];
    var at = 0;
    for (final (start, end) in match) {
      final from = start.clamp(at, chars.length);
      final to = end.clamp(from, chars.length);
      if (from > at) {
        spans.add(TextSpan(text: chars.sublist(at, from).join()));
      }
      spans.add(
        TextSpan(text: chars.sublist(from, to).join(), style: underline),
      );
      at = to;
    }
    if (at < chars.length) spans.add(TextSpan(text: chars.sublist(at).join()));
    return TextSpan(style: style, children: spans);
  }
}

/// A flat view's row: the name, then in the secondary colour the folder
/// it is in. Both take their own width when they fit; when they do not,
/// the folder gives way first (losing its middle, so its last folder
/// stays) down to what the name leaves, and the name keeps at least
/// three fifths of the room.
class _NameWithFolder extends StatelessWidget {
  const _NameWithFolder({
    required this.name,
    required this.nameText,
    required this.nameStyle,
    required this.folder,
    required this.folderStyle,
    this.nameExtra = 0,
  });

  final Widget name;
  final String nameText;
  final TextStyle nameStyle;

  /// What [name] shows besides its text (the tags' dots).
  final double nameExtra;
  final String folder;
  final TextStyle folderStyle;

  /// The share of the row a long name keeps against a long folder.
  static const double nameShare = 0.6;

  /// The room a long folder keeps against a long name: a part of the
  /// row, within these bounds at text scale 1.
  static const double folderKeepsShare = 0.3;
  static const double folderKeepsMin = 36;
  static const double folderKeepsMax = 96;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final available = constraints.maxWidth - AppSpacing.md;
      if (available <= 0) return name;
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      double measure(String text, TextStyle style) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: direction,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width.ceilToDouble();
      }

      final nameWidth = measure(nameText, nameStyle) + nameExtra;
      final folderWidth = measure(folder, folderStyle);
      final double nameRoom;
      if (nameWidth + folderWidth <= available) {
        nameRoom = nameWidth;
      } else {
        // The folder keeps a little room for its last letters; the name
        // keeps the rest, three fifths at least.
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final folderKeeps = math.min(
          folderWidth,
          (available * folderKeepsShare).clamp(
            folderKeepsMin * scale,
            folderKeepsMax * scale,
          ),
        );
        nameRoom = math.min(
          nameWidth,
          math.max(available * nameShare, available - folderKeeps),
        );
      }
      return Row(
        children: [
          SizedBox(width: nameRoom, child: name),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: AppMiddleEllipsis(folder, style: folderStyle)),
        ],
      );
    },
  );
}

/// What a screen reader says for a row: its name, the folder of a flat
/// view's row, its tags.
String rowSemanticsLabel(BuildContext context, FileEntry entry) {
  final l10n = context.l10n;
  if (entry.isParent) return l10n.panelParentFolder;
  var label = entry.folder.isEmpty
      ? entry.name
      : l10n.flatRowLabel(entry.name, entry.folder);
  if (entry.tags.isNotEmpty) {
    label = l10n.tagsRowLabel(
      label,
      l10n.tagNames(entry.tags.map((t) => t.name)),
    );
  }
  final age = recentEntryAge(entry, RecentEntriesClock.nowOf(context));
  return switch (age) {
    RecentEntryAge.hour => l10n.joinedDetails(label, l10n.panelRecentHourHelp),
    RecentEntryAge.day => l10n.joinedDetails(label, l10n.panelRecentDayHelp),
    null => label,
  };
}

/// A folder with nothing to show, in either view.
class EmptyRows extends StatelessWidget {
  const EmptyRows({this.read = true, super.key});

  /// The folder was read; nothing is said of one not read yet (on its way,
  /// or on a server out of reach).
  final bool read;

  @override
  Widget build(BuildContext context) => !read
      ? const SizedBox.expand()
      : Center(
          child: Text(
            context.l10n.panelEmptyFolder,
            style: context.text.bodyMedium?.copyWith(
              color: context.appColors.textFaint,
            ),
          ),
        );
}

/// The text of a list column for [entry].
String columnText(BuildContext context, FileEntry entry, ListColumn column) {
  final l10n = context.l10n;
  switch (column) {
    case ListColumn.name:
      return entry.name;
    case ListColumn.extension:
      return entry.isDir ? '' : entry.extension;
    case ListColumn.size:
      if (entry.isParent) return '';
      final size = entry.size;
      if (size == null) return entry.isDir ? l10n.panelFolderSize : '';
      return l10n.fileSize(size);
    case ListColumn.modified:
      return entry.modified == null ? '' : l10n.dateTime(entry.modified!);
    case ListColumn.created:
      return entry.created == null ? '' : l10n.dateTime(entry.created!);
    case ListColumn.added:
      return entry.added == null ? '' : l10n.dateTime(entry.added!);
    case ListColumn.accessed:
      return entry.accessed == null ? '' : l10n.dateTime(entry.accessed!);
    case ListColumn.permissions:
      return entry.isParent ? '' : entry.permissionsText;
    case ListColumn.owner:
      return entry.owner;
    case ListColumn.group:
      return entry.group;
  }
}

/// The widths of the list's columns, in points at text scale 1.
abstract final class ColumnWidths {
  /// `txt`, `jpeg`, `markdown`.
  static const double extension = 64;

  /// `123.4 MB`, or the folder's word.
  static const double size = 84;

  /// A date column at least; the longest date the locale writes decides
  /// ([dateColumnWidth]).
  static const double dateMin = 96;

  /// `rwxr-xr-x` in the monospace face.
  static const double permissions = 92;

  /// A user or group name.
  static const double owner = 88;

  /// Room a column keeps beyond its longest text.
  static const double padding = AppSpacing.sm;

  /// The name column at least: the data columns give way to it together
  /// in a narrow panel, down to half their width.
  static const double nameMin = 160;

  /// The name column of a flat view at least: the name and its folder.
  static const double flatNameMin = 320;
}

/// The width a column takes at the text size in [context]: a date column
/// as wide as the longest date the locale writes, so no date is cut.
double columnWidth(BuildContext context, ListColumn column) {
  final scale = MediaQuery.textScalerOf(context).scale(1);
  final double base = switch (column) {
    ListColumn.name => 0,
    ListColumn.extension => ColumnWidths.extension,
    ListColumn.size => ColumnWidths.size,
    ListColumn.modified ||
    ListColumn.created ||
    ListColumn.added ||
    ListColumn.accessed => dateColumnWidth(context) / scale,
    ListColumn.permissions => ColumnWidths.permissions,
    ListColumn.owner || ListColumn.group => ColumnWidths.owner,
  };
  return (base * scale).roundToDouble();
}

/// The width of a date column: a date of another year with two-digit day
/// and month, measured in the column's face, with the column's padding.
double dateColumnWidth(BuildContext context) {
  final l10n = context.l10n;
  final now = DateTime(2026, 6, 15, 12, 30);
  final sample = l10n.dateTime(DateTime(2025, 12, 28, 23, 58), now: now);
  final painter = TextPainter(
    text: TextSpan(text: sample, style: columnStyle(context)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  try {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return (painter.width + ColumnWidths.padding * scale).clamp(
      ColumnWidths.dateMin * scale,
      double.infinity,
    );
  } finally {
    painter.dispose();
  }
}

/// Technical metadata uses the platform monospace face; names, extensions
/// and account names keep the system face. Measurements use this same style.
TextStyle columnStyle(BuildContext context, {ListColumn? column}) {
  final base = switch (column) {
    ListColumn.name ||
    ListColumn.extension ||
    ListColumn.owner ||
    ListColumn.group => context.text.bodyMedium!,
    _ => context.mono,
  };
  return base.copyWith(
    color: context.appColors.textMuted,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

bool columnRightAligned(ListColumn column) => column == ListColumn.size;
