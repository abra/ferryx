import 'dart:typed_data';

import 'package:domain_models/domain_models.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import 'text_window.dart';

enum ViewerMode { text, hex, preview }

/// Where the view scrolls after a change: a new window's top or bottom,
/// or the current match.
enum ViewerScroll { top, bottom, match }

@immutable
class ViewerState extends Equatable {
  ViewerState({
    required this.mode,
    required this.wrap,
    this.size = 0,
    this.offset = 0,
    Uint8List? bytes,
    this.generation = 0,
    this.window = DecodedWindow.empty,
    this.findShown = false,
    this.findQuery = '',
    this.matches = const [],
    this.matchesByLine = const {},
    this.currentMatch = -1,
    this.loading = true,
    this.error,
    this.scroll = ViewerScroll.top,
    this.scrollRequest = 0,
  }) : bytes = bytes ?? Uint8List(0);

  final ViewerMode mode;
  final bool wrap;

  /// The file's length.
  final int size;

  /// Where the window read starts in the file.
  final int offset;

  /// The window read; not part of equality ([generation] stands for it).
  final Uint8List bytes;

  /// Bumped on every read.
  final int generation;
  final DecodedWindow window;
  final bool findShown;
  final String findQuery;
  final List<ViewerMatch> matches;
  final Map<int, List<ViewerMatch>> matchesByLine;

  /// Index into [matches]; -1 while there is none.
  final int currentMatch;
  final bool loading;
  final FerryxException? error;
  final ViewerScroll scroll;

  /// Bumped when the view should scroll to [scroll].
  final int scrollRequest;

  int get windowEnd => offset + bytes.length;

  /// Only a part of the file is shown.
  bool get windowed => bytes.length < size;

  bool get hasNext => windowEnd < size;

  bool get hasPrevious => offset > 0;

  ViewerMatch? get current => currentMatch >= 0 && currentMatch < matches.length
      ? matches[currentMatch]
      : null;

  ViewerState copyWith({
    ViewerMode? mode,
    bool? wrap,
    int? size,
    int? offset,
    Uint8List? bytes,
    int? generation,
    DecodedWindow? window,
    bool? findShown,
    String? findQuery,
    List<ViewerMatch>? matches,
    Map<int, List<ViewerMatch>>? matchesByLine,
    int? currentMatch,
    bool? loading,
    FerryxException? error,
    bool clearError = false,
    ViewerScroll? scroll,
    int? scrollRequest,
  }) => ViewerState(
    mode: mode ?? this.mode,
    wrap: wrap ?? this.wrap,
    size: size ?? this.size,
    offset: offset ?? this.offset,
    bytes: bytes ?? this.bytes,
    generation: generation ?? this.generation,
    window: window ?? this.window,
    findShown: findShown ?? this.findShown,
    findQuery: findQuery ?? this.findQuery,
    matches: matches ?? this.matches,
    matchesByLine: matchesByLine ?? this.matchesByLine,
    currentMatch: currentMatch ?? this.currentMatch,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    scroll: scroll ?? this.scroll,
    scrollRequest: scrollRequest ?? this.scrollRequest,
  );

  @override
  List<Object?> get props => [
    mode,
    wrap,
    size,
    offset,
    generation,
    window.lines.length,
    window.binary,
    findShown,
    findQuery,
    matches,
    currentMatch,
    loading,
    error,
    scroll,
    scrollRequest,
  ];
}
