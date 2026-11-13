import 'package:domain_models/domain_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:panels_feature/src/panel/rows_brief.dart';
import 'package:panels_feature/src/panel/rows_list.dart';
import 'package:panels_feature/src/panel/rows_thumbnails.dart';

import 'support/workspace_harness.dart';

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);
  late WorkspaceHarness h;
  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp();
    h.folders['/home/docs'] = [
      for (var i = 0; i < 500; i++)
        h.file('/home/docs', 'file-${i.toString().padLeft(3, '0')}.txt'),
    ];
  });
  tearDown(() => h.tearDown());

  Finder panel() => find.byType(PanelView).first;
  Finder rows() => find.descendant(
    of: panel(),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is RowsBrief || widget is RowsList || widget is RowsThumbnails,
    ),
  );
  Finder viewport() =>
      find.descendant(of: rows(), matching: find.byType(Scrollable));
  ScrollPosition position(WidgetTester tester) =>
      tester.state<ScrollableState>(viewport()).position;
  PanelCubit cubit(WidgetTester tester) =>
      tester.element(panel()).read<PanelCubit>();
  Rect cursor(WidgetTester tester) => tester.getRect(
    find.byKey(tester.widget<PanelView>(panel()).cursorRowKey!),
  );

  Future<void> mount(
    WidgetTester tester,
    int layout, {
    bool vim = false,
  }) async {
    await tester.runAsync(
      () => h.preferences.update((p) => p.copyWith(vimMode: vim)),
    );
    await h.pump(tester, size: const Size(1200, 600));
    cubit(tester).setLayout(layout);
    await tester.pumpAndSettle();
  }

  /// Place the cursor at the last fully visible column/row, without scrolling.
  Future<void> edge(WidgetTester tester, int layout) async {
    final c = cubit(tester);
    final step = layout == 0 || layout == 1
        ? c.geometry.rowsPerColumn
        : c.geometry.columnsPerRow;
    c.moveCursorTo(c.geometry.rowsPerPage - step);
    await tester.pumpAndSettle();
  }

  Future<void> move(WidgetTester tester, int layout, bool vim) async {
    final horizontal = layout == 0 || layout == 1;
    await tester.sendKeyEvent(
      vim
          ? (horizontal ? LogicalKeyboardKey.keyL : LogicalKeyboardKey.keyJ)
          : (horizontal
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowDown),
      platform: 'macos',
      character: vim ? (horizontal ? 'l' : 'j') : null,
    );
    await tester.pump();
    await tester.pump();
  }

  for (final layout in [2, 0, 1, PanelLayout.thumbnailIndex]) {
    for (final vim in [false, true]) {
      testWidgets(
        'layout=$layout, Vim=$vim: keyboard reveal animates while the cursor and marks update immediately',
        (tester) async {
          await mount(tester, layout, vim: vim);
          await edge(tester, layout);
          final c = cubit(tester);
          c.toggleSelectionAt(1);
          await tester.pumpAndSettle();
          final marks = c.state.active!.selected;
          final beforeCursor = c.state.active!.cursor;
          final before = position(tester).pixels;
          await move(tester, layout, vim);
          expect(c.state.active!.cursor, greaterThan(beforeCursor));
          expect(position(tester).pixels, before);
          await tester.pump(const Duration(milliseconds: 40));
          final middle = position(tester).pixels;
          expect(middle, greaterThan(before));
          await tester.pumpAndSettle();
          expect(position(tester).pixels, greaterThan(middle));
          expect(c.state.active!.selected, same(marks));
          expect(
            tester.getRect(viewport()).contains(cursor(tester).center),
            isTrue,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final layout in [2, 0, PanelLayout.thumbnailIndex]) {
    testWidgets(
      'layout=$layout: Reduce Motion can finish an active scroll without advancing time',
      (tester) async {
        await mount(tester, layout, vim: true);
        await edge(tester, layout);
        await move(tester, layout, true);
        await tester.pump(const Duration(milliseconds: 40));
        expect(position(tester).isScrollingNotifier.value, isTrue);
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await tester.pump();
        await tester.pump();
        expect(position(tester).isScrollingNotifier.value, isFalse);
        expect(
          tester.getRect(viewport()).contains(cursor(tester).center),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'layout=$layout: manual scroll survives panel focus changes; resize and close safely stop a reveal',
      (tester) async {
        await mount(tester, layout);
        position(tester).pointerScroll(200);
        await tester.pumpAndSettle();
        final manual = position(tester).pixels;
        await h.press(tester, LogicalKeyboardKey.tab);
        await h.press(tester, LogicalKeyboardKey.tab);
        expect(position(tester).pixels, manual);
        cubit(tester).moveFirst();
        await tester.pumpAndSettle();
        await edge(tester, layout);
        await move(tester, layout, false);
        await tester.pump(const Duration(milliseconds: 40));
        tester.view.physicalSize = const Size(1200, 650);
        await tester.pump();
        await tester.pump();
        expect(position(tester).isScrollingNotifier.value, isFalse);
        expect(
          tester.getRect(viewport()).contains(cursor(tester).center),
          isTrue,
        );
        await edge(tester, layout);
        await move(tester, layout, false);
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'layout=$layout: explicit centre alignment uses the same reveal mechanism',
      (tester) async {
        await mount(tester, layout, vim: true);
        final c = cubit(tester);
        c.moveCursorTo(100);
        await tester.pumpAndSettle();
        c.scrollCursor(ScrollAlign.center);
        await tester.pumpAndSettle();
        final at = cursor(tester).center,
            view = tester.getRect(viewport()).center;
        expect(
          layout == 0 ? at.dx : at.dy,
          closeTo(layout == 0 ? view.dx : view.dy, 1),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'thumbnail column reflow keeps the cursor visible even when cell height stays unchanged',
    (tester) async {
      const size = Size(970, 600);
      await h.pump(tester, size: size);
      final c = cubit(tester);
      c.setLayout(PanelLayout.thumbnailIndex);
      await tester.pumpAndSettle();
      expect(c.geometry.columnsPerRow, 3);
      c.moveCursorTo(100);
      await tester.pumpAndSettle();
      final gridState = tester.state(find.byType(RowsThumbnails));
      final extent = cursor(tester).height;
      await h.pump(tester, size: size, textScale: 1.02);
      expect(tester.state(find.byType(RowsThumbnails)), same(gridState));
      expect(cubit(tester), same(c));
      expect(c.geometry.columnsPerRow, 2);
      expect(cursor(tester).height, extent);
      expect(c.state.active!.cursor, 100);
      expect(position(tester).isScrollingNotifier.value, isFalse);
      expect(
        tester.getRect(viewport()).contains(cursor(tester).center),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'held l retargets horizontal scrolling without rebuilding the column index or replaying old movement',
    (tester) async {
      await mount(tester, 1, vim: true);
      await edge(tester, 1);
      final c = cubit(tester);
      final first = c.state.active!.cursor;
      final step = c.geometry.rowsPerColumn;
      final offsets = RowsBrief.debugOffsetBuilds;
      final measured = RowsBrief.debugMeasures;
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.keyL,
        platform: 'macos',
        character: 'l',
      );
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.sendKeyRepeatEvent(
          LogicalKeyboardKey.keyL,
          platform: 'macos',
          character: 'l',
        );
        await tester.pump();
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyL, platform: 'macos');
      await tester.pumpAndSettle();
      expect(c.state.active!.cursor, first + 6 * step);
      expect(
        tester.getRect(viewport()).contains(cursor(tester).center),
        isTrue,
      );
      expect(RowsBrief.debugOffsetBuilds, offsets);
      expect(RowsBrief.debugMeasures, measured);
      final offset = position(tester).pixels;
      await tester.pump(const Duration(seconds: 1));
      expect(position(tester).pixels, offset);
      expect(tester.takeException(), isNull);
    },
  );
}
