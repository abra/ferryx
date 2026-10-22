import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:panels_feature/src/workspace/shelf.dart';
import 'package:panels_feature/src/workspace/shelf_strip.dart';

import 'support/workspace_harness.dart';

FileEntry _file(String path) => FileEntry(
  name: path.substring(path.lastIndexOf('/') + 1),
  path: path,
  kind: EntryKind.file,
  isDir: false,
);

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);

  group('Shelf', () {
    final a = ShelfItem(_file('/x/a'));
    final b = ShelfItem(_file('/y/b'));

    test('keeps the order items came in, each path once', () {
      final shelf = Shelf.empty.add([a, b]).add([
        ShelfItem(_file('/x/a'), cut: true),
      ]);
      expect([for (final i in shelf.items) i.path], ['/x/a', '/y/b']);
      expect(shelf.items.first.cut, isTrue, reason: 'the newer mark wins');
      expect(shelf.cutCount, 1);
      expect(shelf.contains('/y/b'), isTrue);
      expect(shelf.without(['/x/a']).items, [b]);
      expect(a.folder, '/x');
      expect(a.name, 'a');
    });

    test('marks the items gone from the disk, and those back', () {
      final shelf = Shelf.empty.add([a, b]).withMissing({'/y/b'});
      expect([for (final i in shelf.items) i.missing], [false, true]);
      expect(shelf.withMissing({}).items.every((i) => !i.missing), isTrue);
    });
  });

  group('WorkspaceCubit', () {
    final a = ShelfItem(_file('/x/a'));
    final b = ShelfItem(_file('/y/b'), cut: true);

    test('the first items show the strip; the last taken off hides it', () {
      final cubit = WorkspaceCubit();
      expect(cubit.state.shelfShown, isFalse);
      cubit.shelve([a]);
      expect(cubit.state.shelfShown, isTrue);
      cubit.showShelf(false);
      cubit.shelve([b]);
      expect(cubit.state.shelfShown, isFalse, reason: 'hidden on purpose');
      expect(cubit.state.shelf.length, 2);
      cubit.shelve([b], replace: true);
      expect(cubit.state.shelf.items, [b]);
      cubit
        ..showShelf(true)
        ..unshelve(['/y/b']);
      expect(cubit.state.shelf.isEmpty, isTrue);
      expect(cubit.state.shelfShown, isFalse);
      cubit.close();
    });
  });

  group('the window', () {
    late WorkspaceHarness h;

    setUp(() async {
      h = WorkspaceHarness();
      await h.setUp();
    });

    tearDown(() => h.tearDown());

    WorkspaceState workspace(WidgetTester tester) =>
        tester.element(find.byType(KeyHintStrip)).read<WorkspaceCubit>().state;

    PanelCubit panel(WidgetTester tester, int index) => tester
        .widgetList<PanelView>(find.byType(PanelView))
        .map((v) => tester.element(find.byWidget(v)).read<PanelCubit>())
        .elementAt(index);

    Future<void> down(WidgetTester tester, [int times = 1]) async {
      for (var i = 0; i < times; i++) {
        await h.press(tester, LogicalKeyboardKey.arrowDown);
      }
    }

    Future<void> addToShelf(WidgetTester tester) =>
        h.press(tester, LogicalKeyboardKey.keyS, meta: true, alt: true);

    testWidgets('⌥⌘S shelves the focused row; the strip shows it, the '
        'footer counts it', (tester) async {
      await h.pump(tester);
      expect(find.byType(ShelfStrip), findsNothing);
      await down(tester); // a.txt
      await addToShelf(tester);
      expect(find.byType(ShelfStrip), findsOneWidget);
      expect(find.text('a.txt'), findsWidgets);
      expect(find.textContaining('1 on the shelf'), findsNWidgets(2));
      await down(tester); // b.txt
      await addToShelf(tester);
      await addToShelf(tester);
      expect(
        [for (final i in workspace(tester).shelf.items) i.path],
        ['/home/docs/a.txt', '/home/docs/b.txt'],
        reason: 'each path once',
      );
    });

    testWidgets('Copy Here copies into the active panel\'s folder and keeps '
        'the shelf; Move Here moves and empties it', (tester) async {
      await h.pump(tester);
      await down(tester);
      await addToShelf(tester);
      await h.press(tester, LogicalKeyboardKey.tab); // the right panel
      await tester.tap(find.text('Copy Here'));
      await h.settle(tester);
      expect(h.started.single.kind, OpKind.copy);
      expect(h.started.single.sources, ['/home/docs/a.txt']);
      expect(h.started.single.destination, '/tmp');
      expect(workspace(tester).shelf.length, 1);
      await tester.tap(find.text('Move Here'));
      await h.settle(tester);
      expect(h.started.last.kind, OpKind.move);
      expect(workspace(tester).shelf.isEmpty, isTrue);
      expect(find.byType(ShelfStrip), findsNothing);
    });

    testWidgets('nothing is put into the folder the items are in', (
      tester,
    ) async {
      await h.pump(tester);
      await down(tester);
      await addToShelf(tester);
      await tester.tap(find.text('Copy Here'));
      await h.settle(tester);
      expect(h.started, isEmpty);
      expect(
        find.text('The shelf’s items are in this folder already'),
        findsOneWidget,
      );
    });

    testWidgets('⌃⌘S gives the strip the keys: arrows move along it, Delete '
        'takes an item off, Return shows one in the panel, Esc goes back', (
      tester,
    ) async {
      await h.pump(tester);
      await h.press(tester, LogicalKeyboardKey.keyA, meta: true);
      await addToShelf(tester);
      expect(workspace(tester).shelf.length, 3);
      await h.press(tester, LogicalKeyboardKey.tab); // to /tmp
      await h.press(
        tester,
        LogicalKeyboardKey.keyS,
        meta: true,
        control: true,
      );
      final focus = tester
          .widget<ShelfStrip>(find.byType(ShelfStrip))
          .focusNode;
      expect(focus.hasFocus, isTrue);
      expect(find.text('Show in the panel'), findsOneWidget);
      await h.press(tester, LogicalKeyboardKey.arrowRight);
      await h.press(tester, LogicalKeyboardKey.backspace);
      expect(
        [for (final i in workspace(tester).shelf.items) i.name],
        ['a.txt', 'c.md'],
      );
      await h.press(tester, LogicalKeyboardKey.enter);
      final right = panel(tester, 1).state.active!;
      expect(right.location.path, '/home/docs');
      expect(right.focused?.name, 'c.md');
      expect(focus.hasFocus, isFalse);
      await h.press(
        tester,
        LogicalKeyboardKey.keyS,
        meta: true,
        control: true,
      );
      expect(focus.hasFocus, isTrue);
      await h.press(tester, LogicalKeyboardKey.escape);
      expect(focus.hasFocus, isFalse);
      expect(find.byType(ShelfStrip), findsOneWidget);
      // ⌃⌘S from the strip hides it.
      await h.press(
        tester,
        LogicalKeyboardKey.keyS,
        meta: true,
        control: true,
      );
      await h.press(
        tester,
        LogicalKeyboardKey.keyS,
        meta: true,
        control: true,
      );
      expect(find.byType(ShelfStrip), findsNothing);
    });

    testWidgets('an item gone from the disk shows faint, says so, and is not '
        'put', (tester) async {
      await h.pump(tester);
      await down(tester, 2); // b.txt
      await addToShelf(tester);
      await down(tester); // c.md
      await addToShelf(tester);
      h.folders['/home/docs']!.removeWhere((e) => e.name == 'b.txt');
      h.changes.add('left-1');
      await h.settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await h.settle(tester);
      expect(
        [for (final i in workspace(tester).shelf.items) i.missing],
        [true, false],
      );
      // The test font is wide: the words lose their middle, not their place.
      expect(
        find.byWidgetPredicate(
          (w) => w is AppLabelAndDetail && w.detail == 'no longer there',
        ),
        findsOneWidget,
      );
      await h.press(tester, LogicalKeyboardKey.tab);
      await tester.tap(find.text('Copy Here'));
      await h.settle(tester);
      expect(h.started.single.sources, ['/home/docs/c.md']);
    });

    testWidgets('fits a narrow window at the largest text size', (
      tester,
    ) async {
      await h.pump(tester, size: const Size(900, 600), textScale: 1.6);
      await h.press(tester, LogicalKeyboardKey.keyA, meta: true);
      await addToShelf(tester);
      expect(find.byType(ShelfStrip), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the window with Vim keys', () {
    late WorkspaceHarness h;

    setUp(() async {
      h = WorkspaceHarness();
      await h.setUp(vim: true);
    });

    tearDown(() => h.tearDown());

    Future<void> keys(WidgetTester tester, String typed) =>
        h.type(tester, typed);

    testWidgets('yy and p copy, the shelf stays; dd and p move, it empties; '
        'ys adds; uy lets go', (tester) async {
      await h.pump(tester);
      await keys(tester, 'jyy');
      await h.press(tester, LogicalKeyboardKey.tab);
      await keys(tester, 'p');
      expect(h.started.single.kind, OpKind.copy);
      expect(h.started.single.sources, ['/home/docs/a.txt']);
      expect(find.textContaining('1 on the shelf'), findsWidgets);
      await h.press(tester, LogicalKeyboardKey.tab);
      await keys(tester, 'jdd');
      expect(find.textContaining('1 cut'), findsWidgets);
      await keys(tester, 'jys');
      await h.press(tester, LogicalKeyboardKey.tab);
      h.started.clear();
      await keys(tester, 'p');
      expect([for (final r in h.started) r.kind], [OpKind.copy, OpKind.move]);
      expect(h.started.first.sources, ['/home/docs/c.md']);
      expect(h.started.last.sources, ['/home/docs/b.txt']);
      expect(
        find.textContaining('1 on the shelf'),
        findsWidgets,
        reason: 'cut left',
      );
      await keys(tester, 'uy');
      expect(find.byType(ShelfStrip), findsNothing);
    });
  });
}
