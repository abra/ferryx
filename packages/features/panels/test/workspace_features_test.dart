import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:shortcuts/shortcuts.dart';

import 'support/workspace_harness.dart';

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
