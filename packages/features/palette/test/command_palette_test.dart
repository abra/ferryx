import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:palette_feature/palette_feature.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

/// The window as the app builds it: the global keys at the root with the
/// palette's handler there, a window scope with its commands, a panel
/// scope around the focused panel.
void main() {
  const platform = TargetPlatform.macOS;
  late List<String> ran;
  late FocusNode panel;
  late RecentItems recents;

  setUp(() async {
    ran = [];
    panel = FocusNode(debugLabel: 'panel');
    recents = await RecentItems.load(
      InMemorySideStorage(),
      key: RecentItems.commandsKey,
    );
  });

  tearDown(() => panel.dispose());

  Future<void> pump(
    WidgetTester tester, {
    bool vim = false,
    Locale locale = const Locale('en'),
    Map<AppCommand, VoidCallback> panelHandlers = const {},
    Set<AppCommand> unavailable = const {},
  }) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final map = ShortcutMap.forUser(
      platform,
      vimMotions: vim,
      unavailable: unavailable,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        locale: locale,
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        builder: (context, child) => CommandShortcuts(
          shortcuts: map.toShortcuts(
            platform,
            scopes: const {CommandScope.global},
          ),
          child: CommandHandlers(
            handlers: {
              AppCommand.commandPalette: () {
                final focused = FocusManager.instance.primaryFocus?.context;
                if (focused == null) return;
                showCommandPalette(
                  focused,
                  shortcutMap: map,
                  vim: vim,
                  recents: recents,
                );
              },
            },
            child: child!,
          ),
        ),
        home: Scaffold(
          body: CommandHandlers(
            handlers: {
              AppCommand.refresh: () => ran.add('refresh'),
              AppCommand.copyTo: () => ran.add('window copy'),
            },
            child: CommandShortcuts(
              shortcuts: map.toShortcuts(
                platform,
                scopes: const {CommandScope.panel},
              ),
              child: CommandHandlers(
                handlers: {
                  AppCommand.moveDown: () => ran.add('down'),
                  AppCommand.copyTo: () {
                    // The command runs where the focus is again.
                    ran.add('panel copy, focus ${panel.hasPrimaryFocus}');
                  },
                  AppCommand.vimVisual: () => ran.add('visual'),
                  ...panelHandlers,
                },
                child: Focus(
                  focusNode: panel,
                  autofocus: true,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> openPalette(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pumpAndSettle();
  }

  List<String> labels(WidgetTester tester) => [
    for (final item
        in tester
            .widget<AppQuickPicker<AppCommand>>(
              find.byType(AppQuickPicker<AppCommand>),
            )
            .entries
            .whereType<AppQuickPickerItem<AppCommand>>())
      item.label,
  ];

  testWidgets('offers the commands handled where the focus was, and only '
      'those', (tester) async {
    await pump(tester);
    await openPalette(tester);
    expect(
      labels(tester),
      unorderedEquals(['Copy To…', 'Refresh', 'Move Down']),
      reason:
          'the window\'s and the panel\'s; not the palette itself, not '
          'Vim keys while they are off, nothing no handler takes',
    );
    expect(find.text('F5'), findsOneWidget, reason: 'its key in a cap');
  });

  testWidgets('what this desktop lacks is left out, though a handler '
      'takes it', (tester) async {
    final handlers = {AppCommand.quickLook: () => ran.add('quick look')};
    await pump(tester, panelHandlers: handlers);
    await openPalette(tester);
    expect(labels(tester), contains('Quick Look'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await pump(
      tester,
      panelHandlers: handlers,
      unavailable: const {AppCommand.quickLook},
    );
    await openPalette(tester);
    expect(labels(tester), isNot(contains('Quick Look')));
    await tester.enterText(find.byType(EditableText), 'quick look');
    await tester.pump();
    expect(labels(tester), isEmpty);
    expect(ran, isEmpty);
  });

  testWidgets('a command picked runs after the focus is back, as its key '
      'would: the innermost handler', (tester) async {
    await pump(tester);
    await openPalette(tester);
    expect(panel.hasFocus, isFalse);
    await tester.enterText(find.byType(EditableText), 'copy');
    await tester.pump();
    expect(labels(tester).first, 'Copy To…');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(AppQuickPicker<AppCommand>), findsNothing);
    expect(ran, ['panel copy, focus true']);
    expect(recents.items, ['copyTo']);
  });

  testWidgets('the commands run lately lead the list next time', (
    tester,
  ) async {
    await recents.record(AppCommand.refresh.name);
    await pump(tester);
    await openPalette(tester);
    final picker = tester.widget<AppQuickPicker<AppCommand>>(
      find.byType(AppQuickPicker<AppCommand>),
    );
    expect(picker.entries.first, isA<AppQuickPickerHeader<AppCommand>>());
    expect(
      (picker.entries.first as AppQuickPickerHeader<AppCommand>).title,
      'Recently used',
    );
    expect(labels(tester).first, 'Refresh');
    // Return runs the lit one: the most recent.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(ran, ['refresh']);
  });

  testWidgets('Esc, or its own key again, closes it and runs nothing', (
    tester,
  ) async {
    await pump(tester);
    await openPalette(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AppQuickPicker<AppCommand>), findsNothing);
    expect(panel.hasPrimaryFocus, isTrue);
    await openPalette(tester);
    expect(find.byType(AppQuickPicker<AppCommand>), findsOneWidget);
    await openPalette(tester);
    expect(find.byType(AppQuickPicker<AppCommand>), findsNothing);
    expect(ran, isEmpty);
  });

  testWidgets('with Vim keys on, Vim\'s commands come with their letters', (
    tester,
  ) async {
    await pump(tester, vim: true);
    await openPalette(tester);
    expect(labels(tester), contains('Visual Selection'));
    expect(find.text('v'), findsWidgets);
    expect(find.text('j'), findsOneWidget, reason: 'Move Down as Vim has it');
  });

  testWidgets('in Russian, English words find commands too', (tester) async {
    await pump(tester, locale: const Locale('ru'));
    await openPalette(tester);
    await tester.enterText(find.byType(EditableText), 'refresh');
    await tester.pump();
    final ru = lookupFerryxLocalizations(const Locale('ru'));
    expect(labels(tester), [ru.cmdRefresh]);
    // The English name shows beside it, as what matched.
    expect(find.text('Refresh'), findsOneWidget);
  });
}
