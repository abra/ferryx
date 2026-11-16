import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:domain_models/domain_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'document_format.dart';
import 'hex_format.dart';
import 'text_preview_format.dart';
import 'text_preview_data.dart';
import 'source_syntax.dart';
import 'text_window.dart';
import 'viewer_source.dart';
import 'viewer_state.dart';
import 'window_search.dart';

/// The viewer over one [ViewerSource]: a window of the file at a time,
/// the mode, the find.
class ViewerCubit extends Cubit<ViewerState> {
  ViewerCubit({
    required this.source,
    required bool wrap,
    ViewerMode mode = ViewerMode.text,
    this.windowSize = defaultWindowSize,
    this.highlighter = highlightSource,
    this.windowDecoder = prepareTextWindow,
    WindowSearcher? searcher,
  }) : _findWorker = searcher ?? WindowSearchWorker(),
       super(ViewerState(mode: mode, wrap: wrap));

  /// How much of a file is read at once.
  static const int defaultWindowSize = 2 * 1024 * 1024;

  final ViewerSource source;
  final int windowSize;
  final SourceHighlighter highlighter;
  final TextWindowDecoder windowDecoder;
  int _reads = 0;
  bool _hasWindow = false;
  final WindowSearcher _findWorker;
  Timer? _findTimer;
  int _findRevision = 0;

  /// Reads the window at [offset] (the first by default).
  Future<void> load({
    int offset = 0,
    ViewerScroll scroll = ViewerScroll.top,
  }) async {
    final read = ++_reads;
    _cancelFind();
    emit(_withoutMatches(state.copyWith(loading: true, clearError: true)));
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
        var markdown = '';
        TextPreviewData? preview;
        final format = textPreviewFormatOf(source.displayName);
        if (format != null && size > format.maxInputBytes) {
          preview = const FailedTextPreview(TextPreviewFailure.limit);
        } else if (format != null && size > 0) {
          final bytes = await source.read(0, size);
          if (read != _reads || isClosed) return;
          if (format == TextPreviewFormat.markdown) {
            markdown = utf8.decode(bytes, allowMalformed: true);
          } else {
            preview = await _preparePreview(bytes, format, read);
            if (read != _reads || isClosed) return;
          }
        }
        emit(
          state.copyWith(
            size: size,
            markdown: markdown,
            textPreview: preview,
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
      final window = await windowDecoder(bytes);
      if (read != _reads || isClosed) return;
      _hasWindow = true;
      _updateMatches(
        state.copyWith(
          size: size,
          offset: start,
          bytes: bytes,
          generation: state.generation + 1,
          window: window,
          syntax: const [],
          loading: false,
          clearError: true,
          scroll: scroll,
          scrollRequest: state.scrollRequest + 1,
        ),
      );
      if (state.mode == ViewerMode.text) unawaited(_highlight(read));
    } on FerryxException catch (error) {
      if (read != _reads || isClosed) return;
      emit(state.copyWith(loading: false, error: error));
    }
  }

  Future<TextPreviewData?> _preparePreview(
    Uint8List bytes,
    TextPreviewFormat format,
    int read,
  ) async {
    try {
      final converter = format.converter;
      if (converter != null) {
        final file = source;
        if (file is! ConvertedDocumentSource) {
          return const FailedTextPreview(TextPreviewFailure.malformed);
        }
        final html = await file.renderTextDocument(bytes, converter);
        if (read != _reads || isClosed) return null;
        return await prepareHtml(html, embeddedImages: format.office);
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      return await (format == TextPreviewFormat.html
          ? prepareHtml(text)
          : prepareTable(text, tsv: format == TextPreviewFormat.tsv));
    } on Object {
      return const FailedTextPreview(TextPreviewFailure.malformed);
    }
  }

  Future<void> _highlight(int read) async {
    final language = syntaxLanguageOf(source.displayName);
    if (language == null ||
        state.bytes.isEmpty ||
        state.offset != 0 ||
        state.size > maxSyntaxBytes ||
        state.window.binary) {
      return;
    }
    try {
      final syntax = await highlighter(
        language,
        state.window.lines.join('\n'),
      );
      if (read != _reads || isClosed || state.mode != ViewerMode.text) return;
      emit(
        state.copyWith(
          syntax: syntax,
          syntaxRevision: state.syntaxRevision + 1,
        ),
      );
    } on Object {
      // Highlighting must never prevent reading the original source.
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
    _updateMatches(
      state.copyWith(
        mode: mode,
        loading: false,
        clearError: true,
        findShown: mode == ViewerMode.preview ? false : state.findShown,
      ),
    );
    if (mode == ViewerMode.preview || !_hasWindow) {
      unawaited(load());
    } else if (mode == ViewerMode.text && state.syntax.isEmpty) {
      unawaited(_highlight(_reads));
    }
  }

  void toggleWrap() => emit(state.copyWith(wrap: !state.wrap));

  // ─── Find ───

  void showFind() => emit(state.copyWith(findShown: true));

  void hideFind() => _updateMatches(
    state.copyWith(findShown: false, findQuery: ''),
  );

  void setFindQuery(String query) {
    if (query == state.findQuery) return;
    _updateMatches(
      state.copyWith(findQuery: query),
      reveal: true,
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

  ViewerState _withoutMatches(ViewerState base) => base.copyWith(
    matches: const [],
    matchesByLine: const {},
    currentMatch: -1,
    findSearching: false,
    findCapped: false,
    findFailed: false,
  );

  void _cancelFind() {
    _findRevision++;
    _findTimer?.cancel();
    _findTimer = null;
    _findWorker.cancel();
  }

  void _updateMatches(ViewerState base, {bool reveal = false}) {
    _cancelFind();
    final next = _withoutMatches(base);
    if (base.findQuery.isEmpty ||
        base.mode == ViewerMode.preview ||
        base.loading) {
      emit(next);
      return;
    }
    final hex = base.mode == ViewerMode.hex;
    if (base.bytes.length < 128 * 1024) {
      _publishMatches(
        next,
        searchWindow(
          lines: base.window.lines,
          bytes: base.bytes,
          query: base.findQuery,
          hex: hex,
        ),
        reveal: reveal,
      );
      return;
    }
    emit(next.copyWith(findSearching: true));
    final revision = _findRevision;
    // Coalesce typing before starting an isolate. New input cancels an
    // already-running worker too; it never accumulates obsolete searches.
    _findTimer = Timer(const Duration(milliseconds: 100), () {
      _findTimer = null;
      unawaited(_findMatches(base, revision, reveal));
    });
  }

  Future<void> _findMatches(ViewerState base, int revision, bool reveal) async {
    try {
      final hex = base.mode == ViewerMode.hex;
      final result = await _findWorker.search(
        lines: hex ? const [] : base.window.lines,
        bytes: hex ? base.bytes : Uint8List(0),
        query: base.findQuery,
        hex: hex,
      );
      if (isClosed || revision != _findRevision || result == null) return;
      _publishMatches(state, result, reveal: reveal);
    } on Object catch (error, stack) {
      if (isClosed || revision != _findRevision) return;
      addError(error, stack);
      emit(state.copyWith(findSearching: false, findFailed: true));
    }
  }

  void _publishMatches(
    ViewerState base,
    WindowSearchResult result, {
    required bool reveal,
  }) {
    emit(
      base.copyWith(
        matches: result.matches,
        matchesByLine: matchesByLine(result.matches),
        currentMatch: result.matches.isEmpty ? -1 : 0,
        findSearching: false,
        findCapped: result.capped,
        findFailed: false,
        scroll: reveal && result.matches.isNotEmpty ? ViewerScroll.match : null,
        scrollRequest: reveal && result.matches.isNotEmpty
            ? base.scrollRequest + 1
            : null,
      ),
    );
  }

  @override
  Future<void> close() {
    ++_reads;
    _cancelFind();
    return super.close();
  }
}
