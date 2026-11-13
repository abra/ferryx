import 'dart:async';

import 'package:ferryx/app/app_menu_bar.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shortcuts/shortcuts.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final en = lookupFerryxLocalizations(const Locale('en'));
  late FocusNode panel;
  late FocusNode terminal;
  late TextEditingController text;
  late List<AppCommand> invoked;
  Object? serialized;

  setUp(() {
    panel = FocusNode();
    terminal = FocusNode();
    text = TextEditingController(text: 'hello');
    invoked = [];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.menu,
      (call) async {
        serialized = call.arguments;
        return null;
      },
    );
  });
  tearDown(() {
    panel.dispose();
    terminal.dispose();
    text.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.menu,
      null,
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    ShortcutMap? map,
    Locale locale = const Locale('en'),
    TargetPlatform platform = TargetPlatform.macOS,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        locale: locale,
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: AppMenuBar(
          shortcutMap: map ?? ShortcutMap.forUser(platform),
          child: Scaffold(
            body: CommandHandlers(
              handlers: {
                for (final command in [
                  AppCommand.newTab,
                  AppCommand.copyPaths,
                  AppCommand.pasteItems,
                  AppCommand.selectAll,
                  AppCommand.copyTo,
                  AppCommand.commandPalette,
                ])
                  command: () => invoked.add(command),
              },
              child: Column(
                children: [
                  Focus(
                    focusNode: panel,
                    autofocus: true,
                    child: const Text('panel'),
                  ),
                  TextField(controller: text),
                  CommandHandlers(
                    handlers: {
                      for (final command in [
                        AppCommand.terminalCopy,
                        AppCommand.terminalPaste,
                        AppCommand.terminalSelectAll,
                      ])
                        command: () => invoked.add(command),
                    },
                    child: Focus(
                      focusNode: terminal,
                      child: const Text('terminal'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Iterable<PlatformMenuItem> flatten(PlatformMenuItem item) sync* {
    yield item;
    for (final child in item is PlatformMenu ? item.menus : item.members) {
      yield* flatten(child);
    }
  }

  List<PlatformMenuItem> items(WidgetTester tester) => [
    for (final menu
        in tester
            .widget<PlatformMenuBar>(find.byType(PlatformMenuBar))
            .menus) ...[
      ...flatten(menu),
    ],
  ];

  PlatformMenuItem item(WidgetTester tester, String label) =>
      items(tester).singleWhere((item) => item.label == label);

  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets(
    'native selection invokes the focused command once; dialogs disable panel commands',
    (tester) async {
      await pump(tester);
      final copy = item(tester, en.cmdCopyPaths);
      copy.onSelected!();
      expect(invoked, [AppCommand.copyPaths]);

      // Exercise the actual platform channel's id, not just the callback.
      Map? findEntry(Object? data, String label) {
        if (data is Map) {
          if (data['label'] == label) return data;
          for (final value in data.values) {
            final found = findEntry(value, label);
            if (found != null) return found;
          }
        } else if (data is Iterable) {
          for (final value in data) {
            final found = findEntry(value, label);
            if (found != null) return found;
          }
        }
        return null;
      }

      final entry = findEntry(serialized, en.cmdNewTab)!;
      final reply = Completer<void>();
      binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.menu.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('Menu.selectedCallback', entry['id']),
        ),
        (_) => reply.complete(),
      );
      await reply.future;
      expect(invoked, [AppCommand.copyPaths, AppCommand.newTab]);
      unawaited(
        showDialog<void>(
          context: panel.context!,
          builder: (_) =>
              const AlertDialog(content: TextField(autofocus: true)),
        ),
      );
      await tester.pumpAndSettle();
      expect(item(tester, en.cmdNewTab).onSelected, isNull);
      copy.onSelected!(); // A previously built menu must not reach a stale panel.
      expect(invoked, hasLength(2));
    },
    variant: mac,
  );

  testWidgets('Edit operates on the text field, including cut and paste', (
    tester,
  ) async {
    String? clipboard;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            clipboard = (call.arguments as Map)['text'] as String;
          case 'Clipboard.getData':
            return {'text': clipboard};
          case 'Clipboard.hasStrings':
            return {'value': clipboard?.isNotEmpty ?? false};
        }
        return null;
      },
    );
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pump(tester);
    final copyBeforeFocus = item(tester, en.cmdCopyPaths).onSelected!;
    await tester.tap(find.byType(EditableText));
    await tester.pumpAndSettle();
    item(tester, en.cmdSelectAll).onSelected!();
    expect(text.selection, const TextSelection(baseOffset: 0, extentOffset: 5));
    copyBeforeFocus();
    await tester.pump();
    expect(clipboard, 'hello');
    expect(invoked, isEmpty);
    item(tester, 'Cut').onSelected!();
    await tester.pump();
    expect(text.text, isEmpty);
    expect(clipboard, 'hello');
    item(tester, en.cmdPasteItems).onSelected!();
    await tester.pumpAndSettle();
    expect(text.text, 'hello');
    expect(invoked, isEmpty);
    expect(
      item(tester, en.cmdNewTab).shortcut,
      isNull,
      reason: 'inner editing shortcuts must win',
    );
    panel.requestFocus();
    await tester.pumpAndSettle();
    expect(item(tester, en.cmdNewTab).shortcut, isNotNull);
    expect(item(tester, 'Cut').onSelected, isNull);
  }, variant: mac);

  testWidgets(
    'terminal clipboard commands win and shell keys stay in Flutter',
    (tester) async {
      await pump(tester);
      terminal.requestFocus();
      await tester.pumpAndSettle();
      item(tester, en.cmdTerminalCopy).onSelected!();
      item(tester, en.cmdTerminalPaste).onSelected!();
      item(tester, en.cmdTerminalSelectAll).onSelected!();
      expect(invoked, [
        AppCommand.terminalCopy,
        AppCommand.terminalPaste,
        AppCommand.terminalSelectAll,
      ]);
      expect(
        item(tester, en.cmdCopyTo).shortcut,
        isNull,
        reason: 'F5 belongs to the shell',
      );
      expect(
        item(tester, en.cmdNewTab).shortcut,
        isNotNull,
        reason: 'Command chords still reach the window',
      );
    },
    variant: mac,
  );

  testWidgets(
    'labels, overrides, sequences and unavailable commands follow the shared map',
    (tester) async {
      final map =
          ShortcutMap.forUser(
                TargetPlatform.macOS,
                unavailable: {AppCommand.quickLook, AppCommand.editTags},
              )
              .rebind(AppCommand.newTab, [
                const Chord(LogicalKeyboardKey.keyN, primary: true, alt: true),
              ])
              .rebind(AppCommand.nextTab, [
                const Chord(
                  LogicalKeyboardKey.keyT,
                  prefix: LogicalKeyboardKey.keyG,
                ),
              ])
              .rebind(AppCommand.commandPalette, []);
      const locale = Locale('ru');
      final ru = lookupFerryxLocalizations(locale);
      await pump(tester, map: map, locale: locale);
      final shortcut = item(tester, ru.cmdNewTab).shortcut! as SingleActivator;
      expect(shortcut.trigger, LogicalKeyboardKey.keyN);
      expect(shortcut.meta && shortcut.alt, isTrue);
      expect(item(tester, ru.cmdNextTab).shortcut, isNull);
      expect(item(tester, ru.cmdCommandPalette).shortcut, isNull);
      expect(item(tester, ru.cmdCommandPalette).onSelected, isNotNull);
      expect(
        items(tester).map((item) => item.label),
        isNot(contains(ru.cmdQuickLook)),
      );
      expect(
        items(tester).map((item) => item.label),
        isNot(contains(ru.cmdEditTags)),
      );
    },
    variant: mac,
  );

  testWidgets(
    'other desktops keep the child without installing a native menu',
    (tester) async {
      await pump(tester, platform: TargetPlatform.linux);
      expect(find.byType(PlatformMenuBar), findsNothing);
      expect(find.text('panel'), findsOneWidget);
    },
  );
}
