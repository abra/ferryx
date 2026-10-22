import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../panel/panel_side.dart';
import 'vim_register.dart';

/// The window around the panels: which panel is active, whether one or
/// two show, where the edge between them is.
@immutable
class WorkspaceState extends Equatable {
  const WorkspaceState({
    this.active = PanelSide.left,
    this.singlePane = false,
    this.splitFraction = 0.5,
    this.operationsShown = true,
    this.resizingPanels = false,
    this.register,
  });

  final PanelSide active;
  final bool singlePane;

  /// The left panel's share of the width.
  final double splitFraction;

  /// The operations cards show while operations run.
  final bool operationsShown;

  /// The keys are on the edge between the panels.
  final bool resizingPanels;

  /// What Vim's `yy` or `dd` took, for `p` in either panel.
  final VimRegister? register;

  WorkspaceState copyWith({
    PanelSide? active,
    bool? singlePane,
    double? splitFraction,
    bool? operationsShown,
    bool? resizingPanels,
    VimRegister? register,
    bool clearRegister = false,
  }) => WorkspaceState(
    active: active ?? this.active,
    singlePane: singlePane ?? this.singlePane,
    splitFraction: splitFraction ?? this.splitFraction,
    operationsShown: operationsShown ?? this.operationsShown,
    resizingPanels: resizingPanels ?? this.resizingPanels,
    register: clearRegister ? null : (register ?? this.register),
  );

  @override
  List<Object?> get props => [
    active,
    singlePane,
    splitFraction,
    operationsShown,
    resizingPanels,
    register,
  ];
}
