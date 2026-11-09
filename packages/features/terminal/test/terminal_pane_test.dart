import 'dart:convert';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';
import 'package:terminal_feature/terminal_feature.dart';
import 'package:terminal_service/terminal_service.dart';
import 'package:xterm/xterm.dart';

import 'fakes.dart';

class _MockService extends Mock implements TerminalService {}

class _MockPreferences extends Mock implements PreferencesService {}

/// The terminal in a window whose own commands are recorded, its keys
/// pressed as a keyboard would.
void main() {
  late _MockService service;
  late _MockPreferences preferences;
  late List<FakeSession> sessions;
  late List<AppCommand> reached;
  late List<String> placed;
  late FocusNode focus;
  late TerminalSessionCubit cubit;
  late ValueNotifier<TerminalPreferences> displayPreferences;

  final en = lookupFerryxLocalizations(const Locale('en'));

  setUpAll(() {
    registerFallbackValue(const TerminalStart(cols: 1, rows: 1));
  });

  setUp(() {
    service = _MockService();
    preferences = _MockPreferences();
    sessions = [];
    reached = [];
    placed = [];
    focus = FocusNode(debugLabel: 'terminal');
    displayPreferences = ValueNotifier(const TerminalPreferences());
    when(() => preferences.current).thenReturn(const Preferences());
    when(() => service.start(any())).thenAnswer((_) async {
      final session = FakeSession();
      sessions.add(session);
      return session;
    });
  });

  tearDown(() {
    focus.dispose();
    displayPreferences.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    AppPlatformStyle style = AppPlatformStyle.macos,
    TerminalPlacement placement = const TerminalPlacement(),
    bool vim = false,
  }) async {
    final theme = AppTheme.of(style, Brightness.light);
    final platform = theme.platform;
    cubit = TerminalSessionCubit(
      service: service,
      preferences: preferences,
      platform: platform,
    );
    addTearDown(cubit.close);
    final map = ShortcutMap.forUser(platform, vimMotions: vim);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        // The window's keys at the root, as the app has them: Vim's `cd`,
        // `gj` and the like among them.
        builder: (context, child) => CommandShortcuts(
          shortcuts: map.toShortcuts(
            platform,
            scopes: const {CommandScope.global},
          ),
          child: child!,
        ),
        home: Scaffold(
          body: CommandHandlers(
            // The window's commands, as the workspace and the app answer
            // them.
            handlers: {
              for (final command in AppCommand.inScope(CommandScope.global))
                command: () => reached.add(command),
            },
            child: ValueListenableBuilder<TerminalPreferences>(
              valueListenable: displayPreferences,
              builder: (context, prefs, _) => TerminalPane(
                cubit: cubit,
                focusNode: focus,
                shortcutMap: map,
                fontFamily: prefs.fontFamily,
                fontSize: prefs.fontSize,
                placement: placement,
                onHide: () => placed.add('hide'),
                onTogglePanels: () => placed.add('panels'),
                onToggleFullWindow: () => placed.add('full'),
              ),
            ),
          ),
        ),
      ),
    );
    cubit.show('/work');
    focus.requestFocus();
    await tester.pumpAndSettle();
    if (sessions.isNotEmpty) {
      sessions.last.emit(
        const TerminalShellState(idle: true, folder: '/work/project'),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool meta = false,
    bool control = false,
    bool alt = false,
    bool shift = false,
  }) async {
    final held = [
      if (meta) LogicalKeyboardKey.metaLeft,
      if (control) LogicalKeyboardKey.controlLeft,
      if (alt) LogicalKeyboardKey.altLeft,
      if (shift) LogicalKeyboardKey.shiftLeft,
    ];
    for (final k in held) {
      await tester.sendKeyDownEvent(k);
    }
    await tester.sendKeyEvent(key);
    for (final k in held.reversed) {
      await tester.sendKeyUpEvent(k);
    }
    await tester.pump();
  }

  testWidgets('the shell starts at the view\'s size, the bar names its '
      'folder and offers its places', (tester) async {
    await pump(tester);
    expect(sessions, hasLength(1));
    expect(
      tester.widget<AppMiddleEllipsis>(find.byType(AppMiddleEllipsis)).text,
      '/work/project',
    );
    Finder button(String tooltip) => find.byWidgetPredicate(
      (w) => w is AppIconButton && w.tooltip == tooltip,
    );
    expect(button(en.cmdHideTerminal), findsOneWidget);
    expect(button(en.cmdToggleTerminal), findsOneWidget);
    expect(button(en.cmdTogglePanelsOverTerminal), findsOneWidget);
    await tester.tap(button(en.cmdHideTerminal));
    await tester.tap(button(en.cmdToggleTerminal));
    await tester.tap(button(en.cmdTogglePanelsOverTerminal));
    expect(placed, ['hide', 'full', 'panels']);
  });

  testWidgets('changing the font updates the open terminal without losing '
      'its session, text or selection', (tester) async {
    await pump(tester);
    final session = sessions.single;
    session.emit(TerminalOutput(utf8.encode('kept output\r\n')));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyA, meta: true);

    final before = tester.widget<TerminalView>(find.byType(TerminalView));
    final beforeState = tester.state<TerminalViewState>(
      find.byType(TerminalView),
    );
    final selection = before.controller!.selection;
    final contents = cubit.terminal.buffer.getText();
    displayPreferences.value = displayPreferences.value.copyWith(
      fontFamily: 'Menlo',
    );
    await tester.pumpAndSettle();

    final after = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(after.textStyle.fontFamily, 'Menlo');
    expect(after.textStyle.fontSize, 12);
    expect(after.terminal, same(before.terminal));
    expect(after.controller, same(before.controller));
    expect(after.controller!.selection, selection);
    expect(
      tester.state<TerminalViewState>(find.byType(TerminalView)),
      same(beforeState),
    );
    expect(cubit.terminal.buffer.getText(), contents);
    expect(sessions, hasLength(1));
    expect(session.closed, isFalse);

    displayPreferences.value = displayPreferences.value.copyWith(
      fontFamily: '',
    );
    await tester.pumpAndSettle();
    final restored = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(restored.textStyle.fontFamily, before.textStyle.fontFamily);
    expect(sessions, hasLength(1));
  });

  testWidgets('on macOS: Return, arrows and Control keys go to the shell; '
      'the window keeps its Command chords and the terminal\'s place', (
    tester,
  ) async {
    await pump(tester);
    final session = sessions.single;
    await chord(tester, LogicalKeyboardKey.enter);
    await chord(tester, LogicalKeyboardKey.arrowUp);
    await chord(tester, LogicalKeyboardKey.keyC, control: true);
    await chord(tester, LogicalKeyboardKey.keyA, control: true);
    await chord(tester, LogicalKeyboardKey.tab);
    expect(session.text, '\r\x1b[A\x03\x01\t');
    expect(reached, isEmpty, reason: 'no window command took those keys');

    // ⌃⌥↓ hides the terminal, ⌥⌘O the whole window, ⇧⌘← the left panel,
    // ⌘T a new tab.
    await chord(tester, LogicalKeyboardKey.arrowDown, control: true, alt: true);
    await chord(tester, LogicalKeyboardKey.keyO, meta: true, alt: true);
    await chord(tester, LogicalKeyboardKey.keyO, control: true, alt: true);
    await chord(tester, LogicalKeyboardKey.arrowLeft, meta: true, shift: true);
    await chord(tester, LogicalKeyboardKey.keyT, meta: true);
    expect(reached, [
      AppCommand.hideTerminal,
      AppCommand.toggleTerminal,
      AppCommand.togglePanelsOverTerminal,
      AppCommand.focusLeftPanel,
      AppCommand.newTab,
    ]);
    expect(session.text, '\r\x1b[A\x03\x01\t');
  });

  testWidgets('with Vim keys on, letters typed in the shell never reach the '
      'window: `cd` and `gj` are text there', (tester) async {
    await pump(tester, vim: true);
    for (final key in [
      LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.keyG,
      LogicalKeyboardKey.keyJ,
      LogicalKeyboardKey.space,
    ]) {
      await chord(tester, key);
      expect(KeySequenceState.pending, isNull, reason: '$key armed nothing');
    }
    expect(reached, isEmpty);
    // Command chords still reach the window from the shell.
    await chord(tester, LogicalKeyboardKey.keyT, meta: true);
    expect(reached, [AppCommand.newTab]);
  });

  testWidgets('the terminal\'s own keys win over the window\'s: Command-C '
      'copies its text, not a path; Command-K clears it', (tester) async {
    await pump(tester);
    final session = sessions.single;
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    session.emit(TerminalOutput(utf8.encode('hello world\r\n')));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyA, meta: true);
    await chord(tester, LogicalKeyboardKey.keyC, meta: true);
    expect(copied.single, contains('hello world'));
    await chord(tester, LogicalKeyboardKey.keyK, meta: true);
    expect(session.written.last, 0x0c);
    expect(reached, isEmpty);
  });

  testWidgets('on Linux: Ctrl+letter is the shell\'s, Ctrl+Shift the '
      'terminal\'s or the window\'s', (tester) async {
    await pump(tester, style: AppPlatformStyle.gnome);
    final session = sessions.single;
    // Ctrl+R, Ctrl+W, Ctrl+D: reverse search, delete a word, end of input.
    await chord(tester, LogicalKeyboardKey.keyR, control: true);
    await chord(tester, LogicalKeyboardKey.keyW, control: true);
    await chord(tester, LogicalKeyboardKey.keyD, control: true);
    expect(session.text, '\x12\x17\x04');
    expect(reached, isEmpty);
    // Ctrl+Shift+N a new folder; Ctrl+Shift+Down hides the terminal.
    await chord(tester, LogicalKeyboardKey.keyN, control: true, shift: true);
    await chord(
      tester,
      LogicalKeyboardKey.arrowDown,
      control: true,
      shift: true,
    );
    expect(reached, [AppCommand.newFolder, AppCommand.hideTerminal]);
    expect(session.text, '\x12\x17\x04');
  });

  testWidgets('an ended shell says so; Return starts another', (tester) async {
    await pump(tester);
    sessions.single.emit(const TerminalExited(2));
    await tester.pumpAndSettle();
    expect(find.text(en.terminalExitedWithCode(2)), findsOneWidget);
    expect(find.text(en.terminalRestart), findsOneWidget);
    await chord(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(sessions, hasLength(2));
    expect(find.text(en.terminalRestart), findsNothing);
  });

  testWidgets('a shell that cannot start says why; the button tries again', (
    tester,
  ) async {
    var fail = true;
    when(() => service.start(any())).thenAnswer((_) async {
      if (fail) {
        fail = false;
        throw const FerryxException(
          FerryxErrorKind.notFound,
          '/bin/nope was not found',
        );
      }
      final session = FakeSession();
      sessions.add(session);
      return session;
    });
    await pump(tester);
    expect(find.text(en.terminalStartFailed), findsOneWidget);
    expect(find.textContaining('/bin/nope was not found'), findsOneWidget);
    await tester.tap(find.text(en.terminalRestart));
    await tester.pumpAndSettle();
    expect(sessions, hasLength(1));
    expect(find.text(en.terminalStartFailed), findsNothing);
  });

  testWidgets('the menu key opens the terminal\'s menu by its cursor', (
    tester,
  ) async {
    await pump(tester);
    await chord(tester, LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(find.text(en.cmdTerminalPaste), findsOneWidget);
    expect(find.text(en.cmdTerminalClear), findsOneWidget);
    expect(find.text(en.cmdHideTerminal), findsOneWidget);
    await tester.tap(find.text(en.cmdHideTerminal));
    await tester.pumpAndSettle();
    expect(placed, ['hide']);
  });

  testWidgets('the bar menu selects and copies output, pastes while running '
      'and disables paste after the shell exits', (tester) async {
    await pump(tester);
    final session = sessions.single;
    session.emit(TerminalOutput(utf8.encode('menu output\r\n')));
    await tester.pumpAndSettle();
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        if (call.method == 'Clipboard.getData') {
          return {'text': 'pasted command'};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    Future<void> menu() async {
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is AppIconButton && w.tooltip == en.terminalActions,
        ),
      );
      await tester.pumpAndSettle();
    }

    AppMenuItem item(String label) => tester.widget<AppMenuItem>(
      find.widgetWithText(AppMenuItem, label),
    );

    await menu();
    expect(item(en.cmdTerminalCopy).enabled, isFalse);
    expect(item(en.cmdTerminalPaste).enabled, isTrue);
    await tester.tap(find.text(en.cmdTerminalSelectAll));
    await tester.pumpAndSettle();
    await menu();
    expect(item(en.cmdTerminalCopy).enabled, isTrue);
    await tester.tap(find.text(en.cmdTerminalCopy));
    await tester.pumpAndSettle();
    expect(copied.single, contains('menu output'));

    await menu();
    await tester.tap(find.text(en.cmdTerminalPaste));
    await tester.pumpAndSettle();
    expect(session.text, contains('pasted command'));
    expect(reached, isEmpty);

    session.emit(const TerminalExited(0));
    await tester.pumpAndSettle();
    await menu();
    expect(item(en.cmdTerminalPaste).enabled, isFalse);
    await tester.tap(find.text(en.cmdTerminalPaste));
    await tester.pumpAndSettle();
    expect(find.text(en.cmdTerminalPaste), findsOneWidget);
    expect(session.text, 'pasted command');
  });

  testWidgets('in the window\'s top row the bar keeps room for the window\'s '
      'buttons', (tester) async {
    await pump(
      tester,
      placement: const TerminalPlacement(
        fullWindow: true,
        decor: WindowDecor(leadingInset: 80),
      ),
    );
    final bar = tester.getRect(find.byType(TerminalBar));
    expect(
      bar.height,
      AppTheme.of(
        AppPlatformStyle.macos,
        Brightness.light,
      ).extension<AppMetrics>()!.topBarHeight,
    );
    final icon = tester.getRect(find.byIcon(AppIcons.terminal).first);
    expect(icon.left, greaterThanOrEqualTo(80));
    expect(find.byIcon(AppIcons.showAsWindow), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is AppIconButton && w.tooltip == en.terminalRestoreLayout,
      ),
    );
    expect(placed, ['full']);
  });
}
