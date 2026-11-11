import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/src/panel/panel_footer.dart';
import 'package:panels_feature/src/panel/panel_row.dart';
import 'package:panels_feature/src/panel/recent_entries.dart';
import 'package:panels_feature/src/panel/recent_entries_legend.dart';
import 'package:panels_feature/src/panel/rows_brief.dart';

import 'support/workspace_harness.dart';

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);
  late WorkspaceHarness h;

  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp(vim: true);
    final now = DateTime.now();
    h.folders['/home/docs'] = [
      FileEntry(
        name: 'new.txt',
        path: '/home/docs/new.txt',
        kind: EntryKind.file,
        isDir: false,
        added: now.subtract(const Duration(minutes: 10)),
        modified: DateTime(2000),
      ),
      FileEntry(
        name: 'Today',
        path: '/home/docs/Today',
        kind: EntryKind.directory,
        isDir: true,
        added: now.subtract(const Duration(hours: 4)),
      ),
      FileEntry(
        name: 'old.txt',
        path: '/home/docs/old.txt',
        kind: EntryKind.file,
        isDir: false,
        added: now.subtract(const Duration(days: 2)),
        modified: now,
      ),
      h.file('/home/docs', 'unknown.txt'),
    ];
  });
  tearDown(() => h.tearDown());

  Finder name(String label) => find.byWidgetPredicate(
    (w) => w is RowName && w.entry.name == label,
  );

  for (final brightness in Brightness.values) {
    testWidgets('List and Brief show added dates in $brightness, keeping '
        'selection, focus and Vim footer behavior', (tester) async {
      await h.pump(tester, brightness: brightness);
      final colors = tester.element(name('new.txt')).appColors;
      RowLook look(String label) => tester.widget<RowName>(name(label)).look;
      void expectDates() {
        expect(look('new.txt').recentAge, RecentEntryAge.hour);
        expect(look('new.txt').background(colors), colors.recentHour);
        expect(look('Today').recentAge, RecentEntryAge.day);
        expect(look('Today').background(colors), colors.recentDay);
        expect(look('old.txt').recentAge, isNull);
        expect(look('unknown.txt').recentAge, isNull);
        final painted = find.ancestor(
          of: name('new.txt'),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).color == colors.recentHour,
          ),
        );
        expect(painted, findsOneWidget);
      }

      expectDates();
      expect(find.byType(RecentEntriesLegend), findsNWidgets(2));
      // Dynamic Brief must use the same fills without invalidating widths.
      await h.press(tester, LogicalKeyboardKey.digit2, control: true);
      expect(find.byType(RowsBrief), findsOneWidget);
      expectDates();
      final measured = RowsBrief.debugMeasures;
      await tester.tap(name('new.txt'));
      await h.settle(tester);
      expect(look('new.txt').background(colors), colors.cursorFill);
      await h.press(tester, LogicalKeyboardKey.space);
      expect(look('new.txt').selected, isTrue);
      expect(look('new.txt').background(colors), colors.accentSoft);
      expect(RowsBrief.debugMeasures, measured);
      // The selection total keeps its place; the idle panel keeps its legend.
      expect(find.byType(RecentEntriesLegend), findsOneWidget);
      await h.press(tester, LogicalKeyboardKey.tab);
      expect(look('new.txt').background(colors), colors.selectionMuted);
      await h.press(tester, LogicalKeyboardKey.tab);
      await h.press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(RecentEntriesLegend), findsNWidgets(2));
      await h.press(tester, LogicalKeyboardKey.slash, character: '/');
      expect(find.byType(RecentEntriesLegend), findsOneWidget);
      await h.press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(RecentEntriesLegend), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in ['en', 'ru']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('legend fits narrow $locale panels at text scale $scale', (
        tester,
      ) async {
        await h.pump(
          tester,
          size: const Size(760, 600),
          locale: Locale(locale),
          textScale: scale,
        );
        expect(find.byType(RecentEntriesLegend), findsNWidgets(2));
        for (var index = 0; index < 2; index++) {
          final legend = find.byType(RecentEntriesLegend).at(index);
          final rect = tester.getRect(legend);
          final footer = tester.getRect(
            find.ancestor(
              of: legend,
              matching: find.byType(PanelFooter),
            ),
          );
          expect(footer.contains(rect.center), isTrue);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
