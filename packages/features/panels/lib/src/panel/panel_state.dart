import 'package:domain_models/domain_models.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import 'flat_view.dart';
import 'panel_side.dart';

/// The rows own these sums: a selection remembered for `gv` must not keep
/// an old listing alive. Both keys are weak; cursor moves reuse the sum.
final _selectedBytes = Expando<Expando<({Map<String, int> sizes, int bytes})>>(
  'selected bytes',
);

/// One tab of a panel: where it is, what it shows, where its cursor and
/// selection are.
@immutable
class PanelTabState extends Equatable {
  const PanelTabState({
    required this.id,
    required this.location,
    required this.sort,
    this.listing,
    this.loading = false,
    this.error,
    this.rows = const [],
    this.cursor = -1,
    this.selected = const {},
    this.history = const [],
    this.historyIndex = -1,
    this.quickSearch = '',
    this.matches = const {},
    this.layoutIndex = 0,
    this.folderSizes = const {},
    this.renaming,
    this.rangeSelecting,
    this.pendingFocusName,
    this.scrollRequest = 0,
    this.scrollAlign = ScrollAlign.reveal,
    this.visualAnchor,
    this.visualBase = const {},
    this.searching = false,
    this.lastSelection = const {},
    this.renameCaret = RenameCaret.stem,
    this.passwordLocation,
    this.flat,
  });

  /// The listing id in the core, unique across both panels.
  final String id;
  final Location location;
  final SortOptions sort;
  final Listing? listing;
  final bool loading;

  /// The last failure to read [location]; the previous listing stays.
  final FerryxException? error;

  /// The rows shown: the listing's entries, less the ones a quick search
  /// hides, with the calculated folder sizes merged in.
  final List<FileEntry> rows;

  /// The index of the cursor in [rows]; -1 when there are no rows.
  final int cursor;

  /// Selected rows by their keys (names; under a flat view's root, paths);
  /// the `..` row is never among them.
  final Set<String> selected;
  final List<Location> history;
  final int historyIndex;
  final String quickSearch;

  /// Character ranges to underline, by name, while a quick search is on.
  final Map<String, List<(int, int)>> matches;
  final int layoutIndex;

  /// Sizes calculated for folders of this listing, by name.
  final Map<String, int> folderSizes;

  /// The row being renamed in place.
  final int? renaming;

  /// While Shift is held with the arrows: whether the run selects or
  /// deselects, decided by the first row it touched.
  final bool? rangeSelecting;

  /// The name to put the cursor on once the listing loads.
  final String? pendingFocusName;

  /// Bumped when the view should scroll the cursor into view.
  final int scrollRequest;

  /// Where the cursor's row lands when the view scrolls for it: into view
  /// as little as it takes, or at the top, the middle or the bottom (Vim's
  /// `zt`, `zz`, `zb`).
  final ScrollAlign scrollAlign;

  /// Visual mode (Vim): the row the selection grew from; the rows from it
  /// to the cursor are selected on top of [visualBase].
  final int? visualAnchor;

  /// What was selected before Visual mode began.
  final Set<String> visualBase;

  /// The `/` prompt is open: typed letters go to the quick search until
  /// Return keeps it or Esc clears it.
  final bool searching;

  /// The selection before it was last cleared, for `gv`.
  final Set<String> lastSelection;

  /// Where the caret goes in the rename field.
  final RenameCaret renameCaret;

  /// An archive's folder that could not open without its password: the
  /// window asks for it and opens the folder again.
  final Location? passwordLocation;

  /// The tab shows its folder's whole subtree as one list; `null` for the
  /// folder itself.
  final FlatView? flat;

  FileEntry? get focused =>
      cursor >= 0 && cursor < rows.length ? rows[cursor] : null;

  /// The rows an action works on: the selection in row order, else the
  /// focused item unless it is `..`.
  List<FileEntry> get targets {
    if (selected.isNotEmpty) {
      return [
        for (final row in rows)
          if (selected.contains(row.key)) row,
      ];
    }
    final focused = this.focused;
    return focused == null || focused.isParent ? const [] : [focused];
  }

  int get selectedBytes {
    if (selected.isEmpty) return 0;
    final sums = _selectedBytes[rows] ??= Expando('selection');
    final memo = sums[selected];
    if (memo != null && identical(memo.sizes, folderSizes)) {
      return memo.bytes;
    }
    final bytes = rows
        .where((r) => selected.contains(r.key))
        .fold(0, (sum, r) => sum + (r.size ?? folderSizes[r.name] ?? 0));
    sums[selected] = (sizes: folderSizes, bytes: bytes);
    return bytes;
  }

  /// Visual mode is on.
  bool get visual => visualAnchor != null;

  bool get canGoBack => historyIndex > 0;

  bool get canGoForward => historyIndex < history.length - 1;

  /// The row with [key] (its name, or its path under a flat view's root).
  int indexOfName(String key) => rows.indexWhere((r) => r.key == key);

  bool get isFlat => flat != null;

  /// Where [entry] is: under the tab's folder, in its own folder of a
  /// flat view.
  Location locationOf(FileEntry entry) => location.join(entry.key);

  PanelTabState copyWith({
    Location? location,
    SortOptions? sort,
    Listing? listing,
    bool clearListing = false,
    bool? loading,
    FerryxException? error,
    bool clearError = false,
    List<FileEntry>? rows,
    int? cursor,
    Set<String>? selected,
    List<Location>? history,
    int? historyIndex,
    String? quickSearch,
    Map<String, List<(int, int)>>? matches,
    int? layoutIndex,
    Map<String, int>? folderSizes,
    int? renaming,
    bool clearRenaming = false,
    bool? rangeSelecting,
    bool clearRange = false,
    String? pendingFocusName,
    bool clearPendingFocus = false,
    int? scrollRequest,
    ScrollAlign? scrollAlign,
    int? visualAnchor,
    bool clearVisual = false,
    Set<String>? visualBase,
    bool? searching,
    Set<String>? lastSelection,
    RenameCaret? renameCaret,
    Location? passwordLocation,
    bool clearPasswordLocation = false,
    FlatView? flat,
    bool clearFlat = false,
  }) => PanelTabState(
    id: id,
    location: location ?? this.location,
    sort: sort ?? this.sort,
    listing: clearListing ? null : (listing ?? this.listing),
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    rows: rows ?? this.rows,
    cursor: cursor ?? this.cursor,
    selected: selected ?? this.selected,
    history: history ?? this.history,
    historyIndex: historyIndex ?? this.historyIndex,
    quickSearch: quickSearch ?? this.quickSearch,
    matches: matches ?? this.matches,
    layoutIndex: layoutIndex ?? this.layoutIndex,
    folderSizes: folderSizes ?? this.folderSizes,
    renaming: clearRenaming ? null : (renaming ?? this.renaming),
    rangeSelecting: clearRange ? null : (rangeSelecting ?? this.rangeSelecting),
    pendingFocusName: clearPendingFocus
        ? null
        : (pendingFocusName ?? this.pendingFocusName),
    scrollRequest: scrollRequest ?? this.scrollRequest,
    scrollAlign: scrollAlign ?? this.scrollAlign,
    visualAnchor: clearVisual ? null : (visualAnchor ?? this.visualAnchor),
    visualBase: clearVisual ? const {} : (visualBase ?? this.visualBase),
    searching: searching ?? this.searching,
    lastSelection: lastSelection ?? this.lastSelection,
    renameCaret: renameCaret ?? this.renameCaret,
    passwordLocation: clearPasswordLocation
        ? null
        : (passwordLocation ?? this.passwordLocation),
    flat: clearFlat ? null : (flat ?? this.flat),
  );

  @override
  List<Object?> get props => [
    id,
    location,
    sort,
    listing,
    loading,
    error,
    rows,
    cursor,
    _Hashed(selected),
    history,
    historyIndex,
    quickSearch,
    matches,
    layoutIndex,
    folderSizes,
    renaming,
    rangeSelecting,
    pendingFocusName,
    scrollRequest,
    scrollAlign,
    visualAnchor,
    _Hashed(visualBase),
    searching,
    _Hashed(lastSelection),
    renameCaret,
    passwordLocation,
    flat,
  ];
}

/// A set compared by hashing, in linear time: Equatable compares two sets
/// element against element, which a selection of thousands of rows turns
/// into seconds on every emit that rebuilds it.
@immutable
class _Hashed {
  const _Hashed(this.set);

  final Set<String> set;

  @override
  bool operator ==(Object other) =>
      other is _Hashed &&
      (identical(set, other.set) ||
          set.length == other.set.length && set.containsAll(other.set));

  @override
  int get hashCode => Object.hashAllUnordered(set);
}

/// A panel: its tabs and which one shows.
@immutable
class PanelState extends Equatable {
  const PanelState({
    required this.side,
    this.tabs = const [],
    this.activeIndex = 0,
    this.closedTabs = const [],
    this.servers = const {},
  });

  final PanelSide side;
  final List<PanelTabState> tabs;
  final int activeIndex;

  /// Locations of tabs closed lately, the last closed first.
  final List<Location> closedTabs;

  // ─── Network ───

  /// The servers open, by key, with their state.
  final Map<String, ServerStatus> servers;

  /// The state of the server [tab] is on; `null` for a tab elsewhere.
  ServerState? serverStateOf(PanelTabState tab) {
    final server = tab.location.server;
    if (server == null) return null;
    return servers[server]?.state ?? ServerState.closed;
  }

  PanelTabState? get active =>
      activeIndex >= 0 && activeIndex < tabs.length ? tabs[activeIndex] : null;

  PanelState copyWith({
    List<PanelTabState>? tabs,
    int? activeIndex,
    List<Location>? closedTabs,
    Map<String, ServerStatus>? servers,
  }) => PanelState(
    side: side,
    tabs: tabs ?? this.tabs,
    activeIndex: activeIndex ?? this.activeIndex,
    closedTabs: closedTabs ?? this.closedTabs,
    servers: servers ?? this.servers,
  );

  /// The state with the active tab replaced by [tab].
  PanelState withActive(PanelTabState tab) => withTab(activeIndex, tab);

  PanelState withTab(int index, PanelTabState tab) {
    if (index < 0 || index >= tabs.length) return this;
    final next = [...tabs];
    next[index] = tab;
    return copyWith(tabs: next);
  }

  @override
  List<Object?> get props => [side, tabs, activeIndex, closedTabs, servers];
}

/// What the view knows about its size, for the page and column keys.
@immutable
class PanelGeometry extends Equatable {
  const PanelGeometry({
    this.rowsPerPage = 20,
    this.rowsPerColumn = 1,
    this.firstVisibleRow = 0,
  });

  final int rowsPerPage;

  /// Rows in one column of brief mode; 1 in list mode, where ← and →
  /// have other meanings.
  final int rowsPerColumn;

  /// The first row in view, for `H`, `M` and `L`.
  final int firstVisibleRow;

  @override
  List<Object?> get props => [rowsPerPage, rowsPerColumn, firstVisibleRow];
}

/// How the view scrolls for the cursor.
enum ScrollAlign { reveal, top, center, bottom }

/// Where the caret starts when a name is renamed in place.
enum RenameCaret {
  /// The stem selected, as Finder has it.
  stem,

  /// At the start of the name (Vim's `I`).
  start,

  /// At the end of the name (Vim's `A`).
  end,
}
