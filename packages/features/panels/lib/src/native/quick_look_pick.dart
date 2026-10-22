import 'dart:math' as math;

import 'package:domain_models/domain_models.dart';
import 'package:flutter/foundation.dart';

import '../panel/panel_state.dart';

/// What Quick Look shows for a tab, Finder's way: the targets when several
/// rows are selected (at the cursor's place among them, else the first),
/// else the folder's items without `..`, at the cursor's. Inside an
/// archive only files can be taken out to look at, and the folder's items
/// are not all taken out: the focused file alone.
@immutable
class QuickLookPick {
  const QuickLookPick(this.entries, this.index, {this.fromSelection = false});

  static const empty = QuickLookPick([], 0);

  final List<FileEntry> entries;

  /// The one shown first, an index into [entries].
  final int index;

  /// [entries] are the selection's, not the folder's.
  final bool fromSelection;

  bool get isEmpty => entries.isEmpty;
}

QuickLookPick quickLookPick(PanelTabState tab) {
  final focused = tab.focused;
  final native = tab.location.isNative;
  if (tab.selected.length > 1) {
    final targets = tab.targets;
    final entries = native
        ? targets
        : [
            for (final entry in targets)
              if (!entry.isDir) entry,
          ];
    return QuickLookPick(
      entries,
      math.max(0, quickLookIndexIn(entries, focused)),
      fromSelection: true,
    );
  }
  if (!native) {
    return focused == null || focused.isDir || focused.isParent
        ? QuickLookPick.empty
        : QuickLookPick([focused], 0);
  }
  final skip = tab.rows.firstOrNull?.isParent == true ? 1 : 0;
  final entries = skip == 0 ? tab.rows : tab.rows.sublist(skip);
  return QuickLookPick(entries, quickLookFolderIndex(tab));
}

/// The cursor's place among a folder's items without `..`: computed from
/// the cursor alone, so following the cursor costs nothing per row.
int quickLookFolderIndex(PanelTabState tab) {
  final skip = tab.rows.firstOrNull?.isParent == true ? 1 : 0;
  return math.max(0, tab.cursor - skip);
}

/// Where [focused] is in [entries], or -1.
int quickLookIndexIn(List<FileEntry> entries, FileEntry? focused) =>
    focused == null ? -1 : entries.indexWhere((e) => e.key == focused.key);
