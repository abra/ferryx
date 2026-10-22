import 'package:flutter_bloc/flutter_bloc.dart';

import '../panel/panel_side.dart';
import 'vim_register.dart';
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

  /// Vim's `yy` / `dd`: the rows taken, for `p`.
  void takeRegister(VimRegister register) =>
      emit(state.copyWith(register: register));

  /// `uy`, or a cut register pasted.
  void clearRegister() {
    if (state.register != null) emit(state.copyWith(clearRegister: true));
  }
}
