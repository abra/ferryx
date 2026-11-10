import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/panels_feature.dart';

import 'support/workspace_harness.dart';

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);
  late WorkspaceHarness h;
  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp();
  });
  tearDown(() => h.tearDown());

  for (final stacked in [false, true]) {
    for (final single in [false, true]) {
      testWidgets(
        '${stacked ? 'stacked' : 'side by side'}, ${single ? 'single' : 'two'} panels round only window corners',
        (tester) async {
          unawaited(
            h.preferences.update(
              (p) => p.copyWith(
                panelArrangement: stacked
                    ? PanelArrangement.stacked
                    : PanelArrangement.sideBySide,
                singlePane: single,
              ),
            ),
          );
          await h.pump(tester, decor: const WindowDecor(cornerRadius: 16));
          final panels = tester
              .widgetList<PanelView>(find.byType(PanelView))
              .toList();
          expect(panels.length, single ? 1 : 2);
          const rounded = Radius.circular(16);
          expect(
            panels.first.focusBorderRadius,
            BorderRadius.only(
              topLeft: rounded,
              topRight: stacked || single ? rounded : Radius.zero,
            ),
          );
          if (!single) {
            expect(
              panels.last.focusBorderRadius,
              BorderRadius.only(topRight: stacked ? Radius.zero : rounded),
            );
          }
          for (final panel in panels) {
            final frame = tester.widget<AppFocusArea>(
              find
                  .descendant(
                    of: find.byWidget(panel),
                    matching: find.byType(AppFocusArea),
                  )
                  .first,
            );
            expect(frame.borderRadius, panel.focusBorderRadius);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
