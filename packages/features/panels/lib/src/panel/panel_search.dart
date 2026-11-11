part of 'panel_cubit.dart';

extension PanelSearchTabs on PanelCubit {
  static const maxHits = 10000;

  Future<void> newSearchTab(FindRequest request, {String? label}) async {
    if (_find == null || isClosed) return;
    final active = state.active;
    final tab = PanelTabState(
      id: _newTabId(),
      location: Location.native(request.root),
      sort: active?.sort ?? _p.defaultSort,
      layoutIndex: active?.layoutIndex ?? 2,
    );
    final index = (state.activeIndex + 1).clamp(0, state.tabs.length);
    final tabs = [...state.tabs]..insert(index, tab);
    _emitSearchState(state.copyWith(tabs: tabs, activeIndex: index));
    await _openSearch(index, request, label: label);
  }

  Future<void> stopSearch() async {
    final tab = state.active;
    final search = tab?.search;
    if (tab == null || search == null || !search.running) return;
    await _searchTasks[tab.id]?.stop();
    final index = state.tabs.indexWhere((item) => item.id == tab.id);
    if (isClosed ||
        index < 0 ||
        state.tabs[index].search?.generation != search.generation) {
      return;
    }
    _emitSearchState(
      state.withTab(
        index,
        state.tabs[index].copyWith(search: search.copyWith(running: false)),
      ),
    );
    await _sortSearch(tab.id, search.generation, tab.sort, finished: true);
  }

  Future<void> _stopSearch(String id) async {
    _searchSorts.remove(id);
    _searchHits.remove(id);
    await _searchTasks.remove(id)?.close();
  }

  Future<void> _openSearch(
    int index,
    FindRequest request, {
    String? label,
    bool refreshing = false,
  }) async {
    final service = _find;
    final before = state.tabs.elementAtOrNull(index);
    if (service == null || before == null || isClosed) return;
    await _stopSearch(before.id);
    if (isClosed || state.tabs.elementAtOrNull(index)?.id != before.id) return;
    final generation = ++_searchGeneration;
    final search = PanelSearchState(
      request: request,
      generation: generation,
      label: label,
    );
    final tab = state.tabs[index];
    _emitSearchState(
      state.withTab(
        index,
        tab.copyWith(
          location: Location.native(request.root),
          search: search,
          loading: false,
          clearError: true,
          clearFlat: true,
          listing: refreshing
              ? tab.listing
              : Listing(
                  location: Location.native(request.root),
                  entries: const [],
                  watched: false,
                ),
          rows: refreshing ? null : const [],
          cursor: refreshing ? null : -1,
          selected: refreshing ? null : const {},
          clearRenaming: true,
          clearRange: true,
          clearVisual: true,
        ),
      ),
    );
    final hits = <FindHit>[];
    final seen = <String>{};
    _searchHits[tab.id] = hits;
    var finished = false;
    final paths = path.Context(
      style: RegExp(r'^(?:[a-zA-Z]:[/\\]|\\\\)').hasMatch(request.root)
          ? path.Style.windows
          : path.Style.posix,
    );
    final root = paths.normalize(request.root);
    late final TaskSession<FindUpdate> task;
    task = TaskSession<FindUpdate>(
      updates: service.updates,
      idOf: (update) => update.findId,
      isDone: (update) => update.done,
      cancel: service.cancel,
      onCleanupError: (error, stack) =>
          logger.warn('search cleanup', error: error, stackTrace: stack),
      onError: (error, stack) {
        logger.warn('search tab', error: error, stackTrace: stack);
        final at = state.tabs.indexWhere((item) => item.id == tab.id);
        if (isClosed ||
            at < 0 ||
            state.tabs[at].search?.generation != generation) {
          return;
        }
        final current = state.tabs[at];
        _emitSearchState(
          state.withTab(
            at,
            current.copyWith(
              search: current.search!.copyWith(running: false),
              error: error is FerryxException
                  ? error
                  : FerryxException(FerryxErrorKind.io, error.toString()),
            ),
          ),
        );
      },
      onUpdate: (update) {
        if (finished || isClosed) return;
        final at = state.tabs.indexWhere((item) => item.id == tab.id);
        if (at < 0 || state.tabs[at].search?.generation != generation) return;
        final current = state.tabs[at];
        var capped = current.search!.capped;
        for (final hit in update.hits) {
          if (!paths.isWithin(root, paths.normalize(hit.path))) continue;
          if (!seen.add(hit.path)) continue;
          if (hits.length == maxHits) {
            capped = true;
            break;
          }
          hits.add(hit);
        }
        final search = current.search!.copyWith(
          scanned: update.scanned,
          capped: capped,
          running: !(update.done || capped),
        );
        final updated = current.copyWith(search: search);
        _emitSearchState(
          state.withTab(
            at,
            refreshing
                ? updated
                : _withListing(
                    updated.copyWith(
                      listing: Listing(
                        location: updated.location,
                        entries: _searchEntries(hits, root, paths),
                        watched: false,
                      ),
                    ),
                  ),
          ),
        );
        if (update.done || capped) {
          finished = true;
          if (capped && !update.done) unawaited(task.stop());
          unawaited(
            _sortSearch(
              tab.id,
              generation,
              current.sort,
              finished: true,
              failure: update.error == null
                  ? null
                  : FerryxException(
                      FerryxErrorKind.invalidPattern,
                      update.error!,
                    ),
            ),
          );
        }
      },
    );
    _searchTasks[tab.id] = task;
    await task.start(() => service.start(request));
  }

  List<FileEntry> _searchEntries(
    List<FindHit> hits,
    String root,
    path.Context paths,
  ) => [
    for (final hit in hits)
      FileEntry(
        name: paths.basename(hit.path),
        path: hit.path,
        kind: hit.isDir ? EntryKind.directory : EntryKind.file,
        isDir: hit.isDir,
        size: hit.isDir ? null : hit.size,
        modified: hit.modified,
        extension: paths.extension(hit.path).replaceFirst(RegExp(r'^\.'), ''),
        folder: paths.equals(paths.dirname(hit.path), root)
            ? ''
            : paths
                  .relative(paths.dirname(hit.path), from: root)
                  .replaceAll(paths.separator, '/'),
        isHidden: paths.basename(hit.path).startsWith('.'),
      ),
  ];

  Future<void> _sortSearch(
    String id,
    int generation,
    SortOptions sort, {
    bool finished = false,
    FerryxException? failure,
  }) async {
    final hits = _searchHits[id];
    final service = _find;
    final at = state.tabs.indexWhere((item) => item.id == id);
    if (hits == null || service == null || at < 0 || isClosed) return;
    final before = state.tabs[at];
    if (before.search?.generation != generation) return;
    final revision = (_searchSorts[id] ?? 0) + 1;
    _searchSorts[id] = revision;
    _emitSearchState(state.withTab(at, before.copyWith(sort: sort)));
    final snapshot = List<FindHit>.of(hits, growable: false);
    try {
      final order = await service.order(snapshot, sort);
      if (isClosed || _searchSorts[id] != revision) return;
      final index = state.tabs.indexWhere((item) => item.id == id);
      if (index < 0 || state.tabs[index].search?.generation != generation) {
        return;
      }
      final current = state.tabs[index];
      if (current.sort != sort) {
        return await _sortSearch(
          id,
          generation,
          current.sort,
          finished: finished,
          failure: failure,
        );
      }
      if (order.length != snapshot.length ||
          order.toSet().length != snapshot.length ||
          order.any((index) => index < 0 || index >= snapshot.length)) {
        throw StateError('Incomplete search order');
      }
      final paths = path.Context(
        style:
            RegExp(r'^(?:[a-zA-Z]:[/\\]|\\\\)').hasMatch(current.location.path)
            ? path.Style.windows
            : path.Style.posix,
      );
      final entries = _searchEntries(
        [for (final index in order) snapshot[index]],
        paths.normalize(current.location.path),
        paths,
      );
      _emitSearchState(
        state.withTab(
          index,
          _withListing(
            current.copyWith(
              listing: Listing(
                location: current.location,
                entries: entries,
                watched: false,
              ),
              search: current.search!.copyWith(
                running: finished ? false : null,
              ),
              error: failure,
              clearError: failure == null,
            ),
          ),
        ),
      );
      if (finished && _stale.contains(id) && state.active?.id == id) {
        unawaited(_refreshTab(index));
      }
    } on Object catch (error, stack) {
      logger.warn('sort search', error: error, stackTrace: stack);
      final index = state.tabs.indexWhere((item) => item.id == id);
      if (isClosed ||
          index < 0 ||
          _searchSorts[id] != revision ||
          state.tabs[index].search?.generation != generation) {
        return;
      }
      final current = state.tabs[index];
      _emitSearchState(
        state.withTab(
          index,
          current.copyWith(
            search: current.search!.copyWith(running: finished ? false : null),
            error: error is FerryxException
                ? error
                : const FerryxException(FerryxErrorKind.io, ''),
          ),
        ),
      );
    }
  }
}
