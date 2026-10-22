import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:panels_feature/src/native/quick_look_pick.dart';

void main() {
  const home = Location.native('/home');
  const zip = Location.inArchive(archive: '/home/a.zip');

  FileEntry row(String name, {bool dir = false, bool parent = false}) =>
      FileEntry(
        name: name,
        path: parent ? '/' : '/home/$name',
        kind: dir ? EntryKind.directory : EntryKind.file,
        isDir: dir,
        isParent: parent,
      );

  final rows = [
    row('..', dir: true, parent: true),
    row('docs', dir: true),
    row('a.txt'),
    row('b.txt'),
    row('c.txt'),
  ];

  PanelTabState tab({
    Location location = home,
    List<FileEntry>? entries,
    int cursor = 0,
    Set<String> selected = const {},
  }) => PanelTabState(
    id: 'left-1',
    location: location,
    sort: const SortOptions(),
    rows: entries ?? rows,
    cursor: cursor,
    selected: selected,
  );

  List<String> names(QuickLookPick pick) => [
    for (final entry in pick.entries) entry.name,
  ];

  test("the folder's items without `..`, at the cursor's", () {
    final pick = quickLookPick(tab(cursor: 3));
    expect(names(pick), ['docs', 'a.txt', 'b.txt', 'c.txt']);
    expect(pick.index, 2);
    expect(pick.fromSelection, isFalse);
    expect(quickLookFolderIndex(tab(cursor: 3)), 2);
  });

  test('the cursor on `..` shows the first item', () {
    final pick = quickLookPick(tab(cursor: 0));
    expect(pick.index, 0);
    expect(names(pick).first, 'docs');
  });

  test('a folder without `..` (the root) keeps every row', () {
    final pick = quickLookPick(tab(entries: rows.sublist(1), cursor: 1));
    expect(names(pick), ['docs', 'a.txt', 'b.txt', 'c.txt']);
    expect(pick.index, 1);
  });

  test('several selected: the selection, at the cursor when it is in it', () {
    final selected = {'a.txt', 'c.txt', 'docs'};
    final onC = quickLookPick(tab(cursor: 4, selected: selected));
    expect(names(onC), ['docs', 'a.txt', 'c.txt']);
    expect(onC.index, 2);
    expect(onC.fromSelection, isTrue);
    final elsewhere = quickLookPick(tab(cursor: 3, selected: selected));
    expect(elsewhere.index, 0);
  });

  test('one selected row is not several: the folder, at the cursor', () {
    final pick = quickLookPick(tab(cursor: 2, selected: {'c.txt'}));
    expect(pick.fromSelection, isFalse);
    expect(pick.index, 1);
  });

  test('inside an archive: the focused file alone, never a folder', () {
    expect(names(quickLookPick(tab(location: zip, cursor: 2))), ['a.txt']);
    expect(quickLookPick(tab(location: zip, cursor: 1)).isEmpty, isTrue);
    expect(quickLookPick(tab(location: zip, cursor: 0)).isEmpty, isTrue);
    final selected = quickLookPick(
      tab(location: zip, cursor: 3, selected: {'docs', 'a.txt', 'b.txt'}),
    );
    expect(names(selected), ['a.txt', 'b.txt']);
    expect(selected.index, 1);
  });

  test('an empty folder has nothing to show', () {
    expect(quickLookPick(tab(entries: const [], cursor: -1)).isEmpty, isTrue);
    expect(quickLookPick(tab(entries: [rows.first])).isEmpty, isTrue);
  });

  test('quickLookIndexIn finds the focused row by name', () {
    expect(quickLookIndexIn(rows, rows[3]), 3);
    expect(quickLookIndexIn(rows, null), -1);
    expect(quickLookIndexIn(rows.sublist(0, 2), rows[3]), -1);
  });
}
