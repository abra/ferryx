import 'dart:async';
import 'dart:math' as math;

import 'package:domain_models/domain_models.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:monitoring/monitoring.dart';
import 'package:network_service/network_service.dart';
import 'package:operations_service/operations_service.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:path/path.dart' as path;

import 'flat_view.dart';
import 'panel_side.dart';
import 'panel_state.dart';
import 'quick_search.dart';
import 'saved_panel.dart';
import 'panel_search_state.dart';

part 'panel_search.dart';

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
    this.onFolderShown,
    this.readTags = false,
    NetworkService? network,
    this.connectServer,
    this._find,
  }) : _files = files,
       _operations = operations,
       _preferences = preferences,
       super(PanelState(side: side, servers: network?.servers ?? const {})) {
    _changes = files.directoryChanges.listen(_onDirectoryChanged);
    _progress = operations.progress.listen(_onProgress);
    _prefs = preferences.stream.listen(_onPreferences);
    _lastPrefs = preferences.current;
    _serverChanges = network?.serverChanges.listen(_onServers);
  }

  final PanelSide side;
  final FindService? _find;
  final _searchTasks = <String, TaskSession<FindUpdate>>{};
  final _searchHits = <String, List<FindHit>>{};
  final _searchSorts = <String, int>{};
  int _searchGeneration = 0;
  void _emitSearchState(PanelState next) {
    if (!isClosed) emit(next);
  }

  /// Finder tags are read for the rows once a listing shows (the core
  /// reports the capability; elsewhere there are none to read).
  final bool readTags;
  final FileRepository _files;
  final OperationsService _operations;
  final PreferencesService _preferences;
  final Logger logger;

  /// A folder on disk the user went to is shown: the window counts the
  /// visit for Jump to Folder. Not for the tabs a start restores, nor for
  /// a folder read again where it is.
  final void Function(String path)? onFolderShown;

  /// Opens the connection to a server (by its key) again, asking the user
  /// what it must; answers whether it is open. Without it a folder on a
  /// server that is not connected stays unread.
  final Future<bool> Function(String server)? connectServer;
  StreamSubscription<Map<String, ServerStatus>>? _serverChanges;

  /// Where a tab goes when nothing else is left to it: the home folder.
  Location _fallback = const Location.native('/');
  StreamSubscription<String>? _changes;
  StreamSubscription<OperationProgress>? _progress;
  StreamSubscription<Preferences>? _prefs;
  Preferences _lastPrefs = const Preferences();
  int _nextTabNumber = 1;

  /// Rows per page and per column, as the view last measured them.
  PanelGeometry geometry = const PanelGeometry();

  /// Each row's name folded for quick search: folded once, a typed key
  /// then folds only the query. A row a read again kept is the same
  /// object (see `FileRepository`) and keeps its folding.
  final _folded = Expando<FoldedText>('folded name');

  /// Tabs whose folder changed while they were not shown: read again
  /// when shown, not on every change (a large folder costs a read).
  final _stale = <String>{};

  /// Each tab's read again under way, and the tabs asked to read again
  /// meanwhile: a burst of changes reads once more, not once each.
  final _refreshing = <String, Future<void>>{};
  final _again = <String>{};

  /// A failed or completed read may arrive after a newer navigation request.
  final _loads = <String, Object>{};

  int _loadIndex(String id, Object request) =>
      isClosed || !identical(_loads[id], request)
      ? -1
      : state.tabs.indexWhere((tab) => tab.id == id);

  /// The last quick search a tab ran, by tab id: a query typed on extends
  /// it, and then only its matches can match ([narrowsAsTyped]).
  final _searched =
      <
        String,
        ({
          List<FileEntry> entries,
          String query,
          QuickSearchWhere where,
          Map<String, List<(int, int)>> matches,
        })
      >{};

  /// Operations started here whose folder sizes go into the tabs.
  final _sizeOperations = <int>{};

  /// The flat views' walks under way, by listing id.
  final _flatWalks = <String, StreamSubscription<FlatBatch>>{};

  Preferences get _p => _preferences.current;

  ListingOptions _options(SortOptions sort) => ListingOptions(
    showHidden: _p.showHiddenFiles,
    showParent: _p.showParentEntry,
    sort: sort,
  );

  // ─── Start and persistence ───

  /// Opens the saved tabs, or one at [fallback].
  Future<void> start(SavedPanel? saved, Location fallback) async {
    _fallback = fallback;
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
      if (tabs[i].search case final query? when _find != null) {
        await _openSearch(i, query, label: tabs[i].searchLabel);
        continue;
      }
      await _load(
        i,
        states[i].location,
        pushHistory: true,
        fallback: fallback,
        visit: false,
        // A tab left on a server waits for the user to connect again.
        connect: false,
      );
    }
  }

  SavedPanel saved() => SavedPanel(
    tabs: [
      for (final tab in state.tabs)
        SavedTab(
          location: tab.location,
          sort: tab.sort,
          layoutIndex: tab.layoutIndex,
          search: tab.search?.request,
          searchLabel: tab.search?.label,
        ),
    ],
    activeIndex: state.activeIndex,
    closedTabs: state.closedTabs.take(20).toList(),
  );

  /// Replace navigation state while retiring every old listing first.
  /// Existing file operations keep running independently of these tabs.
  Future<void> restore(SavedPanel saved, Location fallback) async {
    final old = state.tabs;
    emit(state.copyWith(tabs: const [], activeIndex: 0));
    for (final tab in old) {
      await _stopSearch(tab.id);
      await _stopFlat(tab.id);
      _forget(tab.id);
      if (tab.search == null) await _files.closeListing(tab.id);
    }
    if (!isClosed) await start(saved, fallback);
  }

  String _newTabId() => '${side.name}-${_nextTabNumber++}';

  // ─── Loading ───

  /// Reads [location] into the tab at [index]. A folder that cannot be
  /// read leaves the tab where it was and records the error; a tab with
  /// nothing yet falls back to [fallback], then to the root. A folder on a
  /// server that is not connected is connected to first, with [connect].
  Future<void> _load(
    int index,
    Location location, {
    required bool pushHistory,
    String? focusName,
    Location? fallback,
    bool visit = true,
    bool connect = true,
    int? targetHistoryIndex,
  }) async {
    final tab = state.tabs.elementAtOrNull(index);
    if (tab == null || isClosed) return;
    final request = Object();
    _loads[tab.id] = request;
    emit(
      state.withTab(
        index,
        tab.copyWith(
          loading: true,
          clearError: true,
          pendingFocusName: focusName,
          clearPendingFocus: focusName == null,
        ),
      ),
    );
    try {
      final listing = await _files.openListing(
        tab.id,
        location,
        _options(tab.sort),
      );
      index = _loadIndex(tab.id, request);
      if (index < 0) return;
      // Retire the old view only once the new folder has actually opened.
      await _stopSearch(tab.id);
      index = _loadIndex(tab.id, request);
      if (index < 0) return;
      await _stopFlat(tab.id);
      index = _loadIndex(tab.id, request);
      if (index < 0) return;
      final current = state.tabs[index];
      if (visit &&
          location.isNative &&
          (current.listing == null || current.location != location)) {
        onFolderShown?.call(location.path);
      }
      var history = current.history;
      var historyIndex = targetHistoryIndex ?? current.historyIndex;
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
              clearPasswordLocation: true,
              clearFlat: true,
              clearSearch: true,
            ),
            focusName: focusName ?? current.pendingFocusName,
            // Another folder: the old cursor's name and place mean nothing
            // there (a child may even share the name of the folder left).
            fresh: current.location != location,
          ).copyWith(clearPendingFocus: true),
        ),
      );
      unawaited(_loadTags(tab.id));
    } on FerryxException catch (error, stackTrace) {
      index = _loadIndex(tab.id, request);
      if (index < 0) return;
      if (error.kind == FerryxErrorKind.cancelled) {
        emit(
          state.withTab(
            index,
            state.tabs[index].copyWith(
              loading: false,
              clearPendingFocus: true,
            ),
          ),
        );
        return;
      }
      final server = location.server;
      final connector = connectServer;
      if (server != null &&
          connect &&
          connector != null &&
          error.kind == FerryxErrorKind.notConnected) {
        final bool open;
        try {
          open = await connector(server);
        } on Object catch (error, stackTrace) {
          _recoverReadFailure(tab.id, request, location, error, stackTrace);
          return;
        }
        final at = _loadIndex(tab.id, request);
        if (at < 0) return;
        if (open) {
          await _load(
            at,
            location,
            pushHistory: pushHistory,
            focusName: focusName,
            fallback: fallback,
            visit: visit,
            connect: false,
            targetHistoryIndex: targetHistoryIndex,
          );
          return;
        }
        // Given up, or failed and said why: the tab stays where it was.
        final current = state.tabs[at];
        emit(
          state.withTab(
            at,
            current.listing == null
                ? _unreached(current, location, error)
                : current.copyWith(loading: false, clearPendingFocus: true),
          ),
        );
        return;
      }
      _logReadFailure(location, error, stackTrace);
      final current = state.tabs.elementAtOrNull(index);
      if (current == null || current.id != tab.id) return;
      if (current.listing == null &&
          location.isRemote &&
          error.kind.needsConnection) {
        // A server out of reach keeps its tab, to connect to again.
        emit(state.withTab(index, _unreached(current, location, error)));
        return;
      }
      if (error.kind == FerryxErrorKind.passwordRequired &&
          !location.isNative) {
        // The window asks for the password and opens it again; the tab
        // stays where it was meanwhile.
        emit(
          state.withTab(
            index,
            current.copyWith(
              loading: false,
              error: error,
              clearPendingFocus: true,
              passwordLocation: location,
            ),
          ),
        );
        if (current.listing != null) return;
      }
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
        if (next != null) {
          await _load(index, next, pushHistory: pushHistory, visit: visit);
        }
        return;
      }
      emit(
        state.withTab(
          index,
          current.copyWith(
            loading: false,
            error: error,
            failedLocation: location,
            clearPendingFocus: true,
          ),
        ),
      );
    } on Object catch (error, stackTrace) {
      _recoverReadFailure(tab.id, request, location, error, stackTrace);
    }
  }

  void _logReadFailure(Location location, Object error, StackTrace stackTrace) {
    if (error is! FerryxException) {
      logger.error(
        'cannot open ${location.display}',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }
    final expected = switch (error.kind) {
      FerryxErrorKind.notFound ||
      FerryxErrorKind.notADirectory ||
      FerryxErrorKind.permissionDenied ||
      FerryxErrorKind.invalidName => true,
      _ => false,
    };
    final log = expected ? logger.info : logger.warn;
    log(
      'cannot open ${location.display}',
      error: error,
      stackTrace: expected ? null : stackTrace,
    );
  }

  void _recoverReadFailure(
    String id,
    Object request,
    Location location,
    Object error,
    StackTrace stackTrace,
  ) {
    final index = _loadIndex(id, request);
    if (index < 0) return;
    final cancelled =
        error is FerryxException && error.kind == FerryxErrorKind.cancelled;
    if (!cancelled) _logReadFailure(location, error, stackTrace);
    final failure = error is FerryxException
        ? error
        : FerryxException(FerryxErrorKind.io, location.display);
    emit(
      state.withTab(
        index,
        state.tabs[index].copyWith(
          loading: false,
          error: cancelled ? null : failure,
          failedLocation: cancelled ? null : location,
          clearError: cancelled,
          clearPendingFocus: true,
        ),
      ),
    );
  }

  /// A tab with nothing read yet, left at [location] on a server it could
  /// not reach, [error] saying why.
  PanelTabState _unreached(
    PanelTabState tab,
    Location location,
    FerryxException error,
  ) => tab.copyWith(
    location: location,
    loading: false,
    error: error,
    clearPendingFocus: true,
    history: tab.history.isEmpty ? [location] : null,
    historyIndex: tab.history.isEmpty ? 0 : null,
  );

  /// The tab with its rows rebuilt from its listing: quick search applied,
  /// folder sizes merged, the cursor kept on its name or put on
  /// [focusName]; for a [fresh] folder, on [focusName] or the first row.
  PanelTabState _withListing(
    PanelTabState tab, {
    String? focusName,
    bool fresh = false,
  }) {
    final entries = tab.listing?.entries ?? const [];
    final where = _p.quickSearchWhere;
    final onlyMatching = _p.quickSearchOnlyMatching;
    final query = tab.quickSearch;
    final searching = query.isNotEmpty;
    final foldedQuery = FoldedText(query);
    final last = _searched[tab.id];
    // Only the last query's matches can match one typed on from it.
    final among =
        searching &&
            last != null &&
            identical(last.entries, entries) &&
            last.where == where &&
            last.query.isNotEmpty &&
            query.startsWith(last.query) &&
            narrowsAsTyped(where)
        ? last.matches
        : null;
    final matches = <String, List<(int, int)>>{};
    final rows = <FileEntry>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      var row = entry;
      final size = tab.folderSizes[entry.name];
      if (size != null && entry.isDir && entry.size == null) {
        row = entry.copyWith(size: size);
      }
      if (searching && !entry.isParent) {
        final ranges = among != null && !among.containsKey(entry.key)
            ? null
            : quickMatchFolded(
                foldedQuery,
                _folded[entry] ??= FoldedText(entry.name),
                where,
              );
        if (ranges == null) {
          if (onlyMatching) continue;
        } else {
          matches[entry.key] = ranges;
        }
      }
      rows.add(row);
    }
    if (searching) {
      _searched[tab.id] = (
        entries: entries,
        query: query,
        where: where,
        matches: matches,
      );
    } else {
      _searched.remove(tab.id);
    }
    final wanted = focusName ?? (fresh ? null : tab.focused?.key);
    var cursor = wanted == null ? -1 : rows.indexWhere((r) => r.key == wanted);
    if (cursor < 0) {
      cursor = rows.isEmpty
          ? -1
          : fresh
          ? 0
          : math.min(math.max(tab.cursor, 0), rows.length - 1);
    }
    final selected = tab.selected.isEmpty
        ? tab.selected
        : () {
            final names = {for (final r in rows) r.key};
            return tab.selected.where(names.contains).toSet();
          }();
    return tab.copyWith(
      rows: rows,
      matches: matches,
      cursor: cursor,
      selected: selected,
      scrollRequest: tab.scrollRequest + 1,
    );
  }

  Future<void> refresh() async {
    final tab = state.active;
    if (tab != null &&
        tab.location.isRemote &&
        (tab.listing == null || (tab.error?.kind.needsConnection ?? false))) {
      // A server that dropped or was never reached: connected to, then
      // read.
      await reconnect();
      return;
    }
    await _refreshTab(state.activeIndex);
  }

  // ─── Network ───

  /// The active tab's server connected to again, and its folder read.
  Future<void> reconnect() async {
    final tab = state.active;
    if (tab == null || !tab.location.isRemote) return;
    await _load(
      state.activeIndex,
      tab.location,
      pushHistory: false,
      focusName: tab.focused?.key,
    );
  }

  void _onServers(Map<String, ServerStatus> next) {
    final before = state.servers;
    emit(state.copyWith(servers: next));
    for (final server in before.keys) {
      if (!next.containsKey(server)) unawaited(_leaveServer(server));
    }
  }

  /// [server] was disconnected: its tabs go back to where they were on
  /// disk last, else home.
  Future<void> _leaveServer(String server) async {
    final ids = [
      for (final tab in state.tabs)
        if (tab.location.server == server) tab.id,
    ];
    for (final id in ids) {
      final index = state.tabs.indexWhere((t) => t.id == id);
      if (index < 0) continue;
      final tab = state.tabs[index];
      // The places before the current one, the nearest first, then after.
      final before = tab.history.take(tab.historyIndex + 1).toList().reversed;
      final after = tab.history.skip(tab.historyIndex + 1);
      final back = before.followedBy(after).where((l) => !l.isRemote);
      await _load(
        index,
        back.firstOrNull ?? _fallback,
        pushHistory: true,
        visit: false,
      );
    }
  }

  /// An operation on a server ended: the tabs on that server are read
  /// again (nothing watches a server's folders).
  void _refreshServersTouched(OperationProgress progress) {
    final touched = [...progress.sources, ?progress.destination];
    for (var i = 0; i < state.tabs.length; i++) {
      final server = state.tabs[i].location.server;
      if (server != null && touched.any((p) => p.startsWith('$server/'))) {
        unawaited(_refreshTab(i));
      }
    }
  }

  /// Reads tab [index]'s folder again; asked while a read of it is under
  /// way, reads once more after it.
  Future<void> _refreshTab(int index) {
    final id = state.tabs.elementAtOrNull(index)?.id;
    if (id == null) return Future.value();
    if (state.tabs[index].search?.running ?? false) {
      _stale.add(id);
      return Future.value();
    }
    _stale.remove(id);
    final running = _refreshing[id];
    if (running != null) {
      _again.add(id);
      return running;
    }
    final run = _readAgain(id, index);
    _refreshing[id] = run;
    return run;
  }

  Future<void> _readAgain(String id, int index) async {
    try {
      await _refreshOnce(index);
      while (_again.remove(id)) {
        final at = state.tabs.indexWhere((t) => t.id == id);
        if (at < 0) return;
        await _refreshOnce(at);
      }
    } finally {
      _refreshing.remove(id);
    }
  }

  Future<void> _refreshOnce(int index) async {
    final tab = state.tabs.elementAtOrNull(index);
    if (tab == null || tab.loading) return;
    if (tab.search case final search?) {
      await _openSearch(
        index,
        search.request,
        label: search.label,
        refreshing: true,
      );
      return;
    }
    if (tab.isFlat) {
      await _walkFlatAgain(index);
      return;
    }
    final request = _loads[tab.id];
    if (request == null) return;
    try {
      final listing = await _files.refreshListing(tab.id);
      index = _loadIndex(tab.id, request);
      if (index < 0) return;
      final current = state.tabs[index];
      emit(
        state.withTab(
          index,
          _withListing(
            current.copyWith(
              listing: listing.copyWith(
                entries: _keepTags(current.listing, listing.entries),
              ),
              clearError: true,
            ),
          ),
        ),
      );
      unawaited(_loadTags(tab.id));
    } on FerryxException catch (error) {
      index = _loadIndex(tab.id, request);
      if (index < 0) return;
      // A read of the tab's own took this one's place.
      if (error.kind == FerryxErrorKind.cancelled) return;
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
    } on Object catch (error, stackTrace) {
      _recoverReadFailure(tab.id, request, tab.location, error, stackTrace);
    }
  }

  void _onDirectoryChanged(String listingId) {
    final index = state.tabs.indexWhere((t) => t.id == listingId);
    if (index < 0) return;
    if (index == state.activeIndex) {
      unawaited(_refreshTab(index));
    } else {
      _stale.add(listingId);
    }
  }

  /// The tab shown now is read again if its folder changed unseen.
  void _readIfStale() {
    final tab = state.active;
    if (tab != null && _stale.contains(tab.id)) {
      unawaited(_refreshTab(state.activeIndex));
    }
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
    final rowsChanged =
        before.showHiddenFiles != next.showHiddenFiles ||
        before.showParentEntry != next.showParentEntry;
    for (var i = 0; i < state.tabs.length; i++) {
      final tab = state.tabs[i];
      if (tab.isFlat && rowsChanged) {
        // Other rows: the tree is walked again.
        await _walkFlatAgain(i);
        continue;
      }
      await _resortTab(i, tab.sort);
    }
  }

  Future<void> _resortTab(int index, SortOptions sort) async {
    final tab = state.tabs.elementAtOrNull(index);
    if (tab == null || tab.listing == null) return;
    if (tab.search != null) {
      await _sortSearch(tab.id, tab.search!.generation, sort);
      return;
    }
    if (tab.isFlat) {
      await _resortFlat(index, sort);
      return;
    }
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

  Future<void> retryFailedRead() async {
    final target = state.active?.failedLocation;
    if (target == null) {
      await refresh();
    } else {
      await open(target);
    }
  }

  void dismissError() {
    final tab = state.active;
    if (tab?.error == null) return;
    emit(
      state.withActive(
        tab!.copyWith(clearError: true, clearPasswordLocation: true),
      ),
    );
  }

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
      if (tab.search != null) {
        await newTab(location: tab.locationOf(entry));
      } else {
        await open(tab.locationOf(entry));
      }
      return null;
    }
    final location = tab.locationOf(entry);
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
      await open(tab.locationOf(entry));
      return null;
    }
    if (tab.location.isNative) {
      await open(Location.inArchive(archive: entry.path));
      return null;
    }
    return OpenFileRequest(entry, tab.locationOf(entry));
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
    await _load(
      index,
      tab.history[target],
      pushHistory: false,
      targetHistoryIndex: target,
    );
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
        (focused == null || !tab.selected.contains(focused.key));
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
      selected.add(row.key);
    } else {
      selected.remove(row.key);
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
    if (geometry.columnsPerRow > 1) {
      final tab = state.active;
      if (tab == null || tab.cursor < 0) return;
      final column = tab.cursor % geometry.columnsPerRow;
      final target = (column + direction).clamp(0, geometry.columnsPerRow - 1);
      moveCursor(target - column, selecting: selecting);
      return;
    }
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
    if (!selected.remove(row.key)) selected.add(row.key);
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
    _setSelection((row) => !tab.selected.contains(row.key));
  }

  /// Selects ([select]) or deselects the rows whose name [matches].
  void selectWhere(
    bool Function(FileEntry row) matches, {
    required bool select,
  }) {
    final tab = state.active;
    if (tab == null) return;
    _setSelection(
      (row) => matches(row) ? select : tab.selected.contains(row.key),
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
        if (!row.isParent && selected(row)) row.key,
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
    final names = tab.rows.map((r) => r.key).toSet();
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
    if (tab == null || tab.matches.isEmpty || count <= 0) return;
    // Complete wraps do not change the target. Keep the final traversal
    // when count is a multiple: the cursor need not be on a matching row.
    var remaining = (count - 1) % tab.matches.length + 1;
    var at = tab.cursor;
    for (var scanned = 0; scanned < tab.rows.length; scanned++) {
      at = (at + (forward ? 1 : -1) + tab.rows.length) % tab.rows.length;
      if (tab.matches.containsKey(tab.rows[at].key) && --remaining == 0) {
        moveCursorTo(at);
        return;
      }
    }
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
      focusName: tab.focused?.key,
    );
    // The cursor goes to the first match, when the one under it is none.
    var cursor = next.cursor;
    if (query.isNotEmpty) {
      final focused = next.focused;
      if (focused == null || !next.matches.containsKey(focused.key)) {
        final first = next.rows.indexWhere(
          (r) => next.matches.containsKey(r.key),
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
        !(tab.location.isNative || tab.location.isRemote)) {
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
      if (tab.location.isRemote) {
        await _files.renameAt(tab.locationOf(row), trimmed);
      } else {
        await _files.rename(row.path, trimmed);
      }
      final current = state.active;
      if (current != null && current.id == tab.id) {
        final key = row.folder.isEmpty ? trimmed : '${row.folder}/$trimmed';
        _emitActive(current.copyWith(pendingFocusName: key));
        await _refreshTab(state.activeIndex);
        final after = state.active;
        if (after != null && !after.isFlat) {
          final at = after.indexOfName(key);
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
    if (tab == null || !(tab.location.isNative || tab.location.isRemote)) {
      return;
    }
    final wanted = names?.toSet();
    final folders = [
      for (final row in tab.rows)
        if (row.isDir && !row.isParent && !row.isSymlink)
          if (wanted == null || wanted.contains(row.name)) row.path,
    ];
    if (folders.isEmpty) return;
    final id = await _operations.start(
      OperationRequest(
        kind: OpKind.calcSizes,
        sources: folders,
        sourceServer: tab.location.server,
      ),
    );
    _sizeOperations.add(id);
  }

  void _onProgress(OperationProgress progress) {
    if (progress.state.isFinished && progress.kind != OpKind.calcSizes) {
      for (var index = 0; index < state.tabs.length; index++) {
        if (state.tabs[index].search == null) continue;
        _stale.add(state.tabs[index].id);
        if (index == state.activeIndex) unawaited(_refreshTab(index));
      }
      _walkFlatViewsUnder(progress);
      _refreshServersTouched(progress);
    }
    if (!_sizeOperations.contains(progress.id)) return;
    if (progress.state.isFinished) _sizeOperations.remove(progress.id);
    if (progress.sizes.isEmpty) return;
    for (var i = 0; i < state.tabs.length; i++) {
      final tab = state.tabs[i];
      if (!tab.location.isNative && !tab.location.isRemote) continue;
      // A server's folders are named with its key, as the progress names
      // them.
      final shown = '${tab.location.server ?? ''}${tab.location.path}';
      final prefix = shown.endsWith('/') ? shown : '$shown/';
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
    _readIfStale();
    await _stopSearch(tab.id);
    await _stopFlat(tab.id);
    _forget(tab.id);
    if (tab.search == null) await _files.closeListing(tab.id);
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
      await _stopSearch(tab.id);
      await _stopFlat(tab.id);
      _forget(tab.id);
      if (tab.search == null) await _files.closeListing(tab.id);
    }
  }

  /// What the cubit kept of a tab closed.
  void _forget(String id) {
    _loads.remove(id);
    _searched.remove(id);
    _stale.remove(id);
    _again.remove(id);
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
    _readIfStale();
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

  // ─── Flat view ───

  /// ⌥⌘B, `zf`, `:flat`: the folder's whole subtree as one list, or back
  /// to the folder.
  Future<void> toggleFlatView() async {
    final tab = state.active;
    if (tab == null) return;
    if (tab.isFlat) {
      await leaveFlatView();
    } else {
      await _openFlat(state.activeIndex, again: false);
    }
  }

  /// Back to the folder, the cursor on the item that holds the row it was
  /// on (the row itself, or its folder at the top).
  Future<void> leaveFlatView() async {
    final tab = state.active;
    if (tab == null || !tab.isFlat) return;
    final focused = tab.focused;
    final focusName = focused == null || focused.isParent
        ? null
        : focused.folder.isEmpty
        ? focused.name
        : focused.folder.split('/').first;
    await _load(
      state.activeIndex,
      tab.location,
      pushHistory: false,
      focusName: focusName,
    );
  }

  /// Starts a walk of the tab's tree: the first one shows its rows as
  /// they come; one [again] keeps the rows shown until it ends.
  Future<void> _openFlat(int index, {required bool again}) async {
    final tab = state.tabs.elementAtOrNull(index);
    if (tab == null) return;
    await _stopFlat(tab.id);
    if (!again) {
      emit(state.withTab(index, tab.copyWith(loading: true, clearError: true)));
    }
    try {
      final start = await _files.openFlatListing(
        tab.id,
        tab.location,
        _options(tab.sort),
      );
      // Found by its id: tabs before it may have closed meanwhile.
      final at = state.tabs.indexWhere((t) => t.id == tab.id);
      if (at < 0) {
        // The tab closed meanwhile: the walk and its listing go too.
        await start.batches.listen(null).cancel();
        if (tab.search == null) await _files.closeListing(tab.id);
        return;
      }
      final current = state.tabs[at];
      if (again && current.isFlat) {
        emit(
          state.withTab(
            at,
            current.copyWith(
              flat: FlatView(
                generation: start.generation,
                walking: false,
                refreshing: true,
                count: current.flat!.count,
                capped: current.flat!.capped,
                walked: current.flat!.walked,
              ),
            ),
          ),
        );
      } else {
        emit(
          state.withTab(
            at,
            current.copyWith(
              listing: start.listing,
              rows: const [],
              cursor: -1,
              selected: const {},
              quickSearch: '',
              matches: const {},
              folderSizes: const {},
              loading: false,
              clearError: true,
              clearRenaming: true,
              clearRange: true,
              clearVisual: true,
              searching: false,
              scrollRequest: current.scrollRequest + 1,
              flat: FlatView(generation: start.generation),
            ),
          ),
        );
      }
      _flatWalks[tab.id] = start.batches.listen(
        (batch) => unawaited(_onFlatBatch(tab.id, batch)),
      );
    } on FerryxException catch (error, stackTrace) {
      logger.warn(
        'cannot walk ${tab.location.display}',
        error: error,
        stackTrace: stackTrace,
      );
      final at = state.tabs.indexWhere((t) => t.id == tab.id);
      if (at >= 0) {
        emit(
          state.withTab(
            at,
            state.tabs[at].copyWith(loading: false, error: error),
          ),
        );
      }
    }
  }

  /// The tree is walked again (⌘R, a change in the folder, an operation
  /// under it); a change while a walk again is under way asks for one
  /// more after it.
  Future<void> _walkFlatAgain(int index) async {
    final tab = state.tabs.elementAtOrNull(index);
    final flat = tab?.flat;
    if (tab == null || flat == null) return;
    if (flat.refreshing) {
      emit(
        state.withTab(index, tab.copyWith(flat: flat.copyWith(again: true))),
      );
      return;
    }
    await _openFlat(index, again: true);
  }

  Future<void> _stopFlat(String id) async {
    await _flatWalks.remove(id)?.cancel();
  }

  Future<void> _onFlatBatch(String id, FlatBatch batch) async {
    final index = state.tabs.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final tab = state.tabs[index];
    final flat = tab.flat;
    if (flat == null || flat.generation != batch.generation) return;
    if (batch.done) {
      await _finishFlat(id, batch);
      return;
    }
    if (flat.refreshing) {
      emit(
        state.withTab(
          index,
          tab.copyWith(
            flat: flat.copyWith(
              pending: [...flat.pending, ...batch.entries],
              count: batch.count,
            ),
          ),
        ),
      );
      return;
    }
    emit(state.withTab(index, _appendFlat(tab, flat, batch)));
  }

  /// The first walk's new rows go under the shown ones; only they are
  /// matched against the quick search.
  PanelTabState _appendFlat(PanelTabState tab, FlatView flat, FlatBatch batch) {
    final walked = [...flat.walked, ...batch.entries];
    final where = _p.quickSearchWhere;
    final onlyMatching = _p.quickSearchOnlyMatching;
    final query = FoldedText(tab.quickSearch);
    Map<String, List<(int, int)>>? matches;
    final added = <FileEntry>[];
    for (final entry in batch.entries) {
      if (tab.quickSearch.isNotEmpty && !entry.isParent) {
        final ranges = quickMatchFolded(
          query,
          _folded[entry] ??= FoldedText(entry.name),
          where,
        );
        if (ranges == null) {
          if (onlyMatching) continue;
        } else {
          (matches ??= {...tab.matches})[entry.key] = ranges;
        }
      }
      added.add(entry);
    }
    final rows = [...tab.rows, ...added];
    return tab.copyWith(
      listing: tab.listing?.copyWith(entries: walked),
      rows: rows,
      matches: matches,
      cursor: tab.cursor < 0 && rows.isNotEmpty ? 0 : null,
      flat: flat.copyWith(walked: walked, count: batch.count),
    );
  }

  /// The walk ended: its rows, sorted, replace the shown ones; the cursor
  /// and the selection stay on their rows.
  Future<void> _finishFlat(String id, FlatBatch batch) async {
    final before = state.tabs.where((t) => t.id == id).firstOrNull;
    final flat = before?.flat;
    if (before == null || flat == null) return;
    final walked = flat.refreshing ? flat.pending : flat.walked;
    final sort = before.sort;
    final order = await _flatOrder(id, flat.generation, sort, walked.length);
    final index = state.tabs.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final tab = state.tabs[index];
    if (tab.flat?.generation != flat.generation) return;
    final again = tab.flat!.again;
    emit(
      state.withTab(
        index,
        _withListing(
          tab.copyWith(
            listing: tab.listing?.copyWith(
              entries: _keepTags(tab.listing, [
                for (final i in order) walked[i],
              ]),
            ),
            flat: FlatView(
              generation: flat.generation,
              walking: false,
              count: batch.count,
              capped: batch.capped,
              walked: _keepTags(tab.listing, walked),
            ),
            loading: false,
          ),
          focusName: tab.pendingFocusName,
        ).copyWith(clearPendingFocus: true),
      ),
    );
    await _stopFlat(id);
    unawaited(_loadTags(id));
    if (tab.sort != sort) {
      // The order changed while the rows were sorted.
      await _resortFlat(index, tab.sort);
    }
    if (again) await _walkFlatAgain(index);
  }

  /// The order of a flat view's rows (indices into the walk's), from the
  /// core; the walk's own order when it cannot say.
  Future<List<int>> _flatOrder(
    String id,
    int generation,
    SortOptions sort,
    int length,
  ) async {
    try {
      final order = await _files.sortFlatListing(
        id,
        generation,
        _options(sort),
      );
      if (order.length == length) return order;
    } on FerryxException catch (error) {
      logger.warn('cannot sort the flat view', error: error);
    }
    return [for (var i = 0; i < length; i++) i];
  }

  Future<void> _resortFlat(int index, SortOptions sort) async {
    final tab = state.tabs.elementAtOrNull(index);
    final flat = tab?.flat;
    if (tab == null || flat == null) return;
    if (flat.busy) {
      // The walk sorts its rows when it ends, by the order asked last.
      emit(state.withTab(index, tab.copyWith(sort: sort)));
      return;
    }
    final order = await _flatOrder(
      tab.id,
      flat.generation,
      sort,
      flat.walked.length,
    );
    final current = state.tabs.elementAtOrNull(index);
    if (current == null || current.flat?.generation != flat.generation) return;
    emit(
      state.withTab(
        index,
        _withListing(
          current.copyWith(
            sort: sort,
            listing: current.listing?.copyWith(
              entries: [for (final i in order) flat.walked[i]],
            ),
          ),
        ),
      ),
    );
  }

  /// An operation ended: the flat views whose trees it wrote into or took
  /// from are walked again (their folder alone is watched).
  void _walkFlatViewsUnder(OperationProgress progress) {
    final touched = [
      for (final source in progress.sources) _parentOf(source),
      ?progress.destination,
    ];
    for (var i = 0; i < state.tabs.length; i++) {
      final tab = state.tabs[i];
      if (!tab.isFlat || !tab.location.isNative) continue;
      final root = tab.location.path;
      final prefix = root.endsWith('/') ? root : '$root/';
      if (touched.any((p) => p == root || p.startsWith(prefix))) {
        unawaited(_walkFlatAgain(i));
      }
    }
  }

  static String _parentOf(String path) {
    final slash = path.lastIndexOf('/');
    return slash <= 0 ? '/' : path.substring(0, slash);
  }

  // ─── Finder tags ───

  /// The rows' tags, read apart from the listing once it shows (each item
  /// costs the core a system call); the dots follow a moment later.
  Future<void> _loadTags(String id) async {
    if (!readTags) return;
    final tab = state.tabs.where((t) => t.id == id).firstOrNull;
    if (tab == null || !tab.location.isNative) return;
    final Map<String, List<FileTag>> found;
    try {
      found = await _files.listingTags(id);
    } on FerryxException catch (error) {
      logger.warn('cannot read the tags', error: error);
      return;
    }
    if (found.isEmpty || isClosed) return;
    _mergeTags(found, only: id);
  }

  /// Tags changed (an edit from this window): the rows of [byPath] in
  /// every tab take their new tags, none included.
  void applyTags(Map<String, List<FileTag>> byPath) => _mergeTags(byPath);

  void _mergeTags(Map<String, List<FileTag>> byPath, {String? only}) {
    var next = state;
    for (var i = 0; i < next.tabs.length; i++) {
      final tab = next.tabs[i];
      if (only != null && tab.id != only) continue;
      if (!tab.location.isNative) continue;
      // The same list when nothing in it changed, so the rows rebuild
      // only where tags did.
      List<FileEntry> merge(List<FileEntry> entries) {
        List<FileEntry>? out;
        for (var at = 0; at < entries.length; at++) {
          final entry = entries[at];
          final tags = byPath[entry.path];
          if (tags == null || _sameTags(tags, entry.tags)) continue;
          (out ??= [...entries])[at] = entry.copyWith(tags: tags);
        }
        return out ?? entries;
      }

      final listing = tab.listing;
      final flat = tab.flat;
      final rows = merge(tab.rows);
      final entries = listing == null ? null : merge(listing.entries);
      final walked = flat == null ? null : merge(flat.walked);
      final pending = flat == null ? null : merge(flat.pending);
      if (identical(rows, tab.rows) &&
          identical(entries, listing?.entries) &&
          identical(walked, flat?.walked) &&
          identical(pending, flat?.pending)) {
        continue;
      }
      next = next.withTab(
        i,
        tab.copyWith(
          listing: entries == null ? null : listing?.copyWith(entries: entries),
          rows: rows,
          flat: flat?.copyWith(walked: walked, pending: pending),
        ),
      );
    }
    if (!identical(next, state)) emit(next);
  }

  static bool _sameTags(List<FileTag> a, List<FileTag> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// [entries] with the tags the rows of [before] had, by path: a listing
  /// read again shows its dots at once, until its tags are read anew.
  List<FileEntry> _keepTags(Listing? before, List<FileEntry> entries) {
    if (!readTags || before == null) return entries;
    final tags = {
      for (final e in before.entries)
        if (e.tags.isNotEmpty) e.path: e.tags,
    };
    if (tags.isEmpty) return entries;
    return [
      for (final e in entries)
        if (tags[e.path] case final kept? when e.tags.isEmpty)
          e.copyWith(tags: kept)
        else
          e,
    ];
  }

  // ─── Archive passwords ───

  /// The password was given: the folder that asked for it opens. Until
  /// then the tab stays where it was, its error saying why.
  Future<void> openAfterPassword() async {
    final tab = state.active;
    final location = tab?.passwordLocation;
    if (tab == null || location == null) return;
    await open(location);
  }

  @override
  Future<void> close() async {
    _loads.clear();
    _searchSorts.clear();
    for (final task in _searchTasks.values.toList()) {
      await task.close();
    }
    _searchTasks.clear();
    _searchHits.clear();
    await _serverChanges?.cancel();
    await _changes?.cancel();
    await _progress?.cancel();
    await _prefs?.cancel();
    for (final walk in _flatWalks.values) {
      await walk.cancel();
    }
    _flatWalks.clear();
    for (final tab in state.tabs) {
      if (tab.search == null) await _files.closeListing(tab.id);
    }
    return super.close();
  }
}
