import 'package:component_library/component_library.dart';
import 'package:material_ui/material_ui.dart';

/// A terminal supplied by the workspace; file tabs retain their own state.
class PanelTerminal {
  const PanelTerminal({
    required this.child,
    required this.focusScope,
    required this.asTab,
    required this.selected,
    required this.tabIndex,
    required this.heightOf,
    required this.edge,
    required this.onSelectTab,
    required this.onCycleTab,
    required this.onReorder,
    required this.onClose,
    required this.onMenu,
  });

  final Widget child;
  final FocusScopeNode focusScope;
  final bool asTab;
  final bool selected;
  final int tabIndex;
  final double Function(BuildContext, double) heightOf;
  final Widget edge;
  final ValueChanged<int> onSelectTab;
  final ValueChanged<int> onCycleTab;
  final ValueChanged<int> onReorder;
  final VoidCallback onClose;
  final ValueChanged<Rect> onMenu;
}

/// Keeps the file list mounted while a terminal tab covers it.
class PanelTerminalBody extends StatelessWidget {
  const PanelTerminalBody({
    required this.files,
    required this.terminal,
    this.retainOnExit = true,
    super.key,
  });

  final Widget files;
  final PanelTerminal? terminal;
  final bool retainOnExit;

  @override
  Widget build(BuildContext context) {
    final terminal = this.terminal;
    return LayoutBuilder(
      builder: (context, size) {
        final tab = terminal?.asTab ?? false;
        final terminalSelected = tab && terminal!.selected;
        final height = terminal == null || tab
            ? 0.0
            : terminal.heightOf(context, size.maxHeight);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ExcludeFocus(
                    excluding: terminalSelected,
                    child: ExcludeSemantics(
                      excluding: terminalSelected,
                      child: Offstage(offstage: terminalSelected, child: files),
                    ),
                  ),
                  AppPresence(
                    visible: terminalSelected,
                    maintainState: true,
                    retainOnExit: retainOnExit,
                    animateInitially: true,
                    child: tab ? terminal!.child : null,
                  ),
                ],
              ),
            ),
            AppPresence(
              resize: true,
              retainOnExit: retainOnExit,
              animateInitially: true,
              child: terminal != null && !tab
                  ? SizedBox(
                      height: height,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(child: terminal.child),
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            height: AppSizes.resizeHandleWidth,
                            child: terminal.edge,
                          ),
                        ],
                      ),
                    )
                  : null,
            ),
          ],
        );
      },
    );
  }
}
