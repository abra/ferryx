import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:preferences_service/preferences_service.dart';

/// The terminal's place in the window and its height under the panels.
@immutable
class TerminalDock extends Equatable {
  const TerminalDock({
    this.mode = TerminalPlace.hidden,
    this.lines = defaultLines,
    this.beforeFullWindow = TerminalPlace.hidden,
    this.host = TerminalHost.window,
    this.tabIndex = -1,
    this.tabSelected = true,
  });

  static const defaultLines = 12;
  static const minLines = 2;

  /// Where the terminal is ([TerminalPlace.overlapped]: [lines] tall).
  final TerminalPlace mode;

  /// Lines of text under the panels.
  final int lines;

  /// Where the terminal goes back to from the whole window.
  final TerminalPlace beforeFullWindow;
  final TerminalHost host;
  final int tabIndex;
  final bool tabSelected;

  bool get shown => mode != TerminalPlace.hidden;

  /// The panels are on screen.
  bool get panelsShown =>
      mode == TerminalPlace.hidden ||
      mode == TerminalPlace.overlapped ||
      mode == TerminalPlace.panelTab;

  bool get inPanel => host != TerminalHost.window && panelsShown;
  bool get visible => shown && (mode != TerminalPlace.panelTab || tabSelected);

  int tabPosition(int fileTabs) =>
      tabIndex < 0 ? fileTabs : tabIndex.clamp(0, fileTabs);

  TerminalDock copyWith({
    TerminalPlace? mode,
    int? lines,
    TerminalPlace? beforeFullWindow,
    TerminalHost? host,
    int? tabIndex,
    bool? tabSelected,
  }) => TerminalDock(
    mode: mode ?? this.mode,
    lines: lines ?? this.lines,
    beforeFullWindow: beforeFullWindow ?? this.beforeFullWindow,
    host: host ?? this.host,
    tabIndex: tabIndex ?? this.tabIndex,
    tabSelected: tabSelected ?? this.tabSelected,
  );

  @override
  List<Object?> get props => [
    mode,
    lines,
    beforeFullWindow,
    host,
    tabIndex,
    tabSelected,
  ];
}

/// The moves between the terminal's places; where the keys go after each
/// is the window's business.
class TerminalDockCubit extends Cubit<TerminalDock> {
  TerminalDockCubit([super.initialState = const TerminalDock()]);

  void restore(TerminalDock dock) => emit(dock);

  void moveTo(TerminalHost host, {bool asTab = false}) => emit(
    state.copyWith(
      host: host,
      mode: asTab && host != TerminalHost.window
          ? TerminalPlace.panelTab
          : TerminalPlace.overlapped,
      tabSelected: true,
    ),
  );

  void selectTab(bool selected) => emit(state.copyWith(tabSelected: selected));

  void moveTab(int index) => emit(state.copyWith(tabIndex: index));

  /// ⌃` (⌃⌥↑) on a hidden terminal: under the panels.
  void show() {
    if (state.mode == TerminalPlace.hidden) {
      emit(state.copyWith(mode: TerminalPlace.overlapped));
    }
  }

  /// From any place back to the panels alone.
  void hide() {
    if (state.mode != TerminalPlace.hidden) {
      emit(state.copyWith(mode: TerminalPlace.hidden));
    }
  }

  /// ⌃⌥O: the panels over the terminal go, or come back with it under
  /// them.
  void togglePanels() => emit(
    state.copyWith(
      mode:
          state.mode == TerminalPlace.panelsHidden ||
              state.mode == TerminalPlace.fullWindow
          ? TerminalPlace.overlapped
          : TerminalPlace.panelsHidden,
    ),
  );

  /// ⌥⌘O: the whole window, then back where it was.
  void toggleFullWindow() => emit(
    state.mode == TerminalPlace.fullWindow
        ? state.copyWith(mode: state.beforeFullWindow)
        : state.copyWith(
            mode: TerminalPlace.fullWindow,
            beforeFullWindow: state.mode,
          ),
  );

  /// The height under the panels, kept within [TerminalDock.minLines] and
  /// [maxLines].
  void setLines(int lines, {required int maxLines}) {
    const least = TerminalDock.minLines;
    final kept = lines.clamp(least, maxLines < least ? least : maxLines);
    if (kept != state.lines) emit(state.copyWith(lines: kept));
  }
}
