import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/src/workspace/folder_compare.dart';

final _t0 = DateTime(2026, 10, 1, 12);

FileEntry file(String name, {int size = 1, DateTime? modified}) => FileEntry(
  name: name,
  path: '/x/$name',
  kind: EntryKind.file,
  isDir: false,
  size: size,
  modified: modified ?? _t0,
);

FileEntry folder(String name) => FileEntry(
  name: name,
  path: '/x/$name',
  kind: EntryKind.directory,
  isDir: true,
  modified: _t0,
);

const parent = FileEntry(
  name: '..',
  path: '/',
  kind: EntryKind.directory,
  isDir: true,
  isParent: true,
);

FolderComparison compare(
  List<FileEntry> left,
  List<FileEntry> right, {
  bool caseSensitive = false,
  bool byContents = false,
}) => compareFolderEntries(
  left: left,
  right: right,
  caseSensitive: caseSensitive,
  byContents: byContents,
);

void main() {
  group('compareFolderEntries', () {
    test('selects what is on one side only, files and folders', () {
      final result = compare(
        [parent, file('a'), folder('only-left'), file('both')],
        [parent, file('both'), file('b'), folder('only-right')],
      );
      expect(result.left, {'a', 'only-left'});
      expect(result.right, {'b', 'only-right'});
      expect(result.candidates, isEmpty);
    });

    test('of two files the newer is selected; equal ones are not', () {
      final later = _t0.add(const Duration(minutes: 5));
      final result = compare(
        [
          file('newer-left', modified: later),
          file('newer-right'),
          file('same'),
        ],
        [
          file('newer-left'),
          file('newer-right', modified: later),
          file('same'),
        ],
      );
      expect(result.left, {'newer-left'});
      expect(result.right, {'newer-right'});
    });

    test('times within a second agree; other sizes then select both', () {
      final almost = _t0.add(const Duration(milliseconds: 900));
      final result = compare(
        [file('a', size: 10), file('b', size: 5)],
        [file('a', size: 20, modified: almost), file('b', size: 5)],
      );
      expect(result.left, {'a'});
      expect(result.right, {'a'});
    });

    test('a file against a folder of its name selects both', () {
      final result = compare([file('x')], [folder('x')]);
      expect(result.left, {'x'});
      expect(result.right, {'x'});
    });

    test('folders on both sides are left alone', () {
      final result = compare([folder('docs')], [folder('docs')]);
      expect(result.left, isEmpty);
      expect(result.right, isEmpty);
    });

    test('names pair ignoring case unless the collation tells case', () {
      final left = [file('Readme.md')];
      final right = [file('README.md')];
      final folded = compare(left, right);
      expect(folded.left, isEmpty);
      expect(folded.right, isEmpty);
      final exact = compare(left, right, caseSensitive: true);
      expect(exact.left, {'Readme.md'});
      expect(exact.right, {'README.md'});
    });

    test('an exact match wins over one by case', () {
      // A case-sensitive file system can hold both on the right.
      final later = _t0.add(const Duration(hours: 1));
      final result = compare(
        [file('a.txt')],
        [file('A.TXT', modified: later), file('a.txt')],
      );
      expect(result.left, isEmpty);
      expect(result.right, {'A.TXT'});
    });

    test('unknown times decide nothing', () {
      final noTime = FileEntry(
        name: 'n',
        path: '/x/n',
        kind: EntryKind.file,
        isDir: false,
        size: 1,
      );
      final result = compare([noTime], [file('n')]);
      expect(result.left, isEmpty);
      expect(result.right, isEmpty);
    });

    test('by contents, files of one size wait for the core', () {
      final later = _t0.add(const Duration(hours: 1));
      final result = compare(
        [
          file('same-size', size: 3, modified: later),
          file('other-size', size: 3),
          file('tie', size: 7),
        ],
        [
          file('same-size', size: 3),
          file('other-size', size: 4),
          file('tie', size: 7),
        ],
        byContents: true,
      );
      expect(result.candidates.map((c) => c.left.name), ['same-size', 'tie']);
      expect(result.candidates.first.newer, -1);
      expect(result.candidates.last.newer, 0);
      // Sizes differ: decided at once (same times: both).
      expect(result.left, {'other-size'});
      expect(result.right, {'other-size'});

      // The core says both differ: the newer, and both of the tie.
      final full = result.withDiffering([0, 1]);
      expect(full.left, {'other-size', 'same-size', 'tie'});
      expect(full.right, {'other-size', 'tie'});
      // Equal contents (no index) add nothing; a stray index is ignored.
      expect(result.withDiffering([5]).left, result.left);
    });

    test('empty folders compare as the same', () {
      final result = compare([parent], [parent]);
      expect(result.left, isEmpty);
      expect(result.right, isEmpty);
    });
  });

  group('pairByName', () {
    test('keeps each entry once, the unpaired at the end', () {
      final pairs = pairByName(
        [file('a'), file('B'), file('c')],
        [file('b'), file('d'), file('a')],
        caseSensitive: false,
      );
      expect(
        pairs.map((p) => '${p.$1?.name}:${p.$2?.name}'),
        ['a:a', 'B:b', 'c:null', 'null:d'],
      );
    });
  });

  group('newerSide', () {
    test('compares with the tolerance', () {
      const second = Duration(seconds: 1);
      final later = _t0.add(const Duration(seconds: 3));
      expect(newerSide(later, _t0, second), -1);
      expect(newerSide(_t0, later, second), 1);
      expect(newerSide(_t0, _t0.add(second), second), 0);
      expect(newerSide(null, _t0, second), 0);
    });
  });
}
