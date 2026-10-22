import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../panel/panel_side.dart';
import 'shelf.dart';

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
    this.shelf = Shelf.empty,
    this.shelfShown = false,
  });

  final PanelSide active;
  final bool singlePane;

  /// The left panel's share of the width.
  final double splitFraction;

  /// The operations cards show while operations run.
  final bool operationsShown;

  /// The keys are on the edge between the panels.
  final bool resizingPanels;

  /// Items gathered to copy or move together (Add to Shelf, Vim's `yy`
  /// and `dd`), for either panel.
  final Shelf shelf;

  /// The shelf's strip shows above the key hints.
  final bool shelfShown;

  WorkspaceState copyWith({
    PanelSide? active,
    bool? singlePane,
    double? splitFraction,
    bool? operationsShown,
    bool? resizingPanels,
    Shelf? shelf,
    bool? shelfShown,
  }) => WorkspaceState(
    active: active ?? this.active,
    singlePane: singlePane ?? this.singlePane,
    splitFraction: splitFraction ?? this.splitFraction,
    operationsShown: operationsShown ?? this.operationsShown,
    resizingPanels: resizingPanels ?? this.resizingPanels,
    shelf: shelf ?? this.shelf,
    shelfShown: shelfShown ?? this.shelfShown,
  );

  @override
  List<Object?> get props => [
    active,
    singlePane,
    splitFraction,
    operationsShown,
    resizingPanels,
    shelf,
    shelfShown,
  ];
}
