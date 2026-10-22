import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'drop_plan.dart';

/// What a panel asks of the window for files dragged out of its rows and
/// onto them; the window plans each drop and starts the operation.
class PanelDragHooks {
  const PanelDragHooks({
    required this.onDragStart,
    required this.onOver,
    required this.onLeave,
    required this.onDrop,
    required this.highlight,
  });

  /// Row [index] was dragged past the threshold; the pointer is at
  /// [global].
  final void Function(int index, Offset global) onDragStart;

  /// What dropping [drag] at [spot] would do (also lights the spot up).
  final FileDropOperation Function(DropSpot spot, FileDragInfo drag) onOver;
  final void Function(DropSpot spot) onLeave;
  final void Function(
    DropSpot spot,
    FileDragInfo drag,
    FileDropOperation operation,
  )
  onDrop;

  /// The spot of this panel files hang over and would go into, to light
  /// up: a folder row, or the panel itself.
  final ValueListenable<DropSpot?> highlight;
}

/// Where a drop on a row of the folder [location] goes: into the row's
/// folder, or the folder above for `..`; a file's row takes none (the drop
/// goes to the panel under it).
DropSpot? rowDropSpot(Location location, FileEntry entry) {
  if (entry.isParent) {
    final parent = location.parent;
    return parent == null ? null : DropSpot.row(parent, entry.name);
  }
  return entry.isDir
      ? DropSpot.row(location.join(entry.name), entry.name)
      : null;
}

/// The panel's rows as a place to drop files into its folder, ringed
/// while a drop would take them in.
class PanelDropZone extends StatelessWidget {
  const PanelDropZone({
    required this.hooks,
    required this.folder,
    required this.child,
    super.key,
  });

  final PanelDragHooks? hooks;
  final Location folder;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hooks = this.hooks;
    if (hooks == null) return child;
    final spot = DropSpot.panel(folder);
    return FileDropTarget(
      id: spot,
      onOver: (drag) => hooks.onOver(spot, drag),
      onLeave: () => hooks.onLeave(spot),
      onDrop: (drag, operation) => hooks.onDrop(spot, drag, operation),
      child: ValueListenableBuilder<DropSpot?>(
        valueListenable: hooks.highlight,
        builder: (context, lit, child) =>
            AppDropOutline(active: lit == spot, child: child!),
        child: child,
      ),
    );
  }
}

/// A folder row as a place to drop files into its folder.
class RowDropTarget extends StatelessWidget {
  const RowDropTarget({
    required this.spot,
    required this.hooks,
    required this.child,
    super.key,
  });

  final DropSpot? spot;
  final PanelDragHooks? hooks;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spot = this.spot;
    final hooks = this.hooks;
    if (spot == null || hooks == null) return child;
    return FileDropTarget(
      id: spot,
      onOver: (drag) => hooks.onOver(spot, drag),
      onLeave: () => hooks.onLeave(spot),
      onDrop: (drag, operation) => hooks.onDrop(spot, drag, operation),
      child: child,
    );
  }
}
