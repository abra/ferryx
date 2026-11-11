import 'package:flutter_bloc/flutter_bloc.dart';

import '../panel/panel_side.dart';
import 'shelf.dart';
import 'workspace_state.dart';

/// The window's own choices; the panels keep their own state.
class WorkspaceCubit extends Cubit<WorkspaceState> {
  WorkspaceCubit({
    PanelSide active = PanelSide.left,
    bool singlePane = false,
    double splitFraction = 0.5,
    bool operationsShown = true,
  }) : super(
         WorkspaceState(
           active: active,
           singlePane: singlePane,
           splitFraction: splitFraction,
           operationsShown: operationsShown,
         ),
       );

  /// The split stays within this range, so neither panel vanishes by a
  /// drag; single-pane mode is a choice of its own.
  static const double minFraction = 0.2;
  static const double maxFraction = 0.8;

  void activate(PanelSide side) {
    if (state.active != side) emit(state.copyWith(active: side));
  }

  void restoreLayout({
    required PanelSide active,
    required bool singlePane,
    required double splitFraction,
  }) => emit(
    state.copyWith(
      active: active,
      singlePane: singlePane,
      splitFraction: splitFraction.clamp(minFraction, maxFraction),
      resizingPanels: false,
    ),
  );

  void switchPanel() => activate(state.active.opposite);

  void toggleSinglePane() =>
      emit(state.copyWith(singlePane: !state.singlePane));

  void setSplit(double fraction) => emit(
    state.copyWith(splitFraction: fraction.clamp(minFraction, maxFraction)),
  );

  void moveSplit(double delta) => setSplit(state.splitFraction + delta);

  void toggleOperations() =>
      emit(state.copyWith(operationsShown: !state.operationsShown));

  void setResizing(bool resizing) {
    if (state.resizingPanels != resizing) {
      emit(state.copyWith(resizingPanels: resizing));
    }
  }

  // ─── The shelf ───

  /// Puts [items] on the shelf, after what is there, or in its place with
  /// [replace] (Vim's `yy` and `dd`). The strip shows when the shelf was
  /// empty.
  void shelve(List<ShelfItem> items, {bool replace = false}) {
    if (items.isEmpty) return;
    final shelf = (replace ? Shelf.empty : state.shelf).add(items);
    emit(
      state.copyWith(
        shelf: shelf,
        shelfShown: state.shelf.isEmpty ? true : null,
      ),
    );
  }

  /// Takes [paths] off the shelf; an emptied shelf hides its strip.
  void unshelve(Iterable<String> paths) =>
      _setShelf(state.shelf.without(paths));

  /// `uy`, Clear.
  void clearShelf() => _setShelf(Shelf.empty);

  /// Marks the items gone from the disk, and the others back.
  void markMissing(Set<String> missing) {
    final shelf = state.shelf.withMissing(missing);
    if (shelf != state.shelf) emit(state.copyWith(shelf: shelf));
  }

  void showShelf(bool shown) {
    if (state.shelfShown != shown) emit(state.copyWith(shelfShown: shown));
  }

  void _setShelf(Shelf shelf) {
    if (shelf == state.shelf) return;
    emit(
      state.copyWith(
        shelf: shelf,
        shelfShown: shelf.isEmpty ? false : null,
      ),
    );
  }
}
