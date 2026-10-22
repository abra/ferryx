import 'package:component_library/component_library.dart';
import 'package:flutter/widgets.dart';

/// The integrated terminal as the composition root hands it to the window:
/// the panels never import the terminal feature.
class WorkspaceTerminal {
  const WorkspaceTerminal({required this.create, required this.builder});

  /// Makes the window's terminal; the window disposes it.
  final WorkspaceTerminalController Function() create;

  /// The terminal's view, placed as [view] says.
  final Widget Function(
    BuildContext context,
    WorkspaceTerminalController controller,
    WorkspaceTerminalView view,
  )
  builder;
}

/// What the window tells the terminal and hears from it.
abstract interface class WorkspaceTerminalController {
  /// The terminal came on screen with the active panel in [folder] (`null`
  /// inside an archive): the shell starts if none runs, or follows.
  void show(String? folder);

  /// The terminal left the screen; the shell runs on.
  void hide();

  /// The active panel is in [folder] now (`null` inside an archive).
  void followFolder(String? folder);

  /// Folders the shell went to by itself, for the active panel to open.
  Stream<String> get shellFolders;

  /// One line of the terminal's text, to size the terminal by lines.
  double lineHeight(BuildContext context);

  /// What the terminal takes besides its lines under the panels: its bar
  /// and the emulator's margins.
  double chromeHeight(BuildContext context);

  Future<void> dispose();
}

/// Where the window put the terminal, and what its bar's buttons do.
class WorkspaceTerminalView {
  const WorkspaceTerminalView({
    required this.focusNode,
    required this.panelsHidden,
    required this.fullWindow,
    required this.decor,
    required this.onHide,
    required this.onTogglePanels,
    required this.onToggleFullWindow,
  });

  /// The terminal's keys: the window moves the focus here.
  final FocusNode focusNode;
  final bool panelsHidden;
  final bool fullWindow;

  /// The window's buttons, for a bar in the window's top row.
  final WindowDecor decor;
  final VoidCallback onHide;
  final VoidCallback onTogglePanels;
  final VoidCallback onToggleFullWindow;
}
