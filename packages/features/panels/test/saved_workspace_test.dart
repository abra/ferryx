import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:panels_feature/src/workspace/saved_workspace.dart';
import 'package:preferences_service/preferences_service.dart';

void main() {
  const tabs = SavedPanel(
    tabs: [
      SavedTab(location: Location.native('/one'), layoutIndex: 3),
      SavedTab(
        location: Location.native('/two'),
        sort: SortOptions(field: SortField.size),
      ),
    ],
    activeIndex: 1,
  );
  test(
    'workspace serialization keeps both panels, layout and terminal placement',
    () {
      const saved = SavedWorkspace(
        left: tabs,
        right: tabs,
        active: PanelSide.right,
        singlePane: true,
        splitFraction: 0.65,
        arrangement: PanelArrangement.stacked,
        terminal: TerminalDock(
          mode: TerminalPlace.panelTab,
          host: TerminalHost.right,
          lines: 8,
          tabIndex: 1,
          tabSelected: false,
        ),
      );
      final restored = SavedWorkspace.fromJson(saved.toJson())!;
      expect(restored.left.encode(), saved.left.encode());
      expect(restored.right.encode(), saved.right.encode());
      expect(restored.active, saved.active);
      expect(restored.singlePane, saved.singlePane);
      expect(restored.splitFraction, saved.splitFraction);
      expect(restored.arrangement, saved.arrangement);
      expect(restored.terminal, saved.terminal);
      expect(restored.toJson().toString(), isNot(contains('password')));
    },
  );
  test(
    'malformed workspaces are rejected and out-of-range split is clamped',
    () {
      expect(SavedWorkspace.fromJson({}), isNull);
      final restored = SavedWorkspace.fromJson({
        'left': tabs.encode(),
        'right': tabs.encode(),
        'split': 99,
        'terminal': {'place': 'panelTab', 'host': 'window', 'lines': -1},
      })!;
      expect(restored.splitFraction, 0.8);
      expect(restored.terminal.host, TerminalHost.left);
      expect(restored.terminal.lines, TerminalPreferences.minLines);
    },
  );
}
