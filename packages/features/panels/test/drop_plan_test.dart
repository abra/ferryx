import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/src/native/drop_plan.dart';
import 'package:panels_feature/src/native/panel_drag_hooks.dart';
import 'package:panels_feature/src/panel/panel_side.dart';

void main() {
  const copy = FileDropOperation.copy;
  const move = FileDropOperation.move;
  const link = FileDropOperation.link;
  const none = FileDropOperation.none;
  const forbidden = FileDropOperation.forbidden;
  const both = {copy, move};
  const home = Location.native('/home');
  const docs = Location.native('/home/docs');
  const zip = Location.inArchive(archive: '/home/a.zip', path: 'dir');

  DragSource fromPanel(Location folder, List<String> paths) => DragSource.of(
    FileDragInfo(
      allowed: both,
      local: PanelDragPayload(
        side: PanelSide.left,
        folder: folder,
        paths: paths,
      ).encode(),
    ),
  );

  DragSource fromApp(List<String> paths) =>
      DragSource.of(FileDragInfo(allowed: both, paths: paths));

  FileDropOperation plan(
    Location destination,
    DragSource source, {
    Set<FileDropOperation> allowed = both,
    bool? sameVolume = true,
  }) => planDrop(
    destination: destination,
    source: source,
    allowed: allowed,
    sameVolume: sameVolume,
  );

  group('planDrop', () {
    test('one volume moves, another copies, an unknown one copies', () {
      final source = fromPanel(home, ['/home/a.txt']);
      expect(plan(docs, source), move);
      expect(plan(docs, source, sameVolume: false), copy);
      expect(plan(docs, source, sameVolume: null), copy);
    });

    test('a key that forces an operation wins over the volumes', () {
      final source = fromPanel(home, ['/home/a.txt']);
      // ⌥ leaves copy alone, ⌘ (macOS's generic) leaves none: a move.
      expect(plan(docs, source, allowed: {copy}), copy);
      expect(plan(docs, source, allowed: {copy}, sameVolume: true), copy);
      expect(plan(docs, source, allowed: {move}, sameVolume: false), move);
      expect(plan(docs, source, allowed: {}, sameVolume: false), move);
      // ⌃ asks for a link, which a drop does not make.
      expect(plan(docs, source, allowed: {link}), none);
    });

    test('a source that offers one of copy and move gets that one', () {
      final source = fromApp(['/tmp/a.txt']);
      expect(plan(docs, source, allowed: {copy, link}), copy);
      expect(plan(docs, source, allowed: {move, link}), move);
    });

    test('nothing happens in the folder the items are in', () {
      expect(plan(home, fromPanel(home, ['/home/a.txt'])), none);
      expect(plan(home, fromApp(['/home/a.txt'])), none);
      // Forcing a copy there does nothing either.
      expect(plan(home, fromApp(['/home/a.txt']), allowed: {copy}), none);
    });

    test('a folder never goes into itself or a folder of its own', () {
      final source = fromPanel(home, ['/home/docs', '/home/b.txt']);
      expect(plan(docs, source), forbidden);
      expect(
        plan(const Location.native('/home/docs/deep/er'), source),
        forbidden,
      );
      // A sibling whose name starts the same is another folder.
      expect(plan(const Location.native('/home/docs2'), source), move);
    });

    test('with Windows paths too', () {
      final source = fromApp([r'C:\Users\me\docs']);
      expect(
        plan(const Location.native(r'C:\Users\me\docs\inner'), source),
        forbidden,
      );
      expect(plan(const Location.native(r'C:\Users\me'), source), none);
      expect(plan(const Location.native(r'D:\backup'), source), move);
    });

    test('an archive takes nothing in', () {
      expect(plan(zip, fromPanel(home, ['/home/a.txt'])), forbidden);
      expect(plan(zip, fromApp(['/tmp/a.txt'])), forbidden);
    });

    test('out of an archive is an extraction, never a move', () {
      final source = fromPanel(zip, ['dir/a.txt']);
      expect(source.fromArchive, isTrue);
      expect(plan(docs, source, allowed: {copy}), copy);
      expect(plan(docs, source, allowed: {copy, move}), copy);
      expect(plan(docs, source, allowed: {}), forbidden);
      expect(plan(docs, source, allowed: {move}), forbidden);
      expect(plan(docs, source, allowed: {link}), none);
      // Back into an archive: refused, as into any archive.
      expect(plan(zip, source), forbidden);
    });

    test("another application's drag before its first file is read", () {
      final source = fromApp(const []);
      expect(source.folder, isNull);
      expect(plan(docs, source, sameVolume: null), copy);
      expect(plan(docs, source, allowed: {}), move);
    });
  });

  group('DragSource', () {
    test('reads a panel payload back from what the desktop carried', () {
      final payload = PanelDragPayload(
        side: PanelSide.right,
        folder: zip,
        paths: const ['dir/a.txt', 'dir/b'],
      );
      // The session hands back a copy of the map, as the platform does.
      final carried = Map<Object?, Object?>.from(payload.encode());
      final source = DragSource.of(FileDragInfo(allowed: both, local: carried));
      expect(source.payload?.side, PanelSide.right);
      expect(source.folder, zip);
      expect(source.paths, ['dir/a.txt', 'dir/b']);
    });

    test("another application's drag: the first file's folder", () {
      final source = fromApp(['/Volumes/USB/photos/a.jpg', '/x/b.jpg']);
      expect(source.payload, isNull);
      expect(source.folder, const Location.native('/Volumes/USB/photos'));
      expect(fromApp(['/a.txt']).folder, const Location.native('/'));
      expect(
        fromApp([r'C:\a.txt']).folder,
        const Location.native(r'C:\'),
      );
    });

    test('ignores local data that is not ours', () {
      for (final local in [
        'text',
        {'ferryx.panelDrag': 2},
        {
          'ferryx.panelDrag': 1,
          'side': 'up',
          'folder': 'native:/',
          'paths': [],
        },
        {'ferryx.panelDrag': 1, 'side': 'left', 'folder': 'x', 'paths': []},
      ]) {
        expect(PanelDragPayload.decode(local), isNull, reason: '$local');
      }
    });
  });

  group('rowDropSpot', () {
    FileEntry entry(String name, {bool dir = false, bool parent = false}) =>
        FileEntry(
          name: name,
          path: '/home/$name',
          kind: dir ? EntryKind.directory : EntryKind.file,
          isDir: dir,
          isParent: parent,
        );

    test(
      'a folder row takes drops into itself, `..` into the folder above',
      () {
        expect(
          rowDropSpot(home, entry('docs', dir: true)),
          const DropSpot.row(docs, 'docs'),
        );
        expect(
          rowDropSpot(home, entry('..', dir: true, parent: true)),
          const DropSpot.row(Location.native('/'), '..'),
        );
        expect(rowDropSpot(home, entry('a.txt')), isNull);
        expect(
          rowDropSpot(const Location.native('/'), entry('..', parent: true)),
          isNull,
        );
      },
    );

    test('inside an archive the spots are in the archive', () {
      expect(
        rowDropSpot(zip, entry('sub', dir: true))?.folder.isNative,
        isFalse,
      );
    });
  });

  test('dropAccepts', () {
    expect([copy, move, link].every(dropAccepts), isTrue);
    expect([none, forbidden].any(dropAccepts), isFalse);
  });
}
