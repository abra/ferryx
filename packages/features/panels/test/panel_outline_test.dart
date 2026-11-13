import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:panels_feature/src/panel/panel_footer.dart';
import 'package:panels_feature/src/panel/rows_header.dart';

import 'support/workspace_harness.dart';

Finder _frame(Finder panel) => find
    .descendant(
      of: panel,
      matching: find.byWidgetPredicate(
        (widget) => widget is AppFocusFrame && widget.visible,
      ),
    )
    .first;

Finder _outline(Finder frame) =>
    find.descendant(of: frame, matching: find.byType(DecoratedBox)).last;

AppRoundedRectangleBorder _shape(WidgetTester tester, Finder frame) =>
    (tester.widget<DecoratedBox>(_outline(frame)).decoration as ShapeDecoration)
            .shape
        as AppRoundedRectangleBorder;

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);
  late WorkspaceHarness h;
  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp();
  });
  tearDown(() => h.tearDown());

  for (final brightness in Brightness.values) {
    for (final stacked in [false, true]) {
      for (final single in [false, true]) {
        testWidgets(
          '${brightness.name}, stacked=$stacked, single=$single: '
          'frame starts below headings and ends above the footer in every view',
          (tester) async {
            await tester.runAsync(
              () => h.preferences.update(
                (p) => p.copyWith(
                  panelArrangement: stacked
                      ? PanelArrangement.stacked
                      : PanelArrangement.sideBySide,
                  singlePane: single,
                ),
              ),
            );
            await h.pump(
              tester,
              decor: const WindowDecor(cornerRadius: 16),
              brightness: brightness,
              textScale: 1.5,
            );
            final panels = find.byType(PanelView);
            expect(panels, findsNWidgets(single ? 1 : 2));
            for (final layout in [2, 0, PanelLayout.thumbnailIndex]) {
              for (final element in panels.evaluate()) {
                element.read<PanelCubit>().setLayout(layout);
              }
              await tester.pumpAndSettle();
              for (final panel in tester.widgetList<PanelView>(panels)) {
                final panelFinder = find.byWidget(panel);
                final frame = _frame(panelFinder);
                final bounds = tester.getRect(_outline(frame));
                final footer = tester.getRect(
                  find.descendant(
                    of: panelFinder,
                    matching: find.byType(PanelFooter),
                  ),
                );
                final scope = tester.widget<AppFocusArea>(
                  find.descendant(
                    of: panelFinder,
                    matching: find.byType(AppFocusArea),
                  ),
                );
                expect(scope.showOutline, isFalse);
                expect(bounds.left, tester.getRect(panelFinder).left);
                expect(bounds.right, tester.getRect(panelFinder).right);
                expect(bounds.bottom, footer.top);
                expect(bounds.overlaps(footer), isFalse);
                final heading = find.descendant(
                  of: panelFinder,
                  matching: find.byType(RowsHeader),
                );
                if (layout == PanelLayout.thumbnailIndex) {
                  expect(heading, findsNothing);
                  expect(bounds.top, tester.getRect(frame).top);
                } else {
                  expect(bounds.top, tester.getRect(heading).bottom);
                }
                final shape = _shape(tester, frame);
                expect(shape.borderRadius, BorderRadius.zero);
                expect(shape.side.width, AppSizes.focusFrameWidth);
                expect(shape.side.strokeAlign, BorderSide.strokeAlignInside);
                final context = tester.element(frame);
                expect(
                  shape.side.color,
                  panel.active
                      ? context.appColors.accent
                      : const Color(0x00000000),
                );
              }
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final vim in [false, true]) {
    testWidgets('Vim=$vim: Tab and pointer move only the content frame; '
        'tabs and the command line retain the panel focus', (tester) async {
      await tester.runAsync(
        () => h.preferences.update((p) => p.copyWith(vimMode: vim)),
      );
      await h.pump(tester);
      final panels = find.byType(PanelView);
      final left = panels.first;
      final right = panels.last;
      final leftCubit = tester.element(left).read<PanelCubit>();
      leftCubit.moveCursor(1);
      leftCubit.toggleSelection();
      await tester.pump();
      final selected = leftCubit.state.active!.selected;
      final rows = find.descendant(of: left, matching: find.byType(RowsHeader));
      final bounds = tester.getRect(_outline(_frame(left)));
      final accent = tester.element(left).appColors.accent;
      expect(_shape(tester, _frame(left)).side.color, accent);

      await h.press(tester, LogicalKeyboardKey.tab);
      expect(_shape(tester, _frame(left)).side.color.a, 0);
      expect(_shape(tester, _frame(right)).side.color, accent);
      await tester.tapAt(tester.getRect(_outline(_frame(left))).center);
      await tester.pumpAndSettle();
      expect(_shape(tester, _frame(left)).side.color, accent);
      expect(_shape(tester, _frame(right)).side.color.a, 0);
      expect(tester.getRect(_outline(_frame(left))), bounds);

      await tester.runAsync(() => leftCubit.newTab());
      await tester.pumpAndSettle();
      final strip = find.descendant(
        of: left,
        matching: find.byType(AppTabStrip),
      );
      expect(
        tester.getRect(strip).bottom,
        lessThanOrEqualTo(tester.getRect(_outline(_frame(left))).top),
      );
      final tab = tester.widget<AppTabStrip>(strip);
      tab.onSelect(0);
      await tester.pumpAndSettle();
      expect(leftCubit.state.active!.selected, selected);
      expect(_shape(tester, _frame(left)).side.color, accent);
      expect(
        tester.getRect(_outline(_frame(left))).top,
        tester.getRect(rows).bottom,
      );
      if (vim) {
        await h.press(
          tester,
          LogicalKeyboardKey.semicolon,
          shift: true,
          character: ':',
        );
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'vim command line',
        );
        expect(_shape(tester, _frame(left)).side.color, accent);
        final footer = tester.getRect(
          find.descendant(of: left, matching: find.byType(PanelFooter)),
        );
        expect(tester.getRect(_outline(_frame(left))).bottom, footer.top);
        expect(
          tester.getRect(_outline(_frame(left))).overlaps(footer),
          isFalse,
        );
        await h.press(tester, LogicalKeyboardKey.escape);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
