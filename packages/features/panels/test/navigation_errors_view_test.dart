import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/panels_feature.dart';

import 'support/workspace_harness.dart';

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);
  late WorkspaceHarness h;
  final en = lookupFerryxLocalizations(const Locale('en'));
  const target = Location.native('/home/docs/......');
  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp();
  });
  tearDown(() => h.tearDown());

  PanelCubit left(WidgetTester tester) =>
      tester.element(find.byType(PanelView).first).read<PanelCubit>();
  for (final vim in [false, true]) {
    testWidgets(
      'Vim=$vim: Esc dismisses a read error without clearing selection',
      (tester) async {
        await tester.runAsync(
          () => h.preferences.update((p) => p.copyWith(vimMode: vim)),
        );
        await h.pump(tester);
        final panel = left(tester);
        panel.selectWhere((row) => row.name == 'a.txt', select: true);
        final before = panel.state.active!;
        await panel.open(target);
        await tester.pumpAndSettle();
        expect(find.text(en.panelErrorTitle), findsOneWidget);
        await h.press(tester, LogicalKeyboardKey.escape);
        expect(find.text(en.panelErrorTitle), findsNothing);
        expect(panel.state.active!.location, before.location);
        expect(panel.state.active!.selected, before.selected);
        expect(panel.state.active!.cursor, before.cursor);
        expect(
          tester
              .widget<PanelView>(find.byType(PanelView).first)
              .focusNode
              .hasFocus,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Vim=$vim: Retry and Close keep a keyboard path back to the files',
      (tester) async {
        await tester.runAsync(
          () => h.preferences.update((p) => p.copyWith(vimMode: vim)),
        );
        await h.pump(tester);
        final panel = left(tester);
        await panel.open(target);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is AppIconButton && w.tooltip == en.actionClose,
          ),
        );
        await tester.pumpAndSettle();
        expect(panel.state.active!.error, isNull);
        expect(
          tester
              .widget<PanelView>(find.byType(PanelView).first)
              .focusNode
              .hasFocus,
          isTrue,
        );
        await panel.open(target);
        await tester.pumpAndSettle();
        h.addFolder(target.path, ['recovered.txt']);
        await tester.tap(find.widgetWithText(OutlinedButton, en.actionRetry));
        await tester.pumpAndSettle();
        expect(panel.state.active!.location, target);
        expect(panel.state.active!.error, isNull);
        expect(
          tester
              .widget<PanelView>(find.byType(PanelView).first)
              .focusNode
              .hasFocus,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('an invalid :cd is recoverable through the next command', (
    tester,
  ) async {
    await tester.runAsync(
      () => h.preferences.update((p) => p.copyWith(vimMode: true)),
    );
    await h.pump(tester);
    Future<void> run(String command) async {
      await h.press(
        tester,
        LogicalKeyboardKey.semicolon,
        shift: true,
        character: ':',
      );
      await tester.enterText(find.byType(AppTextField), command);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }

    final before = left(tester).state.active!;
    await run('cd ......');
    expect(left(tester).state.active!.location, before.location);
    expect(left(tester).state.active!.failedLocation, target);
    expect(find.text(en.panelErrorTitle), findsOneWidget);
    await run('cd /tmp');
    expect(left(tester).state.active!.location, const Location.native('/tmp'));
    expect(find.text(en.panelErrorTitle), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
