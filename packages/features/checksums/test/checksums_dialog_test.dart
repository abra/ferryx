import 'dart:async';

import 'package:checksums_feature/checksums_feature.dart';
import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operations_service/operations_service.dart';
import 'package:shortcuts/shortcuts.dart';

class _Service extends Mock implements ChecksumService {}

const _hash =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

void main() {
  late _Service service;
  late StreamController<ChecksumUpdate> updates;
  final en = lookupFerryxLocalizations(const Locale('en'));

  setUpAll(() {
    registerFallbackValue(
      const ChecksumRequest(
        paths: [],
        base: '',
        algorithm: ChecksumAlgorithm.md5,
      ),
    );
  });

  setUp(() {
    service = _Service();
    updates = StreamController<ChecksumUpdate>.broadcast();
    when(() => service.updates).thenAnswer((_) => updates.stream);
    when(() => service.start(any())).thenAnswer((_) async => 1);
    when(() => service.cancel(any())).thenAnswer((_) async {});
  });

  tearDown(() => updates.close());

  Future<ChecksumsCubit> pump(
    WidgetTester tester, {
    ShortcutMap? shortcutMap,
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cubit = ChecksumsCubit(
      service: service,
      paths: const ['/home/a.iso', '/home/b.iso'],
      base: '/home',
    );
    addTearDown(cubit.close);
    const platform = TargetPlatform.macOS;
    final map = shortcutMap ?? ShortcutMap.defaults(platform);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: CommandShortcuts(
          shortcuts: map.toShortcuts(
            platform,
            scopes: const {CommandScope.global},
          ),
          child: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: ChecksumsDialog(shortcutMap: map),
            ),
          ),
        ),
      ),
    );
    await cubit.start();
    updates.add(
      const ChecksumUpdate(
        taskId: 1,
        files: [
          ChecksumFile(index: 0, name: 'a.iso', path: '/home/a.iso', size: 3),
          ChecksumFile(index: 1, name: 'b.iso', path: '/home/b.iso', size: 3),
        ],
        outcomes: [
          ChecksumOutcome(index: 0, status: ChecksumStatus.ok, hash: _hash),
          ChecksumOutcome(index: 1, status: ChecksumStatus.ok, hash: 'ffff'),
        ],
        filesTotal: 2,
        filesDone: 2,
        done: true,
      ),
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  testWidgets('shows the hashes; a pasted hash names its file', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(_hash), findsOneWidget);
    expect(find.text(en.checksumFiles(2)), findsOneWidget);
    await tester.enterText(find.byType(EditableText), _hash.toUpperCase());
    await tester.pumpAndSettle();
    expect(find.text(en.checksumMatch('a.iso')), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'deadbeefdeadbeef');
    await tester.pumpAndSettle();
    expect(find.text(en.checksumNoMatch), findsOneWidget);
  });

  testWidgets('the algorithm switch starts over', (tester) async {
    final cubit = await pump(tester);
    await tester.tap(find.text('MD5'));
    // Running again: the spinner turns, so no settling.
    await tester.pump();
    expect(cubit.state.algorithm, ChecksumAlgorithm.md5);
    expect(cubit.state.running, isTrue);
    verify(() => service.start(any())).called(2);
  });

  testWidgets('⌘C copies the selected rows\' hashes', (tester) async {
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
    await pump(tester);
    await tester.tap(find.text('a.iso'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(copied, [_hash]);
  });

  testWidgets('hash copy guidance follows the actual rebind and row focus', (
    tester,
  ) async {
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
    const chord = Chord(
      LogicalKeyboardKey.keyH,
      primary: true,
      control: true,
      shift: true,
    );
    final map = ShortcutMap.defaults(TargetPlatform.macOS)
        .rebind(AppCommand.copyPaths, [chord])
        .rebind(AppCommand.contextMenu, []);
    await pump(tester, shortcutMap: map);
    await tester.tap(find.text('a.iso'));
    await tester.pumpAndSettle();
    final hints = tester.widget<AppKeyHints>(find.byType(AppKeyHints)).hints;
    expect(
      hints.any(
        (hint) =>
            hint.label == en.checksumCopyHash &&
            hint.keys.single == chord.label(TargetPlatform.macOS),
      ),
      isTrue,
    );
    expect(hints.map((hint) => hint.label), isNot(contains(en.cmdContextMenu)));

    for (final key in [
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft,
    ]) {
      await tester.sendKeyDownEvent(key);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    for (final key in [
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      await tester.sendKeyUpEvent(key);
    }
    await tester.pumpAndSettle();
    expect(copied, [_hash]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'visible Actions retains complete row commands when their keys are unbound',
    (
      tester,
    ) async {
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
      var map = ShortcutMap.defaults(TargetPlatform.macOS);
      for (final command in [
        AppCommand.contextMenu,
        AppCommand.copyPaths,
        AppCommand.selectAll,
        AppCommand.deselectAll,
      ]) {
        map = map.rebind(command, []);
      }
      await pump(tester, shortcutMap: map);
      final actions = find.widgetWithText(OutlinedButton, en.contextActions);
      expect(tester.widget<OutlinedButton>(actions).onPressed, isNull);
      await tester.tap(find.text('a.iso'));
      await tester.pumpAndSettle();
      final rows = tester
          .widget<AppRowList>(find.byType(AppRowList))
          .controller;
      Focus.of(
        tester.element(
          find.descendant(
            of: actions,
            matching: find.text(en.contextActions),
          ),
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      for (final label in [
        en.checksumCopyHash,
        en.checksumCopyLine,
        en.cmdSelectAll,
        en.cmdDeselectAll,
      ]) {
        expect(find.widgetWithText(AppMenuItem, label), findsOneWidget);
      }
      expect(
        tester
            .widget<AppMenuItem>(
              find.widgetWithText(AppMenuItem, en.checksumCopyHash),
            )
            .shortcut,
        isNull,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(copied, isEmpty);
      expect(rows.selected, {0});
      await tester.tap(actions);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppMenuItem, en.cmdSelectAll));
      await tester.pumpAndSettle();
      expect(rows.selected, {0, 1});
      await tester.tap(actions);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppMenuItem, en.checksumCopyLine));
      await tester.pumpAndSettle();
      expect(copied, ['$_hash  a.iso\nffff  b.iso']);
      await tester.tap(actions);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppMenuItem, en.cmdDeselectAll));
      await tester.pumpAndSettle();
      expect(rows.selected, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
