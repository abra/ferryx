import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operations_service/operations_service.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

import 'support/workspace_harness.dart';

class _FolderSync extends Mock implements FolderSyncService {}

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);
  late WorkspaceHarness h;
  final en = lookupFerryxLocalizations(const Locale('en'));
  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp();
    h.addFolder('/home/second');
  });
  tearDown(() => h.tearDown());
  PanelCubit left(WidgetTester tester) =>
      tester.element(find.byType(PanelView).first).read<PanelCubit>();
  Future<void> command(WidgetTester tester, AppCommand command) async {
    Actions.invoke(
      tester.element(find.byType(PanelView).first),
      CommandIntent(command),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'exit captures current tabs and split before the snapshot timer',
    (
      tester,
    ) async {
      final closing = ValueNotifier(false);
      addTearDown(closing.dispose);
      final snapshots = <WorkspaceSnapshot>[];
      await h.pump(tester, onSnapshot: snapshots.add, flushSnapshots: closing);
      final panel = left(tester);
      await panel.newTab(location: const Location.native('/home/second'));
      await tester.pump();
      final splitter = tester.widget<AppSplitter>(find.byType(AppSplitter));
      splitter.onAction(AppSplitterAction.right);
      splitter.onAction(AppSplitterAction.done);
      expect(snapshots, isEmpty);

      closing.value = true;
      expect(snapshots.single.left.tabs.last.location.path, '/home/second');
      expect(snapshots.single.left.activeIndex, 1);
      expect(snapshots.single.splitFraction, closeTo(0.52, 0.0001));
      await tester.pump(const Duration(milliseconds: 401));
      expect(snapshots, hasLength(1));
    },
  );

  testWidgets('closing the workspace still takes a completed comparison', (
    tester,
  ) async {
    final service = _FolderSync();
    final started = Completer<void>();
    final reply = Completer<int>();
    h.addFolder('/compare-left', ['sample']);
    h.addFolder('/compare-right', ['sample']);
    await tester.runAsync(
      () => h.preferences.update(
        (p) => p.copyWith(
          compareOptions: const CompareOptions(quickContents: true),
        ),
      ),
    );
    when(() => service.compareContents(any())).thenAnswer((_) {
      started.complete();
      return reply.future;
    });
    when(() => service.takeContentDifferences(42)).thenAnswer((_) async => [0]);
    when(() => h.operations.current).thenReturn({
      42: const OperationProgress(
        id: 42,
        kind: OpKind.compareContents,
        state: OpState.done,
      ),
    });
    await h.pump(
      tester,
      left: '/compare-left',
      right: '/compare-right',
      folderSync: service,
    );
    await command(tester, AppCommand.compareFolders);
    expect(started.isCompleted, isTrue);
    await tester.pumpWidget(const SizedBox());
    reply.complete(42);
    await tester.pumpAndSettle();
    verify(() => service.takeContentDifferences(42)).called(1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('named workspace restores tabs and view mode after navigation', (
    tester,
  ) async {
    await h.pump(tester);
    final panel = left(tester);
    await panel.newTab(location: const Location.native('/home/second'));
    panel.setLayout(PanelLayout.thumbnailIndex);
    await tester.pumpAndSettle();
    await command(tester, AppCommand.manageWorkspaces);
    await tester.enterText(find.byType(AppTextField), 'Research');
    await tester.tap(find.text(en.workspaceSaveCurrent));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.actionClose));
    await tester.pumpAndSettle();
    await panel.closeTab();
    panel.setLayout(0);
    await tester.pumpAndSettle();
    expect(panel.state.tabs.length, 1);
    final previous = [
      panel.state.active!.id,
      tester
          .element(find.byType(PanelView).last)
          .read<PanelCubit>()
          .state
          .active!
          .id,
    ];
    await command(tester, AppCommand.manageWorkspaces);
    await tester.tap(find.text('Research'));
    await tester.pump();
    await tester.tap(find.text(en.actionOpen));
    await tester.pumpAndSettle();
    expect(panel.state.tabs.length, 2);
    expect(panel.state.active!.location, const Location.native('/home/second'));
    expect(panel.state.active!.layoutIndex, PanelLayout.thumbnailIndex);
    expect(
      tester.widget<PanelView>(find.byType(PanelView).first).focusNode.hasFocus,
      isTrue,
    );
    for (final id in previous) {
      verify(() => h.files.closeListing(id)).called(1);
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('Compare Files resolves marked files or both panel cursors', (
    tester,
  ) async {
    h.addFolder('/home/docs', ['alpha.txt', 'beta.txt']);
    h.addFolder('/tmp', ['other.txt']);
    final pairs = <(Location, Location)>[];
    await h.pump(tester, onCompare: (_, a, b) async => pairs.add((a, b)));
    final panel = left(tester),
        other = tester.element(find.byType(PanelView).last).read<PanelCubit>();
    panel.moveCursorTo(
      panel.state.active!.rows.indexWhere((r) => r.name == 'alpha.txt'),
    );
    other.moveCursorTo(
      other.state.active!.rows.indexWhere((r) => r.name == 'other.txt'),
    );
    await tester.pumpAndSettle();
    await command(tester, AppCommand.compareFiles);
    expect(pairs.single, (
      const Location.native('/home/docs/alpha.txt'),
      const Location.native('/tmp/other.txt'),
    ));
    panel.toggleSelectionAt(
      panel.state.active!.rows.indexWhere((r) => r.name == 'alpha.txt'),
    );
    panel.toggleSelectionAt(
      panel.state.active!.rows.indexWhere((r) => r.name == 'beta.txt'),
    );
    await tester.pumpAndSettle();
    await command(tester, AppCommand.compareFiles);
    expect(pairs.last, (
      const Location.native('/home/docs/alpha.txt'),
      const Location.native('/home/docs/beta.txt'),
    ));
    // Marks may outlive a filtered/replaced listing: two keys are not
    // necessarily two visible targets for the comparison handler.
    h.folders['/home/docs']!.removeWhere((row) => row.name == 'beta.txt');
    await panel.refresh();
    await tester.pumpAndSettle();
    final current = panel.state.active!;
    // Keep a stale selected key to exercise the handler's defensive guard.
    panel.emit(
      panel.state.withActive(
        current.copyWith(
          selected: {'alpha.txt', 'beta.txt'},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await command(tester, AppCommand.compareFiles);
    expect(pairs, hasLength(2));
    expect(h.started, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'thumbnail grid is lazy and supports arrows in ${brightness.name}',
      (tester) async {
        h.addFolder(
          '/home/images',
          List.generate(
            1000,
            (i) => 'photo-${i.toString().padLeft(4, '0')}.png',
          ),
        );
        await h.pump(
          tester,
          left: '/home/images',
          brightness: brightness,
          textScale: 1.25,
        );
        await command(tester, AppCommand.thumbnailsView);
        final panel = left(tester),
            columns = left(tester).geometry.columnsPerRow;
        expect(columns, greaterThan(1));
        expect(find.byType(GridView), findsOneWidget);
        expect(find.byType(HintTarget).evaluate().length, lessThan(100));
        panel.moveCursorTo(columns);
        await tester.pumpAndSettle();
        await h.press(tester, LogicalKeyboardKey.arrowDown);
        expect(panel.state.active!.cursor, 2 * columns);
        await h.press(tester, LogicalKeyboardKey.arrowRight);
        expect(panel.state.active!.cursor, 2 * columns + 1);
        panel.moveCursorTo(columns - 1);
        await tester.pumpAndSettle();
        await h.press(tester, LogicalKeyboardKey.arrowRight);
        expect(panel.state.active!.cursor, columns - 1);
        panel.moveLast();
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (w) => w is AppMiddleEllipsis && w.text == 'photo-0999.png',
          ),
          findsOneWidget,
        );
        await command(tester, AppCommand.viewMode3);
        expect(find.byType(GridView), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
