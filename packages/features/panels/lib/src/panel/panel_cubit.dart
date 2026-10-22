import 'dart:async';
import 'dart:math' as math;

import 'package:domain_models/domain_models.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:monitoring/monitoring.dart';
import 'package:operations_service/operations_service.dart';
import 'package:preferences_service/preferences_service.dart';

import 'panel_side.dart';
import 'panel_state.dart';
import 'quick_search.dart';
import 'saved_panel.dart';

/// Where Return leads when a row is not a folder: the workspace opens
/// the file with the desktop, or runs it.
class OpenFileRequest {
  const OpenFileRequest(this.entry, this.location);

  final FileEntry entry;

  /// The row's location (a file on disk, or a member of an archive).
  final Location location;
}

/// One panel: its tabs, each with a listing watched by the core, a
/// cursor and a selection kept apart, as orthodox managers have them.
class PanelCubit extends Cubit<PanelState> {
  PanelCubit({
    required this.side,
    required FileRepository files,
    required OperationsService operations,
    required PreferencesService preferences,
    required this.logger,
  }) : _files = files,
       _operations = operations,
       _preferences = preferences,
       super(PanelState(side: side)) {
    _changes = files.directoryChanges.listen(_onDirectoryChanged);
    _progress = operations.progress.listen(_onProgress);
    _prefs = preferences.stream.listen(_onPreferences);
    _lastPrefs = preferences.current;
  }

  final PanelSide side;
  final FileRepository _files;
  final OperationsService _operations;
  final PreferencesService _preferences;
  final Logger logger;
  StreamSubscription<String>? _changes;
  StreamSubscription<OperationProgress>? _progress;
  StreamSubscription<Preferences>? _prefs;
  Preferences _lastPrefs = const Preferences();
  int _nextTabNumber = 1;

  /// Rows per page and per column, as the view last measured them.
  PanelGeometry geometry = const PanelGeometry();

  /// Operations started here whose folder sizes go into the tabs.
  final _sizeOperations = <int>{};

  Preferences get _p => _preferences.current;

  ListingOptions _options(SortOptions sort) => ListingOptions(
    showHidden: _p.showHiddenFiles,
    showParent: _p.showParentEntry,
    sort: sort,
  );

  // ─── Start and persistence ───

  /// Opens the saved tabs, or one at [fallback].
  Future<void> start(SavedPanel? saved, Location fallback) async {
    // A first run starts in the Full layout: a list with its columns.
    final tabs = saved?.tabs ?? [SavedTab(location: fallback, layoutIndex: 2)];
    final states = <PanelTabState>[];
    for (final tab in tabs) {
      states.add(
        PanelTabState(
          id: _newTabId(),
          location: tab.location,
          sort: tab.sort,
          layoutIndex: tab.layoutIndex,
          loading: true,
        ),
      );
    }
    emit(
      state.copyWith(
        tabs: states,
        activeIndex: (saved?.activeIndex ?? 0).clamp(0, states.length - 1),
        closedTabs: saved?.closedTabs ?? const [],
      ),
    );
    for (var i = 0; i < states.length; i++) {
      await _load(i, states[i].location, pushHistory: true, fallback: fallback);
    }
  }

  SavedPanel saved() => SavedPanel(
    tabs: [
      for (final tab in state.tabs)
        SavedTab(
          location: tab.location,
          sort: tab.sort,
          layoutIndex: tab.layoutIndex,
        ),
    ],
    activeIndex: state.activeIndex,
    closedTabs: state.closedTabs.take(20).toList(),
  );

  String _newTabId() => '${side.name}-${_nextTabNumber++}';

  // ─── Loading ───

  /// Reads [location] into the tab at [index]. A folder that cannot be
  /// read leaves the tab where it was and records the error; a tab with
  /// nothing yet falls back to [fallback], then to the root.
  Future<void> _load(
    int index,
    Location location, {
    required bool pushHistory,
    String? focusName,
    Location? fallback,
  }) async {
    final tab = state.tabs.elementAtOrNull(index);
    if (tab == null) return;
    emit(
      state.withTab(
        index,
        tab.copyWith(
          loading: true,
          clearError: true,
          pendingFocusName: focusName,
        ),
      ),
    );
    try {
      final listing = await _files.openListing(
        tab.id,
        location,
        _options(tab.sort),
      );
      final current = state.tabs.elementAtOrNull(index);
      if (current == null || current.id != tab.id) return;
      var history = current.history;
      var historyIndex = current.historyIndex;
      if (pushHistory) {
        history = [...history.take(historyIndex + 1), location];
        historyIndex = history.length - 1;
      }
      emit(
        state.withTab(
          index,
          _withListing(
            current.copyWith(
              location: location,
              listing: listing,
              loading: false,
              clearError: true,
              history: history,
              historyIndex: historyIndex,
              selected: const {},
              quickSearch: '',
              matches: const {},
              folderSizes: const {},
              clearRenaming: true,
              clearRange: true,
              clearVisual: true,
              searching: false,
            ),
            focusName: focusName ?? current.pendingFocusName,
          ).copyWith(clearPendingFocus: true),
        ),
      );
    } on FerryxException catch (error, stackTrace) {
      logger.warn(
        'cannot open ${location.display}',
        error: error,
        stackTrace: stackTrace,
      );
      final current = state.tabs.elementAtOrNull(index);
      if (current == null || current.id != tab.id) return;
      if (current.listing == null) {
        // Nothing to fall back on in the tab: try the fallback, then the
        // root, which always reads.
        final next = fallback != null && fallback != location
            ? fallback
            : location.isNative && location.path != '/'
            ? const Location.native('/')
            : null;
        emit(
          state.withTab(
            index,
            current.copyWith(
              loading: false,
              error: error,
              clearPendingFocus: true,
            ),
          ),
        );
        if (next != null) await _load(index, next, pushHistory: pushHistory);
        return;
      }
      emit(
        state.withTab(
          index,
          current.copyWith(
            loading: false,
            error: error,
            clearPendingFocus: true,
          ),
        ),
      );
    }
  }

  /// The tab with its rows rebuilt from its listing: quick search applied,
  /// folder sizes merged, the cursor kept on its name or put on
  /// [focusName].
  PanelTabState _withListing(PanelTabState tab, {String? focusName}) {
    final entries = tab.listing?.entries ?? const [];
    final where = _p.quickSearchWhere;
    final onlyMatching = _p.quickSearchOnlyMatching;
    final matches = <String, List<(int, int)>>{};
    final rows = <FileEntry>[];
    for (final entry in entries) {
      var row = entry;
      final size = tab.folderSizes[entry.name];
      if (size != null && entry.isDir && entry.size == null) {
        row = entry.copyWith(size: size);
      }
      if (tab.quickSearch.isNotEmpty && !entry.isParent) {
        final ranges = quickMatch(tab.quickSearch, entry.name, where);
        if (ranges == null) {
          if (onlyMatching) continue;
        } else {
          matches[entry.name] = ranges;
        }
      }
      rows.add(row);
    }
    final wanted = focusName ?? tab.focused?.name;
    var cursor = wanted == null ? -1 : rows.indexWhere((r) => r.name == wanted);
    if (cursor < 0) {
      cursor = rows.isEmpty
          ? -1
          : math.min(math.max(tab.cursor, 0), rows.length - 1);
    }
    final names = rows.map((r) => r.name).toSet();
    return tab.copyWith(
      rows: rows,
      matches: matches,
      cursor: cursor,
      selected: tab.selected.where(names.contains).toSet(),
      scrollRequest: tab.scrollRequest + 1,
    );
  }

  Future<void> refresh() async {
    final index = state.activeIndex;
    await _refreshTab(index);
  }

  Future<void> _refreshTab(int index) async {
    final tab = state.tabs.elementAtOrNull(index);
    if (tab == null || tab.loading) return;
    try {
      final listing = await _files.refreshListing(tab.id);
      final current = state.tabs.elementAtOrNull(index);
      if (current == null || current.id != tab.id) return;
      emit(
        state.withTab(
          index,
          _withListing(current.copyWith(listing: listing, clearError: true)),
        ),
      );
    } on FerryxException catch (error) {
      final gone =
          error.kind == FerryxErrorKind.notFound ||
          error.kind == FerryxErrorKind.notADirectory;
      final parent = tab.location.parent;
      if (gone && parent != null) {
        // The folder went away: climb to the nearest one still there.
        await _load(index, parent, pushHistory: true);
        return;
      }
      final current = state.tabs.elementAtOrNull(index);
      if (current != null && current.id == tab.id) {
        emit(state.withTab(index, current.copyWith(error: error)));
      }
    }
  }

  void _onDirectoryChanged(String listingId) {
    final index = state.tabs.indexWhere((t) => t.id == listingId);
    if (index >= 0) unawaited(_refreshTab(index));
  }

  Future<void> _onPreferences(Preferences next) async {
    final before = _lastPrefs;
    _lastPrefs = next;
    final listingChanged =
        before.showHiddenFiles != next.showHiddenFiles ||
        before.showParentEntry != next.showParentEntry ||
        before.quickSearchWhere != next.quickSearchWhere ||
        before.quickSearchOnlyMatching != next.quickSearchOnlyMatching;
    if (!listingChanged) return;
    for (var i = 0; i < state.tabs.length; i++) {
      await _resortTab(i, state.tabs[i].sort);
    }
  }

  Future<void> _resortTab(int index, SortOptions sort) async {
    final tab = state.tabs.elementAtOrNull(index);
    if (tab == null || tab.listing == null) return;
    try {
      final listing = await _files.resortListing(tab.id, _options(sort));
      final current = state.tabs.elementAtOrNull(index);
      if (current == null || current.id != tab.id) return;
      emit(
        state.withTab(
          index,
          _withListing(current.copyWith(sort: sort, listing: listing)),
        ),
      );
    } on FerryxException catch (error) {
      logger.warn('resort failed', error: error);
    }
  }

  // ─── Navigation ───

  Future<void> open(Location location, {String? focusName}) => _load(
    state.activeIndex,
    location,
    pushHistory: true,
    focusName: focusName,
  );

  /// Return on the cursor: into a folder or an archive, up on `..`;
  /// answers the file to open otherwise.
  Future<OpenFileRequest?> enter() async {
    final tab = state.active;
    final entry = tab?.focused;
    if (tab == null || entry == null) return null;
    if (entry.isParent) {
      await goParent();
      return null;
    }
    if (entry.isDir) {
      await open(tab.location.join(entry.name));
      return null;
    }
    final location = tab.location.join(entry.name);
    if (location.isNative && _files.isArchive(entry.path)) {
      await open(Location.inArchive(archive: entry.path));
      return null;
    }
    return OpenFileRequest(entry, location);
  }

  /// ⌘↓: into the focused item even when its extension does not say it is
  /// an archive.
  Future<OpenFileRequest?> goInto() async {
    final tab = state.active;
    final entry = tab?.focused;
    if (tab == null || entry == null || entry.isParent) return null;
    if (entry.isDir) {
      await open(tab.location.join(entry.name));
      return null;
    }
    if (tab.location.isNative) {
      await open(Location.inArchive(archive: entry.path));
      return null;
    }
    return OpenFileRequest(entry, tab.location.join(entry.name));
  }

  Future<void> goParent() async {
    final tab = state.active;
    final parent = tab?.location.parent;
    if (tab == null || parent == null) return;
    await open(parent, focusName: tab.location.name);
  }

  Future<void> goBack() => _goHistory(-1);

  Future<void> goForward() => _goHistory(1);

  Future<void> _goHistory(int step) async {
    final index = state.activeIndex;
    final tab = state.active;
    if (tab == null) return;
    final target = tab.historyIndex + step;
    if (target < 0 || target >= tab.history.length) return;
    emit(state.withActive(tab.copyWith(historyIndex: target)));
    await _load(index, tab.history[target], pushHistory: false);
  }

  /// Follows the focused symlink to where it points.
  Future<void> followSymlink() async {
    final tab = state.active;
    final entry = tab?.focused;
    if (tab == null ||
        entry == null ||
        !entry.isSymlink ||
        !tab.location.isNative) {
      return;
    }
    try {
      final resolved = await _files.resolvePath(entry.path);
      final slash = resolved.lastIndexOf('/');
      final parent = slash <= 0 ? '/' : resolved.substring(0, slash);
      await open(
        Location.native(parent),
        focusName: resolved.substring(slash + 1),
      );
    } on FerryxException catch (error) {
      logger.warn('cannot follow ${entry.path}', error: error);
    }
  }

  // ─── Sorting and layout ───

  Future<void> setSort(SortOptions sort) => _resortTab(state.activeIndex, sort);

  Future<void> toggleSortField(SortField field) async {
    final tab = state.active;
    if (tab == null) return;
    await setSort(tab.sort.toggled(field));
  }

  void setLayout(int index) {
    final tab = state.active;
    if (tab == null) return;
    emit(state.withActive(tab.copyWith(layoutIndex: index)));
  }

  // ─── Cursor and selection ───

  void _emitActive(PanelTabState tab) => emit(state.withActive(tab));

  /// Puts the cursor on [index] (clamped). With [selecting], the rows from
  /// the old cursor up to the new one are selected or deselected, as the
  /// first row of the run decided.
  void moveCursorTo(int index, {bool selecting = false, bool scroll = true}) {
    final tab = state.active;
    if (tab == null || tab.rows.isEmpty) return;
    final target = index.clamp(0, tab.rows.length - 1);
    var next = tab.copyWith(
      cursor: target,
      scrollRequest: scroll ? tab.scrollRequest + 1 : null,
      scrollAlign: ScrollAlign.reveal,
      clearRenaming: true,
    );
    final anchor = tab.visualAnchor;
    if (anchor != null) {
      // Visual mode: the rows between the anchor and the cursor are the
      // selection, over what was selected before.
      final selected = {...tab.visualBase};
      final from = anchor.clamp(0, tab.rows.length - 1);
      final step = target >= from ? 1 : -1;
      for (var i = from; ; i += step) {
        _apply(selected, tab.rows[i], true);
        if (i == target) break;
      }
      _emitActive(next.copyWith(selected: selected, clearRange: true));
      return;
    }
    if (!selecting) {
      _emitActive(next.copyWith(clearRange: true));
      return;
    }
    final from = tab.cursor < 0 ? target : tab.cursor;
    final focused = tab.focused;
    final mode =
        tab.rangeSelecting ??
        (focused == null || !tab.selected.contains(focused.name));
    final selected = {...tab.selected};
    if (from != target) {
      final step = target > from ? 1 : -1;
      for (var i = from; i != target; i += step) {
        _apply(selected, tab.rows[i], mode);
      }
    } else {
      _apply(selected, tab.rows[from], mode);
    }
    next = next.copyWith(selected: selected, rangeSelecting: mode);
    _emitActive(next);
  }

  void _apply(Set<String> selected, FileEntry row, bool select) {
    if (row.isParent) return;
    if (select) {
      selected.add(row.name);
    } else {
      selected.remove(row.name);
    }
  }

  void moveCursor(int delta, {bool selecting = false}) {
    final tab = state.active;
    if (tab == null) return;
    moveCursorTo(math.max(tab.cursor, 0) + delta, selecting: selecting);
  }

  void moveFirst({bool selecting = false}) =>
      moveCursorTo(0, selecting: selecting);

  void moveLast({bool selecting = false}) {
    final tab = state.active;
    if (tab == null) return;
    moveCursorTo(tab.rows.length - 1, selecting: selecting);
  }

  void movePage(int direction, {bool selecting = false}) => moveCursor(
    direction * math.max(geometry.rowsPerPage, 1),
    selecting: selecting,
  );

  /// ← and → in brief mode step by a column; in list mode they do
  /// nothing here (the view may bind them to other things).
  void moveColumn(int direction, {bool selecting = false}) {
    if (geometry.rowsPerColumn <= 1) return;
    moveCursor(direction * geometry.rowsPerColumn, selecting: selecting);
  }

  /// A click: the cursor moves; with the primary modifier the row's
  /// selection flips; with Shift the rows between the cursor and the
  /// click take the state of the first.
  void clickRow(int index, {bool toggle = false, bool range = false}) {
    final tab = state.active;
    if (tab == null || index < 0 || index >= tab.rows.length) return;
    if (toggle) {
      toggleSelectionAt(index);
      moveCursorTo(index, scroll: false);
      return;
    }
    if (range) {
      moveCursorTo(index, selecting: true, scroll: false);
      // The clicked row joins the run too, as Finder's Shift-click does.
      final after = state.active;
      if (after != null && after.rangeSelecting != null) {
        final selected = {...after.selected};
        _apply(selected, after.rows[index], after.rangeSelecting!);
        _emitActive(after.copyWith(selected: selected, clearRange: true));
      }
      return;
    }
    moveCursorTo(index, scroll: false);
  }

  void toggleSelectionAt(int index) {
    final tab = state.active;
    if (tab == null || index < 0 || index >= tab.rows.length) return;
    final row = tab.rows[index];
    if (row.isParent) return;
    final selected = {...tab.selected};
    if (!selected.remove(row.name)) selected.add(row.name);
    _emitActive(tab.copyWith(selected: selected, clearRange: true));
  }

  void toggleSelection() {
    final tab = state.active;
    if (tab != null) toggleSelectionAt(tab.cursor);
  }

  void toggleSelectionAndMoveDown() {
    final tab = state.active;
    if (tab == null) return;
    toggleSelectionAt(tab.cursor);
    moveCursor(1);
  }

  void selectAll() => _setSelection((row) => true);

  void deselectAll() => _setSelection((row) => false);

  void invertSelection() {
    final tab = state.active;
    if (tab == null) return;
    _setSelection((row) => !tab.selected.contains(row.name));
  }

  /// Selects ([select]) or deselects the rows whose name [matches].
  void selectWhere(
    bool Function(FileEntry row) matches, {
    required bool select,
  }) {
    final tab = state.active;
    if (tab == null) return;
    _setSelection(
      (row) => matches(row) ? select : tab.selected.contains(row.name),
    );
  }

  /// Selects exactly the rows named in [names] (Compare Folders). A quick
  /// search ends first, so that no named row stays hidden by it.
  void selectOnly(Set<String> names) {
    if (state.active?.quickSearch.isNotEmpty ?? false) clearQuickSearch();
    _setSelection((row) => names.contains(row.name));
  }

  void selectByExtension({required bool select}) {
    final tab = state.active;
    final focused = tab?.focused;
    if (tab == null || focused == null || focused.isParent) return;
    final extension = focused.extension.toLowerCase();
    selectWhere(
      (row) => !row.isDir && row.extension.toLowerCase() == extension,
      select: select,
    );
  }

  void _setSelection(bool Function(FileEntry row) selected) {
    final tab = state.active;
    if (tab == null) return;
    final next = {
      for (final row in tab.rows)
        if (!row.isParent && selected(row)) row.name,
    };
    _emitActive(
      tab.copyWith(
        selected: next,
        clearRange: true,
        clearVisual: true,
        // A selection cleared can come back with `gv`.
        lastSelection: next.isEmpty && tab.selected.isNotEmpty
            ? tab.selected
            : null,
      ),
    );
  }

  // ─── Vim ───

  /// `v`: the selection grows from the cursor as it moves; again, or
  /// Esc, ends it and the selection stays.
  void toggleVisual() {
    final tab = state.active;
    if (tab == null) return;
    if (tab.visual) {
      endVisual();
      return;
    }
    if (tab.cursor < 0) return;
    final selected = {...tab.selected};
    _apply(selected, tab.rows[tab.cursor], true);
    _emitActive(
      tab.copyWith(
        visualAnchor: tab.cursor,
        visualBase: tab.selected,
        selected: selected,
        clearRange: true,
      ),
    );
  }

  void endVisual() {
    final tab = state.active;
    if (tab == null || !tab.visual) return;
    _emitActive(tab.copyWith(clearVisual: true));
  }

  /// `gv`: the selection last cleared comes back.
  void reselectLast() {
    final tab = state.active;
    if (tab == null || tab.lastSelection.isEmpty) return;
    final names = tab.rows.map((r) => r.name).toSet();
    _emitActive(
      tab.copyWith(
        selected: tab.lastSelection.where(names.contains).toSet(),
        clearVisual: true,
      ),
    );
  }

  /// `/`: the quick-search prompt opens; letters filter until Return
  /// keeps the matches ([searchConfirm]) or Esc clears them.
  void searchOpen() {
    final tab = state.active;
    if (tab == null) return;
    _emitActive(tab.copyWith(searching: true, clearVisual: true));
  }

  void searchConfirm() {
    final tab = state.active;
    if (tab == null) return;
    _emitActive(tab.copyWith(searching: false));
  }

  void searchCancel() {
    final tab = state.active;
    if (tab == null) return;
    _emitActive(tab.copyWith(searching: false));
    clearQuickSearch();
  }

  /// `n` / `N`: the next or previous row the quick search matched, round
  /// the ends.
  void searchStep({required bool forward, int count = 1}) {
    final tab = state.active;
    if (tab == null || tab.matches.isEmpty || tab.rows.isEmpty) return;
    var at = tab.cursor;
    for (var n = 0; n < count; n++) {
      final start = at;
      do {
        at = (at + (forward ? 1 : -1) + tab.rows.length) % tab.rows.length;
        if (tab.matches.containsKey(tab.rows[at].name)) break;
      } while (at != start);
    }
    moveCursorTo(at);
  }

  /// `f` / `F`: the next or previous row whose name starts with [char],
  /// case aside; nothing when there is none.
  void findRowStartingWith(
    String char, {
    required bool forward,
    int count = 1,
  }) {
    final tab = state.active;
    if (tab == null || tab.rows.isEmpty) return;
    final wanted = char.toLowerCase();
    var at = tab.cursor;
    for (var n = 0; n < count; n++) {
      final start = at;
      var found = false;
      while (true) {
        at += forward ? 1 : -1;
        if (at < 0 || at >= tab.rows.length) break;
        final row = tab.rows[at];
        if (!row.isParent && row.name.toLowerCase().startsWith(wanted)) {
          found = true;
          break;
        }
      }
      if (!found) {
        at = start;
        break;
      }
    }
    if (at != tab.cursor) moveCursorTo(at);
  }

  /// `H`, `M`, `L`: the top, middle or bottom row in view.
  void moveToScreen(ScrollAlign where, {int count = 1}) {
    final tab = state.active;
    if (tab == null || tab.rows.isEmpty) return;
    final first = geometry.firstVisibleRow.clamp(0, tab.rows.length - 1);
    final last = (first + geometry.rowsPerPage - 1).clamp(
      0,
      tab.rows.length - 1,
    );
    final target = switch (where) {
      ScrollAlign.top => first + count - 1,
      ScrollAlign.bottom => last - count + 1,
      _ => (first + last) ~/ 2,
    };
    moveCursorTo(target.clamp(first, last));
  }

  /// `zz`, `zt`, `zb`: the view scrolls so the cursor's row lands there.
  void scrollCursor(ScrollAlign align) {
    final tab = state.active;
    if (tab == null) return;
    _emitActive(
      tab.copyWith(
        scrollRequest: tab.scrollRequest + 1,
        scrollAlign: align,
      ),
    );
  }

  /// `or`: the same field, the other way.
  Future<void> sortReverse() async {
    final tab = state.active;
    if (tab == null) return;
    await setSort(tab.sort.copyWith(descending: !tab.sort.descending));
  }

  /// Clears the selection after an operation acted on it.
  void clearSelection() => deselectAll();

  // ─── Quick search ───

  void quickSearchType(String text) {
    final tab = state.active;
    if (tab == null) return;
    _setQuickSearch(tab.quickSearch + text);
  }

  void quickSearchBackspace() {
    final tab = state.active;
    if (tab == null || tab.quickSearch.isEmpty) return;
    _setQuickSearch(tab.quickSearch.substring(0, tab.quickSearch.length - 1));
  }

  void clearQuickSearch() => _setQuickSearch('');

  void _setQuickSearch(String query) {
    final tab = state.active;
    if (tab == null) return;
    final next = _withListing(
      tab.copyWith(quickSearch: query),
      focusName: tab.focused?.name,
    );
    // The cursor goes to the first match, when the one under it is none.
    var cursor = next.cursor;
    if (query.isNotEmpty) {
      final focused = next.focused;
      if (focused == null || !next.matches.containsKey(focused.name)) {
        final first = next.rows.indexWhere(
          (r) => next.matches.containsKey(r.name),
        );
        if (first >= 0) cursor = first;
      }
    }
    _emitActive(next.copyWith(cursor: cursor, clearRange: true));
  }

  // ─── Renaming in place ───

  void startRenaming({RenameCaret caret = RenameCaret.stem}) {
    final tab = state.active;
    final focused = tab?.focused;
    if (tab == null ||
        focused == null ||
        focused.isParent ||
        !tab.location.isNative) {
      return;
    }
    _emitActive(
      tab.copyWith(renaming: tab.cursor, renameCaret: caret, clearVisual: true),
    );
  }

  void stopRenaming() {
    final tab = state.active;
    if (tab == null || tab.renaming == null) return;
    _emitActive(tab.copyWith(clearRenaming: true));
  }

  /// Renames the row being renamed; answers the error to show, if any.
  Future<FerryxException?> commitRename(String newName) async {
    final tab = state.active;
    final index = tab?.renaming;
    if (tab == null || index == null || index >= tab.rows.length) return null;
    final row = tab.rows[index];
    _emitActive(tab.copyWith(clearRenaming: true));
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == row.name) return null;
    try {
      await _files.rename(row.path, trimmed);
      final current = state.active;
      if (current != null && current.id == tab.id) {
        _emitActive(current.copyWith(pendingFocusName: trimmed));
        await _refreshTab(state.activeIndex);
        final after = state.active;
        if (after != null) {
          final at = after.indexOfName(trimmed);
          if (at >= 0) moveCursorTo(at);
        }
      }
      return null;
    } on FerryxException catch (error) {
      return error;
    }
  }

  // ─── Folder sizes ───

  /// Calculates the sizes of the folders among [names] (every folder of
  /// the listing when empty).
  Future<void> calcSizes({List<String>? names}) async {
    final tab = state.active;
    if (tab == null || !tab.location.isNative) return;
    final folders = [
      for (final row in tab.rows)
        if (row.isDir && !row.isParent && !row.isSymlink)
          if (names == null || names.contains(row.name)) row.path,
    ];
    if (folders.isEmpty) return;
    final id = await _operations.start(
      OperationRequest(kind: OpKind.calcSizes, sources: folders),
    );
    _sizeOperations.add(id);
  }

  void _onProgress(OperationProgress progress) {
    if (!_sizeOperations.contains(progress.id)) return;
    if (progress.state.isFinished) _sizeOperations.remove(progress.id);
    if (progress.sizes.isEmpty) return;
    for (var i = 0; i < state.tabs.length; i++) {
      final tab = state.tabs[i];
      if (!tab.location.isNative) continue;
      final prefix = tab.location.path.endsWith('/')
          ? tab.location.path
          : '${tab.location.path}/';
      final sizes = {...tab.folderSizes};
      var changed = false;
      for (final size in progress.sizes) {
        if (!size.path.startsWith(prefix)) continue;
        final name = size.path.substring(prefix.length);
        if (name.contains('/')) continue;
        if (sizes[name] != size.bytes) {
          sizes[name] = size.bytes;
          changed = true;
        }
      }
      if (changed) {
        emit(state.withTab(i, _withListing(tab.copyWith(folderSizes: sizes))));
      }
    }
    if (progress.state.isFinished) unawaited(_operations.forget(progress.id));
  }

  // ─── Tabs ───

  Future<void> newTab({Location? location}) async {
    final active = state.active;
    final where = location ?? active?.location ?? const Location.native('/');
    final tab = PanelTabState(
      id: _newTabId(),
      location: where,
      sort: active?.sort ?? _p.defaultSort,
      layoutIndex: active?.layoutIndex ?? 0,
      loading: true,
    );
    final index = state.activeIndex + 1;
    final tabs = [...state.tabs]
      ..insert(index.clamp(0, state.tabs.length), tab);
    emit(
      state.copyWith(tabs: tabs, activeIndex: index.clamp(0, tabs.length - 1)),
    );
    await _load(state.activeIndex, where, pushHistory: true);
  }

  Future<void> closeTab([int? index]) async {
    final at = index ?? state.activeIndex;
    if (state.tabs.length <= 1 || at < 0 || at >= state.tabs.length) return;
    final tab = state.tabs[at];
    final tabs = [...state.tabs]..removeAt(at);
    final active = state.activeIndex > at || state.activeIndex == tabs.length
        ? state.activeIndex - 1
        : state.activeIndex;
    emit(
      state.copyWith(
        tabs: tabs,
        activeIndex: active.clamp(0, tabs.length - 1),
        closedTabs: [tab.location, ...state.closedTabs].take(20).toList(),
      ),
    );
    await _files.closeListing(tab.id);
  }

  Future<void> closeOtherTabs() async {
    final active = state.active;
    if (active == null) return;
    final others = state.tabs.where((t) => t.id != active.id).toList();
    emit(
      state.copyWith(
        tabs: [active],
        activeIndex: 0,
        closedTabs: [
          ...others.map((t) => t.location),
          ...state.closedTabs,
        ].take(20).toList(),
      ),
    );
    for (final tab in others) {
      await _files.closeListing(tab.id);
    }
  }

  Future<void> reopenClosedTab() async {
    if (state.closedTabs.isEmpty) return;
    final location = state.closedTabs.first;
    emit(state.copyWith(closedTabs: state.closedTabs.sublist(1)));
    await newTab(location: location);
  }

  void showTab(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    emit(state.copyWith(activeIndex: index));
  }

  void nextTab() => showTab((state.activeIndex + 1) % state.tabs.length);

  void previousTab() =>
      showTab((state.activeIndex - 1 + state.tabs.length) % state.tabs.length);

  void moveTab(int from, int to) {
    if (from == to || from < 0 || from >= state.tabs.length) return;
    final tabs = [...state.tabs];
    final tab = tabs.removeAt(from);
    final target = to.clamp(0, tabs.length);
    tabs.insert(target, tab);
    final activeId = state.active?.id;
    emit(
      state.copyWith(
        tabs: tabs,
        activeIndex: tabs.indexWhere((t) => t.id == activeId),
      ),
    );
  }

  /// Opens [location] in a new tab of this panel and shows it.
  Future<void> openInNewTab(Location location, {String? focusName}) async {
    await newTab(location: location);
    if (focusName != null) {
      final tab = state.active;
      if (tab != null) {
        final at = tab.indexOfName(focusName);
        if (at >= 0) moveCursorTo(at);
      }
    }
  }

  /// Shows [location] with the cursor on [focusName], in the active tab.
  Future<void> reveal(Location location, {required String focusName}) =>
      open(location, focusName: focusName);

  @override
  Future<void> close() async {
    await _changes?.cancel();
    await _progress?.cancel();
    await _prefs?.cancel();
    for (final tab in state.tabs) {
      await _files.closeListing(tab.id);
    }
    return super.close();
  }
}
