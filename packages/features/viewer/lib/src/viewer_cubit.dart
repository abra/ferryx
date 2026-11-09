import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:domain_models/domain_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'document_format.dart';
import 'hex_format.dart';
import 'text_window.dart';
import 'viewer_source.dart';
import 'viewer_state.dart';

/// The viewer over one [ViewerSource]: a window of the file at a time,
/// the mode, the find.
class ViewerCubit extends Cubit<ViewerState> {
  ViewerCubit({
    required this.source,
    required bool wrap,
    ViewerMode mode = ViewerMode.text,
    this.windowSize = defaultWindowSize,
  }) : super(ViewerState(mode: mode, wrap: wrap));

  /// How much of a file is read at once.
  static const int defaultWindowSize = 2 * 1024 * 1024;

  final ViewerSource source;
  final int windowSize;
  int _reads = 0;
  bool _hasWindow = false;

  /// Reads the window at [offset] (the first by default).
  Future<void> load({
    int offset = 0,
    ViewerScroll scroll = ViewerScroll.top,
  }) async {
    final read = ++_reads;
    emit(state.copyWith(loading: true, clearError: true));
    try {
      // Document decoders own their reads and cancellation. Do not read or
      // decode a binary text window before the first document page.
      if (state.mode == ViewerMode.preview &&
          isDocumentName(source.displayName)) {
        emit(
          state.copyWith(
            generation: state.generation + 1,
            loading: false,
          ),
        );
        return;
      }
      final size = await source.size();
      if (read != _reads || isClosed) return;
      if (state.mode == ViewerMode.preview) {
        emit(
          state.copyWith(
            size: size,
            generation: state.generation + 1,
            loading: false,
          ),
        );
        return;
      }
      final start = math.max(0, math.min(offset, size));
      final bytes = size == 0
          ? Uint8List(0)
          : await source.read(start, math.min(windowSize, size - start));
      if (read != _reads || isClosed) return;
      final window = decodeWindow(bytes);
      _hasWindow = true;
      emit(
        _withMatches(
          state.copyWith(
            size: size,
            offset: start,
            bytes: bytes,
            generation: state.generation + 1,
            window: window,
            loading: false,
            clearError: true,
            scroll: scroll,
            scrollRequest: state.scrollRequest + 1,
          ),
          keepCurrent: false,
        ),
      );
    } on FerryxException catch (error) {
      if (read != _reads || isClosed) return;
      emit(state.copyWith(loading: false, error: error));
    }
  }

  /// Reads the shown window again (⌘R, or the file changed).
  Future<void> refresh() {
    _hasWindow = false;
    return load(offset: state.offset, scroll: ViewerScroll.top);
  }

  Future<void> loadNext() async {
    if (!state.hasNext) return;
    await load(offset: state.windowEnd);
  }

  Future<void> loadPrevious() async {
    if (!state.hasPrevious) return;
    await load(
      offset: math.max(0, state.offset - windowSize),
      scroll: ViewerScroll.bottom,
    );
  }

  /// The window that ends at the file's end, scrolled to its bottom.
  Future<void> loadLast() async {
    await load(
      offset: math.max(0, state.size - windowSize),
      scroll: ViewerScroll.bottom,
    );
  }

  /// A window from [offset]; hex mode keeps its rows on multiples of 16.
  Future<void> goTo(int offset) async {
    var start = math.min(math.max(offset, 0), math.max(0, state.size - 1));
    if (state.mode == ViewerMode.hex) start -= start % hexRowLength;
    await load(offset: start);
  }

  void setMode(ViewerMode mode) {
    if (mode == state.mode) return;
    ++_reads;
    emit(
      _withMatches(
        state.copyWith(
          mode: mode,
          loading: false,
          clearError: true,
          findShown: mode == ViewerMode.preview ? false : state.findShown,
        ),
        keepCurrent: false,
      ),
    );
    if (mode == ViewerMode.preview || !_hasWindow) unawaited(load());
  }

  void toggleWrap() => emit(state.copyWith(wrap: !state.wrap));

  // ─── Find ───

  void showFind() => emit(state.copyWith(findShown: true));

  void hideFind() => emit(
    _withMatches(
      state.copyWith(findShown: false, findQuery: ''),
      keepCurrent: false,
    ),
  );

  void setFindQuery(String query) {
    if (query == state.findQuery) return;
    final next = _withMatches(
      state.copyWith(findQuery: query),
      keepCurrent: false,
    );
    emit(
      next.matches.isEmpty
          ? next
          : next.copyWith(
              scroll: ViewerScroll.match,
              scrollRequest: next.scrollRequest + 1,
            ),
    );
  }

  void findNext() => _step(1);

  void findPrevious() => _step(-1);

  void _step(int delta) {
    final count = state.matches.length;
    if (count == 0) return;
    final current = state.currentMatch < 0
        ? (delta > 0 ? 0 : count - 1)
        : (state.currentMatch + delta + count) % count;
    emit(
      state.copyWith(
        currentMatch: current,
        scroll: ViewerScroll.match,
        scrollRequest: state.scrollRequest + 1,
      ),
    );
  }

  /// [state] with its matches found again in its window and mode; the
  /// current match goes to the first unless kept.
  ViewerState _withMatches(ViewerState state, {required bool keepCurrent}) {
    final matches = switch (state.mode) {
      ViewerMode.text => findInLines(state.window.lines, state.findQuery),
      ViewerMode.hex => findInBytes(state.bytes, state.findQuery),
      ViewerMode.preview => const <ViewerMatch>[],
    };
    final current = matches.isEmpty
        ? -1
        : keepCurrent &&
              state.currentMatch >= 0 &&
              state.currentMatch < matches.length
        ? state.currentMatch
        : 0;
    return state.copyWith(
      matches: matches,
      matchesByLine: matchesByLine(matches),
      currentMatch: current,
    );
  }
}
