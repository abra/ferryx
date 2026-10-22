import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';

import 'file_icon.dart';

/// How a row is drawn: under the cursor, selected, or plain, in the panel
/// the keys are in or in the other one.
///
/// Orthodox managers tell the cursor from the selection: the cursor row
/// takes the emphasized selection (the accent with light text), selected
/// rows a tint of it. Where the keys are not (the other panel, a window
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

  /// The cursor row in the active panel: light text on the accent.
  bool get emphasized => cursor && active;

  Color? background(AppColorsExt colors) {
    if (cursor) return active ? colors.selectionAccent : colors.selectionMuted;
    if (selected) return active ? colors.accentSoft : colors.selectionMuted;
    return null;
  }

  /// The name's colour; [ink] is the row's own when nothing overrides it.
  Color foreground(BuildContext context, {Color? ink}) {
    final colors = context.appColors;
    if (emphasized) return colors.onAccent;
    if (selected && active) return colors.link;
    if (dimmed) return colors.textFaint;
    return ink ?? context.colors.onSurface;
  }

  /// The colour of a row's details (size, date) and of its check mark's
  /// companions.
  Color secondary(AppColorsExt colors) {
    if (emphasized) return colors.onAccentMuted;
    if (dimmed) return colors.textFaint;
    return colors.textMuted;
  }

  /// The selection's check mark.
  Color checkMark(AppColorsExt colors) {
    if (emphasized) return colors.onAccent;
    return active ? colors.accent : colors.textMuted;
  }
}

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
    final iconColor = look.emphasized ? colors.onAccent : tint;
    final base = context.text.bodyMedium!.copyWith(
      color: look.foreground(context),
      fontStyle: entry.isSymlink ? FontStyle.italic : null,
    );
    final style = entry.isHidden && !look.cursor
        ? base.copyWith(color: colors.textFaint)
        : base;
    final match = look.match;
    return Row(
      children: [
        Icon(icon, size: iconSize, color: iconColor),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          // A long name loses its middle, so the extension stays in view;
          // with a search on, the underlined letters stay instead.
          child:
              field ??
              (match == null || match.isEmpty
                  ? AppMiddleEllipsis(
                      entry.isParent ? '..' : entry.name,
                      style: style,
                    )
                  : Text.rich(
                      _spans(entry.name, match, style, colors),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
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
      decorationColor: look.emphasized ? colors.onAccent : colors.accent,
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

/// A folder with nothing to show, in either view.
class EmptyRows extends StatelessWidget {
  const EmptyRows({super.key});

  @override
  Widget build(BuildContext context) => Center(
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

/// The face of a column's text: the body in the muted colour, figures of
/// one width so sizes and dates line up (Finder sets them in the name's
/// size); permissions in the monospace face.
TextStyle columnStyle(BuildContext context, {ListColumn? column}) {
  final base = column == ListColumn.permissions
      ? context.mono
      : context.text.bodyMedium!;
  return base.copyWith(
    color: context.appColors.textMuted,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

bool columnRightAligned(ListColumn column) => column == ListColumn.size;
