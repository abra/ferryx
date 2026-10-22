import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:preferences_service/preferences_service.dart';

void main() {
  final start = DateTime(2026, 10, 1, 12);

  group('FrecentFolder.scoreAt', () {
    test('weighs the rank by how long ago the last visit was', () {
      final folder = FrecentFolder(path: '/a', rank: 10, lastVisit: start);
      expect(folder.scoreAt(start.add(const Duration(minutes: 30))), 40);
      expect(folder.scoreAt(start.add(const Duration(hours: 5))), 20);
      expect(folder.scoreAt(start.add(const Duration(days: 3))), 5);
      expect(folder.scoreAt(start.add(const Duration(days: 30))), 2.5);
    });
  });

  group('matchFolders', () {
    FrecentFolder folder(String path, {double rank = 1, Duration? ago}) =>
        FrecentFolder(
          path: path,
          rank: rank,
          lastVisit: start.subtract(ago ?? Duration.zero),
        );

    List<String> paths(List<FolderMatch> matches) => [
      for (final m in matches) m.folder.path,
    ];

    test('an empty query answers every folder, the most frecent first', () {
      final matches = matchFolders(
        [
          folder('/old', rank: 50, ago: const Duration(days: 30)),
          folder('/fresh', rank: 5),
          folder('/day', rank: 8, ago: const Duration(hours: 3)),
        ],
        '  ',
        now: start,
      );
      // 50 × ¼ = 12.5, 5 × 4 = 20, 8 × 2 = 16.
      expect(paths(matches), ['/fresh', '/day', '/old']);
      expect(matches.every((m) => m.ranges.isEmpty), isTrue);
    });

    test('every word must match, in order, case aside', () {
      final folders = [
        folder('/Users/me/Projects/ferryx'),
        folder('/Users/me/ferryx-notes/projects'),
        folder('/tmp/other'),
      ];
      expect(
        paths(matchFolders(folders, 'proj FERRY', now: start)),
        ['/Users/me/Projects/ferryx'],
      );
      expect(matchFolders(folders, 'ferryx zzz', now: start), isEmpty);
    });

    test('the last word in the folder\'s own name ranks first', () {
      final matches = matchFolders(
        [
          folder('/src/app/lib', rank: 100),
          folder('/work/apps', rank: 1),
        ],
        'app',
        now: start,
      );
      expect(paths(matches), ['/work/apps', '/src/app/lib']);
      expect(matches.first.inLastSegment, isTrue);
      expect(matches.last.inLastSegment, isFalse);
    });

    test('the ranges index the path, the last word as far right as it '
        'goes', () {
      final match = matchFolders(
        [folder('/src/src/main')],
        'src ma',
        now: start,
      ).single;
      expect(match.ranges, [(1, 4), (9, 11)]);
      final repeated = matchFolders(
        [folder('/docs/docs')],
        'docs',
        now: start,
      ).single;
      expect(repeated.ranges, [(6, 10)]);
      expect(repeated.inLastSegment, isTrue);
    });

    test('ties go to the shorter path; the excluded folder is left out', () {
      final matches = matchFolders(
        [folder('/a/notes-long'), folder('/a/notes'), folder('/b/notes')],
        'notes',
        now: start,
        exclude: '/b/notes',
      );
      expect(paths(matches), ['/a/notes', '/a/notes-long']);
    });
  });

  group('FolderFrecency', () {
    late DateTime now;
    late InMemorySideStorage storage;

    setUp(() {
      now = start;
      storage = InMemorySideStorage();
    });

    Future<FolderFrecency> load({int maxEntries = 1000}) => FolderFrecency.load(
      storage,
      now: () => now,
      writeDelay: const Duration(milliseconds: 20),
      maxEntries: maxEntries,
    );

    test('a visit adds a point and moves the last visit', () async {
      final store = await load();
      store
        ..visit('/a')
        ..visit('/b');
      now = now.add(const Duration(minutes: 5));
      store.visit('/a');
      final a = store.folders.firstWhere((f) => f.path == '/a');
      expect(a.rank, 2);
      expect(a.lastVisit, now);
      expect(store.query('').first.folder.path, '/a');
      await store.dispose();
    });

    test('writes once per delay, not once per visit, and on flush', () async {
      final store = await load();
      for (var i = 0; i < 50; i++) {
        store.visit('/folder/$i');
      }
      expect(storage.writes, 0);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(storage.writes, 1);
      store.visit('/folder/x');
      await store.flush();
      expect(storage.writes, 2);
      await store.dispose();
      store.visit('/after');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(storage.writes, 2);
    });

    test('reads back what it wrote; damaged items are skipped', () async {
      final store = await load();
      store
        ..visit('/a')
        ..visit('/a')
        ..visit('/b');
      await store.dispose();
      final again = await load();
      expect(
        {for (final f in again.folders) f.path: f.rank},
        {'/a': 2.0, '/b': 1.0},
      );
      storage.values[FolderFrecency.key] = jsonEncode({
        'version': 1,
        'folders': [
          ['/ok', 3, start.millisecondsSinceEpoch],
          ['', 3, 0],
          ['/negative', -1, 0],
          'nonsense',
          [1, 2, 3],
        ],
      });
      final damaged = await load();
      expect([for (final f in damaged.folders) f.path], ['/ok']);
      storage.values[FolderFrecency.key] = '{not json';
      expect((await load()).folders, isEmpty);
    });

    test('ages every rank once the total passes the limit', () async {
      storage.values[FolderFrecency.key] = jsonEncode({
        'version': 1,
        'folders': [
          ['/big', FolderFrecency.maxTotalRank, start.millisecondsSinceEpoch],
          ['/small', 1.05, start.millisecondsSinceEpoch],
        ],
      });
      final store = await load();
      store.visit('/new');
      final ranks = {for (final f in store.folders) f.path: f.rank};
      // Scaled by 0.9 × 10000 / 10002.05: the small one falls under one
      // point and goes; the folder just visited stays.
      expect(ranks.keys, unorderedEquals(['/big', '/new']));
      expect(ranks['/big'], closeTo(8998.2, 0.1));
      await store.dispose();
    });

    test('keeps at most maxEntries, dropping the least frecent', () async {
      final store = await load(maxEntries: 3);
      store.visit('/old');
      now = now.add(const Duration(days: 10));
      store
        ..visit('/a')
        ..visit('/a')
        ..visit('/b')
        ..visit('/c');
      expect(store.folders.map((f) => f.path).toSet(), {'/a', '/b', '/c'});
      store.remove('/b');
      expect(store.folders.map((f) => f.path).toSet(), {'/a', '/c'});
      await store.dispose();
    });
  });

  group('RecentItems', () {
    test('the newest first, each once, at most the capacity', () async {
      final storage = InMemorySideStorage();
      final recent = await RecentItems.load(
        storage,
        key: RecentItems.commandsKey,
        capacity: 3,
      );
      for (final item in ['a', 'b', 'c', 'a', 'd']) {
        await recent.record(item);
      }
      expect(recent.items, ['d', 'a', 'c']);
      final again = await RecentItems.load(
        storage,
        key: RecentItems.commandsKey,
        capacity: 3,
      );
      expect(again.items, ['d', 'a', 'c']);
      storage.values[RecentItems.commandsKey] = '[1, "x", null';
      final damaged = await RecentItems.load(
        storage,
        key: RecentItems.commandsKey,
      );
      expect(damaged.items, isEmpty);
    });
  });
}
