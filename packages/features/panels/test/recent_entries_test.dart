import 'dart:collection';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panels_feature/src/panel/panel_row.dart';
import 'package:panels_feature/src/panel/panel_state.dart';
import 'package:panels_feature/src/panel/recent_entries.dart';
import 'package:panels_feature/src/panel/rows_brief.dart';
import 'package:panels_feature/src/panel/rows_list.dart';
import 'package:shortcuts/shortcuts.dart';

void main() {
  final start = DateTime.utc(2026, 11, 11, 12);

  FileEntry entry({
    Duration? age,
    bool folder = false,
    bool parent = false,
    DateTime? modified,
    DateTime? created,
  }) => FileEntry(
    name: parent ? '..' : 'item',
    path: '/item',
    kind: folder ? EntryKind.directory : EntryKind.file,
    isDir: folder,
    isParent: parent,
    added: age == null ? null : start.subtract(age),
    modified: modified,
    created: created,
  );

  test(
    'date added ranges have exact one-hour, three-hour and day boundaries',
    () {
      for (final folder in [false, true]) {
        RecentEntryAge? age(Duration elapsed) => recentEntryAge(
          entry(age: elapsed, folder: folder),
          start,
        );
        expect(age(Duration.zero), RecentEntryAge.hour);
        expect(
          age(const Duration(minutes: 59, seconds: 59)),
          RecentEntryAge.hour,
        );
        expect(age(const Duration(hours: 1)), RecentEntryAge.threeHours);
        expect(
          age(const Duration(hours: 2, minutes: 59, seconds: 59)),
          RecentEntryAge.threeHours,
        );
        expect(age(const Duration(hours: 3)), RecentEntryAge.day);
        expect(age(const Duration(hours: 23, minutes: 59)), RecentEntryAge.day);
        expect(age(const Duration(days: 1)), isNull);
        expect(age(const Duration(days: 100)), isNull);
      }
    },
  );

  test('missing, future and parent dates never highlight; modification and '
      'creation are not substitutes for the date added', () {
    expect(recentEntryAge(entry(), start), isNull);
    expect(
      recentEntryAge(entry(age: const Duration(seconds: -1)), start),
      isNull,
    );
    expect(
      recentEntryAge(entry(age: Duration.zero, parent: true), start),
      isNull,
    );
    expect(
      recentEntryAge(entry(modified: start, created: start), start),
      isNull,
    );
    expect(
      recentEntryAge(
        entry(age: const Duration(minutes: 5), modified: DateTime.utc(2000)),
        start,
      ),
      RecentEntryAge.hour,
    );
  });

  testWidgets('a stationary listing ages without a refresh and stops ticking '
      'after its last recent entry expires', (tester) async {
    var now = start;
    var builds = 0;
    RecentEntryAge? shown;
    final row = entry(age: const Duration(minutes: 59, seconds: 30));
    await tester.pumpWidget(
      RecentEntriesClock(
        entries: [row],
        now: () => now,
        child: Builder(
          builder: (context) {
            builds++;
            shown = recentEntryAge(row, RecentEntriesClock.nowOf(context));
            return const SizedBox();
          },
        ),
      ),
    );
    expect(shown, RecentEntryAge.hour);
    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    expect(shown, RecentEntryAge.threeHours);
    now = now.add(const Duration(hours: 2));
    await tester.pump(const Duration(hours: 2));
    expect(shown, RecentEntryAge.day);
    now = now.add(const Duration(hours: 21));
    await tester.pump(const Duration(hours: 21));
    expect(shown, isNull);
    final expiredBuilds = builds;
    now = now.add(const Duration(days: 3));
    await tester.pump(const Duration(days: 3));
    expect(builds, expiredBuilds);
  });

  testWidgets('selection rebuilds do not scan the listing; replacing it '
      'cancels the old deadline', (tester) async {
    var now = start;
    DateTime readNow() => now;
    var builds = 0;
    final rows = _CountedEntries([
      entry(age: const Duration(minutes: 59)),
    ]);
    final child = Builder(
      builder: (context) {
        RecentEntriesClock.nowOf(context);
        builds++;
        return const SizedBox();
      },
    );
    Widget clock(List<FileEntry> entries) => RecentEntriesClock(
      entries: entries,
      now: readNow,
      child: child,
    );
    await tester.pumpWidget(clock(rows));
    final reads = rows.reads;
    await tester.pumpWidget(clock(rows));
    expect(rows.reads, reads);
    await tester.pumpWidget(clock(const []));
    final emptyBuilds = builds;
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    expect(builds, emptyBuilds);
    expect(rows.reads, reads);
  });

  testWidgets('returning from suspension updates the clock immediately; '
      'disposing a recent listing cancels its timer', (tester) async {
    var now = start;
    RecentEntryAge? shown;
    final row = entry(age: const Duration(minutes: 59));
    await tester.pumpWidget(
      RecentEntriesClock(
        entries: [row],
        now: () => now,
        child: Builder(
          builder: (context) {
            shown = recentEntryAge(row, RecentEntriesClock.nowOf(context));
            return const SizedBox();
          },
        ),
      ),
    );
    expect(shown, RecentEntryAge.hour);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    now = now.add(const Duration(hours: 2));
    await tester.pump(const Duration(hours: 2));
    expect(shown, RecentEntryAge.hour, reason: 'no timer while hidden');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(shown, RecentEntryAge.threeHours);
    await tester.pumpWidget(const SizedBox());
    now = now.add(const Duration(days: 1));
    await tester.pump(const Duration(days: 1));
    expect(tester.takeException(), isNull);
  });
  for (final brief in [false, true]) {
    testWidgets('visible ${brief ? 'Brief' : 'List'} rows age in place, '
        'without remeasuring names', (tester) async {
      var now = start;
      final rows = [entry(age: const Duration(minutes: 59))];
      final tab = PanelTabState(
        id: 'tab',
        location: const Location.native('/'),
        sort: const SortOptions(),
        rows: rows,
      );
      final callbacks = RowCallbacks(
        onTapDown: (_, {toggle = false, range = false}) {},
        onDoubleTap: (_) {},
        onSecondaryTapDown: (_, _) {},
        onRenameCommit: (_) {},
        onRenameCancel: () {},
      );
      final rename = RenameSpec(
        caret: RenameCaret.stem,
        shortcutMap: ShortcutMap.forUser(TargetPlatform.macOS),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppPlatformStyle.macos),
          localizationsDelegates: FerryxSupportedLocales.delegates,
          supportedLocales: FerryxSupportedLocales.locales,
          home: Scaffold(
            body: RecentEntriesClock(
              entries: rows,
              now: () => now,
              child: brief
                  ? RowsBrief(
                      tab: tab,
                      layout: PanelLayout.defaults[1],
                      active: true,
                      callbacks: callbacks,
                      onGeometry: (_) {},
                      rename: rename,
                      onSort: (_) {},
                    )
                  : RowsList(
                      tab: tab,
                      layout: PanelLayout.defaults[2],
                      active: true,
                      callbacks: callbacks,
                      onGeometry: (_) {},
                      rename: rename,
                      onSort: (_) {},
                    ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final name = find.byType(RowName);
      RowLook look() => tester.widget<RowName>(name).look;
      final colors = tester.element(name).appColors;
      expect(look().background(colors), colors.recentHour);
      final measured = RowsBrief.debugMeasures;
      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(look().background(colors), colors.recentThreeHours);
      now = now.add(const Duration(hours: 2));
      await tester.pump(const Duration(hours: 2));
      expect(look().background(colors), colors.recentDay);
      now = now.add(const Duration(hours: 21));
      await tester.pump(const Duration(hours: 21));
      expect(look().background(colors), isNull);
      expect(RowsBrief.debugMeasures, measured);
      expect(tester.takeException(), isNull);
    });
  }
}

class _CountedEntries extends ListBase<FileEntry> {
  _CountedEntries(this.entries);

  final List<FileEntry> entries;
  int reads = 0;

  @override
  int get length => entries.length;

  @override
  FileEntry operator [](int index) {
    reads++;
    return entries[index];
  }

  @override
  set length(int length) => throw UnsupportedError('read only');

  @override
  void operator []=(int index, FileEntry value) =>
      throw UnsupportedError('read only');
}
