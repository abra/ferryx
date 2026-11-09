import 'dart:collection';
import 'dart:developer' show reachabilityBarrier;

import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/panels_feature.dart';

class _CountedRows extends ListBase<FileEntry> {
  _CountedRows(this._rows);

  final List<FileEntry> _rows;
  int reads = 0;

  @override
  int get length => _rows.length;

  @override
  set length(int value) => throw UnsupportedError('immutable');

  @override
  FileEntry operator [](int index) {
    reads++;
    return _rows[index];
  }

  @override
  void operator []=(int index, FileEntry value) =>
      throw UnsupportedError('immutable');
}

FileEntry _file(String name, int size) => FileEntry(
  name: name,
  path: '/home/$name',
  kind: EntryKind.file,
  isDir: false,
  size: size,
);

// Keep the old snapshot out of the test's stack while checking ownership.
@pragma('vm:never-inline')
({PanelTabState tab, WeakReference<List<FileEntry>> rows})
_rememberSelection() {
  final rows = [_file('a.txt', 12)];
  final tab = PanelTabState(
    id: 't',
    location: const Location.native('/home'),
    sort: const SortOptions(),
    rows: rows,
    selected: {'a.txt'},
  );
  expect(tab.selectedBytes, 12);
  return (
    tab: tab.copyWith(
      location: const Location.native('/empty'),
      rows: const [],
      selected: const {},
      lastSelection: tab.selected,
    ),
    rows: WeakReference(rows),
  );
}

Future<void> _collectGarbage() async {
  final barrier = reachabilityBarrier + 2;
  final pressure = <List<int>>[];
  // Observe completed GC cycles, not an arbitrary delay or heap-size guess.
  while (reachabilityBarrier < barrier) {
    pressure.add(List<int>.generate(30000, (i) => i));
    if (pressure.length > 100) pressure.removeAt(0);
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  PanelTabState tab(Set<String> selected) => PanelTabState(
    id: 't',
    location: const Location.native('/home'),
    sort: const SortOptions(),
    selected: selected,
  );

  test('two tabs with the same big selection in sets of their own compare '
      'equal in linear time, as every emit compares them', () {
    final names = [for (var i = 0; i < 50000; i++) 'file $i.txt'];
    final a = tab(names.toSet());
    final b = tab(names.reversed.toSet());
    final clock = Stopwatch()..start();
    expect(a, b);
    // Pairwise, as Equatable compares sets, this takes minutes.
    expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
    expect(a, isNot(tab({...names.skip(1), 'other.txt'})));
    expect(a.hashCode, b.hashCode);
  });

  test(
    'selected bytes reuse cursor moves and follow rows, selection and sizes',
    () {
      const folder = FileEntry(
        name: 'docs',
        path: '/home/docs',
        kind: EntryKind.directory,
        isDir: true,
      );
      final rows = _CountedRows([_file('a.txt', 12), folder]);
      final initial = tab({'a.txt', 'docs'}).copyWith(
        rows: rows,
        folderSizes: {'docs': 20},
      );
      expect(initial.selectedBytes, 32);
      expect(rows.reads, 2);
      expect(initial.copyWith(cursor: 1).selectedBytes, 32);
      expect(rows.reads, 2);
      expect(initial.copyWith(selected: {'docs'}).selectedBytes, 20);
      expect(rows.reads, 4);
      expect(initial.copyWith(folderSizes: {'docs': 30}).selectedBytes, 42);
      expect(rows.reads, 6);
      expect(
        initial.copyWith(rows: [_file('a.txt', 50), folder]).selectedBytes,
        70,
      );
      expect(initial.copyWith(selected: const {}).selectedBytes, 0);
    },
  );

  test(
    'a remembered selection does not retain the old listing through its sum',
    () async {
      final remembered = _rememberSelection();
      await _collectGarbage();
      expect(remembered.tab.lastSelection, {'a.txt'});
      expect(remembered.rows.target, isNull);
    },
  );
}
