import 'package:domain_models/domain_models.dart';
import 'package:preferences_service/preferences_service.dart';

import '../panel/panel_side.dart';
import '../panel/saved_panel.dart';
import 'terminal_dock.dart';

/// Layout and navigation state, never the terminal's process or credentials.
class SavedWorkspace {
  const SavedWorkspace({
    required this.left,
    required this.right,
    required this.active,
    required this.singlePane,
    required this.splitFraction,
    required this.arrangement,
    required this.terminal,
  });
  final SavedPanel left, right;
  final PanelSide active;
  final bool singlePane;
  final double splitFraction;
  final PanelArrangement arrangement;
  final TerminalDock terminal;

  Map<String, Object?> toJson() => {
    'left': left.encode(),
    'right': right.encode(),
    'active': active.name,
    'singlePane': singlePane,
    'split': splitFraction,
    'arrangement': arrangement.name,
    'terminal': {
      'place': terminal.mode.name,
      'beforeFullWindow': terminal.beforeFullWindow.name,
      'host': terminal.host.name,
      'lines': terminal.lines,
      'tabIndex': terminal.tabIndex,
      'tabSelected': terminal.tabSelected,
    },
  };

  static SavedWorkspace? fromJson(Map<String, Object?> json) {
    final rawLeft = json['left'], rawRight = json['right'];
    if (rawLeft is! String || rawRight is! String) return null;
    final left = SavedPanel.decode(rawLeft),
        right = SavedPanel.decode(rawRight);
    if (left == null ||
        right == null ||
        left.tabs.length > 64 ||
        right.tabs.length > 64) {
      return null;
    }
    final split = json['split'];
    final prefs = TerminalPreferences.fromJson(json['terminal']);
    return SavedWorkspace(
      left: left,
      right: right,
      active: PanelSide.values.asNameMap()[json['active']] ?? PanelSide.left,
      singlePane: json['singlePane'] == true,
      splitFraction: split is num && split.isFinite
          ? split.toDouble().clamp(0.2, 0.8)
          : 0.5,
      arrangement:
          PanelArrangement.values.asNameMap()[json['arrangement']] ??
          PanelArrangement.byWindowShape,
      terminal: TerminalDock(
        mode: prefs.place,
        beforeFullWindow: switch (json['terminal']) {
          {'beforeFullWindow': final String place} =>
            TerminalPlace.values.asNameMap()[place] == TerminalPlace.fullWindow
                ? TerminalPlace.hidden
                : TerminalPlace.values.asNameMap()[place] ??
                      TerminalPlace.hidden,
          _ => TerminalPlace.hidden,
        },
        host:
            prefs.place == TerminalPlace.panelTab &&
                prefs.host == TerminalHost.window
            ? TerminalHost.left
            : prefs.host,
        lines: prefs.lines,
        tabIndex: prefs.tabIndex,
        tabSelected: prefs.tabSelected,
      ),
    );
  }
}
