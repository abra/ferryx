import 'dart:convert';
import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx/app/terminal_link.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';
import 'package:terminal_feature/terminal_feature.dart';
import 'package:terminal_service/terminal_service.dart';

import '../../packages/features/panels/test/support/workspace_harness.dart';
import '../../packages/features/terminal/test/fakes.dart';

class _Service extends Mock implements TerminalService {}

void main() {
  setUpAll(() {
    WorkspaceHarness.registerFallbacks();
    registerFallbackValue(
      const TerminalStart(shell: '', folder: '/home', cols: 80, rows: 24),
    );
  });
  late WorkspaceHarness h;
  late _Service service;
  late TerminalLink link;
  late List<FakeSession> sessions;
  final en = lookupFerryxLocalizations(const Locale('en'));

  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp(vim: true);
    service = _Service();
    sessions = [];
    when(() => service.start(any())).thenAnswer((_) async {
      final session = FakeSession();
      sessions.add(session);
      return session;
    });
  });
  tearDown(() => h.tearDown());

  Future<void> pump(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
  }) => h.pump(
    tester,
    brightness: brightness,
    terminal: WorkspaceTerminal(
      create: () => link = TerminalLink(
        service: service,
        preferences: h.preferences,
        platform: TargetPlatform.macOS,
      ),
      builder: (context, controller, view) => TerminalPane(
        cubit: TerminalLink.of(controller).cubit,
        focusNode: view.focusNode,
        shortcutMap: h.shortcutMap,
        fontSize: 12,
        placement: TerminalPlacement(
          inPanel: view.inPanel,
          asTab: view.asTab,
          panelsHidden: view.panelsHidden,
          fullWindow: view.fullWindow,
          decor: view.decor,
        ),
        placementActions: view.placementActions,
        onHide: view.onHide,
        onTogglePanels: view.onTogglePanels,
        onToggleFullWindow: view.onToggleFullWindow,
      ),
    ),
  );

  Finder panel(PanelSide side) =>
      find.byWidgetPredicate((w) => w is PanelView && w.key == ValueKey(side));
  PanelCubit cubit(WidgetTester tester, PanelSide side) =>
      tester.element(panel(side)).read<PanelCubit>();
  Finder getPane() => find.byType(TerminalPane);
  Future<void> command(WidgetTester tester, AppCommand command) async {
    invokeCommand(
      tester.element(find.byType(TerminalPane, skipOffstage: false)),
      command,
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await h.press(tester, LogicalKeyboardKey.backquote, control: true);
    expect(sessions, hasLength(1));
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name}: move a live terminal between bottom, tab and panels',
      (tester) async {
        await pump(tester, brightness: brightness);
        final rightBefore = tester.getRect(panel(PanelSide.right));
        await open(tester);
        final state = tester.state(getPane());
        final session = sessions.single;
        session.emit(
          TerminalOutput(utf8.encode('session survives every move\r\n')),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getRect(getPane()).right,
          tester.getRect(panel(PanelSide.left)).right,
        );
        expect(tester.getRect(panel(PanelSide.right)), rightBefore);

        await command(tester, AppCommand.terminalAsTab);
        var strip = tester.widget<AppTabStrip>(find.byType(AppTabStrip));
        expect(strip.tabs.last.label, en.terminalTitle);
        expect(strip.tabs.last.icon, AppIcons.terminal);
        expect(strip.active, 1);
        expect(tester.state(getPane()), same(state));
        strip.onSelect(0);
        await tester.pumpAndSettle();
        expect(getPane(), findsNothing);
        expect(find.byType(TerminalPane, skipOffstage: false), findsOneWidget);
        strip = tester.widget<AppTabStrip>(find.byType(AppTabStrip));
        strip.onSelect(1);
        await tester.pumpAndSettle();
        expect(tester.state(getPane()), same(state));
        expect(
          tester.widget<TerminalPane>(getPane()).focusNode.hasFocus,
          isTrue,
        );

        await command(tester, AppCommand.terminalInRightPanel);
        expect(
          tester.getRect(getPane()).left,
          tester.getRect(panel(PanelSide.right)).left,
        );
        await command(tester, AppCommand.terminalBelowFiles);
        expect(find.byType(AppTabStrip), findsNothing);
        expect(tester.state(getPane()), same(state));
        await command(tester, AppCommand.terminalInLeftPanel);
        expect(tester.state(getPane()), same(state));
        expect(sessions, hasLength(1));
        expect(session.closed, isFalse);
        expect(
          link.cubit.terminal.buffer.getText(),
          contains('session survives every move'),
        );
        await tester.pumpWidget(const SizedBox());
        expect(session.closed, isTrue);
      },
    );
  }

  for (final vim in [false, true]) {
    testWidgets(
      'Vim=$vim: shell input stays out of file handlers and operations',
      (tester) async {
        await tester.runAsync(
          () => h.preferences.update((p) => p.copyWith(vimMode: vim)),
        );
        await pump(tester);
        await open(tester);
        final before = cubit(tester, PanelSide.left).state.active!;
        await command(tester, AppCommand.terminalAsTab);
        for (final key in [
          LogicalKeyboardKey.keyC,
          LogicalKeyboardKey.keyD,
          LogicalKeyboardKey.keyG,
          LogicalKeyboardKey.keyJ,
          LogicalKeyboardKey.space,
        ]) {
          await h.press(tester, key);
          expect(KeySequenceState.pending, isNull);
        }
        await h.press(tester, LogicalKeyboardKey.keyC, control: true);
        expect(sessions.single.text, contains('\x03'));
        final after = cubit(tester, PanelSide.left).state.active!;
        expect(after.cursor, before.cursor);
        expect(after.quickSearch, isEmpty);
        expect(after.selected, before.selected);
        expect(
          canInvokeCommand(tester.element(getPane()), AppCommand.deleteItems),
          isFalse,
        );
      },
    );
  }

  testWidgets(
    'Vim tab commands and numbered selection include the visible terminal tab',
    (tester) async {
      await pump(tester);
      await open(tester);
      await command(tester, AppCommand.terminalAsTab);
      tester.widget<AppTabStrip>(find.byType(AppTabStrip)).onReorder(1, 0);
      await tester.pumpAndSettle();
      await command(tester, AppCommand.nextTab);
      Future<void> run(String line) async {
        await h.press(
          tester,
          LogicalKeyboardKey.semicolon,
          shift: true,
          character: ':',
        );
        await tester.enterText(find.byType(AppTextField), line);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
      }

      for (final line in ['tabnext', 'tabprevious']) {
        await run(line);
        expect(getPane(), findsOneWidget);
        await command(tester, AppCommand.nextTab);
        expect(getPane(), findsNothing);
      }
      final files = tester.widget<PanelView>(panel(PanelSide.left));
      expect(
        invokeCommand(files.focusNode.context!, AppCommand.showTab1),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(getPane(), findsOneWidget);
      expect(sessions, hasLength(1));
      expect(sessions.single.closed, isFalse);
    },
  );

  testWidgets(
    'terminal tab reorders, cycles with file tabs and closes independently',
    (tester) async {
      await pump(tester);
      await open(tester);
      await command(tester, AppCommand.terminalAsTab);
      tester.widget<AppTabStrip>(find.byType(AppTabStrip)).onReorder(1, 0);
      await tester.pumpAndSettle();
      var strip = tester.widget<AppTabStrip>(find.byType(AppTabStrip));
      expect(strip.tabs.first.label, en.terminalTitle);
      expect(strip.active, 0);
      await command(tester, AppCommand.nextTab);
      expect(getPane(), findsNothing);
      await h.press(tester, LogicalKeyboardKey.keyG, character: 'g');
      await h.press(tester, LogicalKeyboardKey.keyT, character: 't');
      expect(getPane(), findsOneWidget);
      await command(tester, AppCommand.closeTab);
      expect(getPane(), findsNothing);
      expect(cubit(tester, PanelSide.left).state.tabs, hasLength(1));
      expect(sessions.single.closed, isFalse);
      await open(tester);
      expect(sessions, hasLength(1));
    },
  );

  testWidgets(
    'rapid docking and hide/show during transitions keep one live terminal',
    (tester) async {
      await pump(tester);
      await open(tester);
      final state = tester.state(getPane());
      for (final action in [
        AppCommand.terminalAsTab,
        AppCommand.terminalInRightPanel,
        AppCommand.terminalBelowFiles,
        AppCommand.terminalAcrossPanels,
        AppCommand.toggleTerminal,
      ]) {
        expect(
          invokeCommand(
            tester.element(find.byType(TerminalPane, skipOffstage: false)),
            action,
          ),
          isTrue,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        expect(tester.takeException(), isNull);
        expect(tester.state(getPane()), same(state));
      }
      invokeCommand(tester.element(getPane()), AppCommand.hideTerminal);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final files = tester.widget<PanelView>(panel(PanelSide.right));
      expect(
        invokeCommand(files.focusNode.context!, AppCommand.showTerminal),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(getPane(), findsOneWidget);
      expect(sessions, hasLength(1));
      expect(sessions.single.closed, isFalse);
    },
  );

  testWidgets(
    'restores a terminal tab in the right panel and saves docking changes',
    (tester) async {
      unawaited(
        h.preferences.update(
          (p) => p.copyWith(
            terminal: p.terminal.copyWith(
              place: TerminalPlace.panelTab,
              host: TerminalHost.right,
              tabIndex: 0,
              lines: 9,
            ),
          ),
        ),
      );
      await pump(tester);
      expect(sessions, hasLength(1));
      expect(
        tester.getRect(getPane()).left,
        tester.getRect(panel(PanelSide.right)).left,
      );
      final strip = tester.widget<AppTabStrip>(find.byType(AppTabStrip));
      expect(strip.active, 0);
      expect(strip.tabs.first.label, en.terminalTitle);
      await command(tester, AppCommand.terminalBelowFiles);
      await tester.pump(const Duration(milliseconds: 500));
      expect(h.preferences.current.terminal.host, TerminalHost.right);
      expect(h.preferences.current.terminal.place, TerminalPlace.overlapped);
      expect(h.preferences.current.terminal.lines, 9);
    },
  );
}
