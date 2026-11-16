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
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';
import 'package:sync_feature/sync_feature.dart';

class _Service extends Mock implements FolderSyncService {}

const _side = SideInfo(size: 3, modifiedMs: 1000);

CompareRow row(String rel, CompareState state) => CompareRow(
  leftRel: rel,
  rightRel: rel,
  state: state,
  left: state == CompareState.rightOnly ? null : _side,
  right: state == CompareState.leftOnly ? null : _side,
);

void main() {
  late _Service service;
  late StreamController<CompareUpdate> updates;
  late SyncCubit cubit;
  final en = lookupFerryxLocalizations(const Locale('en'));

  setUpAll(() {
    registerFallbackValue(const FolderCompareRequest(left: '', right: ''));
    registerFallbackValue(
      const SyncPlan(left: '', right: '', recursive: true, items: []),
    );
  });

  setUp(() {
    service = _Service();
    updates = StreamController<CompareUpdate>.broadcast();
    when(() => service.updates).thenAnswer((_) => updates.stream);
    when(() => service.compare(any())).thenAnswer((_) async => 1);
    when(() => service.cancel(any())).thenAnswer((_) async {});
    when(() => service.synchronize(any())).thenAnswer((_) async => 9);
  });

  tearDown(() => updates.close());

  Future<void> pump(
    WidgetTester tester, {
    double textScale = 1,
    Locale locale = const Locale('en'),
    ShortcutMap? shortcutMap,
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Made in the test's own zone, so its updates reach the widgets as the
    // test pumps.
    cubit = SyncCubit(service: service, options: const CompareOptions());
    addTearDown(cubit.close);
    const platform = TargetPlatform.macOS;
    final map = shortcutMap ?? ShortcutMap.defaults(platform);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        locale: locale,
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(1280, 900),
            textScaler: TextScaler.linear(textScale),
          ),
          child: CommandShortcuts(
            shortcuts: map.toShortcuts(
              platform,
              scopes: const {CommandScope.global},
            ),
            child: Scaffold(
              body: BlocProvider.value(
                value: cubit,
                child: SyncDialog(
                  left: '/left',
                  right: '/right',
                  preserveAttributes: true,
                  verify: false,
                  shortcutMap: map,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> compareWith(WidgetTester tester, List<CompareRow> rows) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    updates.add(CompareUpdate(taskId: 1, rows: rows, done: true));
    await tester.pumpAndSettle();
  }

  testWidgets('Return compares; the rows and the plan show', (tester) async {
    await pump(tester);
    expect(find.text(en.syncStartHint), findsOneWidget);
    await compareWith(tester, [
      row('alone.txt', CompareState.leftOnly),
      row('theirs.txt', CompareState.rightOnly),
      row('same.txt', CompareState.equal),
    ]);
    verify(() => service.compare(any())).called(1);
    expect(find.text('alone.txt'), findsOneWidget);
    expect(find.text('theirs.txt'), findsOneWidget);
    // Identical rows are filtered out by default.
    expect(find.text('same.txt'), findsNothing);
    expect(
      find.textContaining(en.syncToRight(en.count(1))),
      findsOneWidget,
    );
  });

  testWidgets('the keys walk the table and change the actions', (
    tester,
  ) async {
    await pump(tester);
    await compareWith(tester, [
      row('a.txt', CompareState.leftNewer),
      row('b.txt', CompareState.rightNewer),
    ]);
    // The table has the focus after Compare; ↓ picks the first row.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(cubit.state.actionOf(0), RowAction.copyToRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(cubit.state.actionOf(0), RowAction.copyToLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(cubit.state.actionOf(0), RowAction.skip);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(cubit.state.actionOf(0), RowAction.skip);

    // ⇧↓ takes the second row along; → sends both right.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(cubit.state.actionOf(0), RowAction.copyToRight);
    expect(cubit.state.actionOf(1), RowAction.copyToRight);
  });

  testWidgets('row guidance offers only copy directions the row supports', (
    tester,
  ) async {
    await pump(tester);
    await compareWith(tester, [row('only-left.txt', CompareState.leftOnly)]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final hints = tester.widget<AppKeyHints>(find.byType(AppKeyHints)).hints;
    expect(hints.map((hint) => hint.label), contains(en.hintChangeAction));
    expect(hints.map((hint) => hint.label), contains(en.syncActionCopyRight));
    expect(
      hints.map((hint) => hint.label),
      isNot(contains(en.syncActionCopyLeft)),
    );
    expect(
      hints.map((hint) => hint.label),
      isNot(contains(en.syncSynchronize)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(cubit.state.actionOf(0), RowAction.copyToRight);
    verifyNever(() => service.synchronize(any()));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'visible Actions offers a complete plan menu without a context binding',
    (
      tester,
    ) async {
      var map = ShortcutMap.defaults(TargetPlatform.macOS);
      for (final command in [
        AppCommand.contextMenu,
        AppCommand.selectAll,
        AppCommand.deselectAll,
      ]) {
        map = map.rebind(command, []);
      }
      await pump(tester, shortcutMap: map);
      final actions = find.widgetWithText(OutlinedButton, en.contextActions);
      expect(tester.widget<OutlinedButton>(actions).onPressed, isNull);
      await compareWith(tester, [
        row('left.txt', CompareState.leftOnly),
        row('right.txt', CompareState.rightOnly),
      ]);
      cubit.setOptions(
        cubit.state.options.copyWith(
          direction: SyncDirection.leftToRight,
          deleteMissing: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final rows = tester
          .widget<AppRowList>(find.byType(AppRowList))
          .controller;
      expect(rows.targets, [1]);
      await tester.tap(actions);
      await tester.pumpAndSettle();
      for (final label in [
        en.syncActionCopyRight,
        en.syncActionCopyLeft,
        en.syncActionDeleteLeft,
        en.syncActionDeleteRight,
        en.syncActionSkip,
        en.syncActionDefault,
        en.cmdSelectAll,
        en.cmdDeselectAll,
      ]) {
        expect(find.widgetWithText(AppMenuItem, label), findsOneWidget);
      }
      expect(
        tester
            .widget<AppMenuItem>(
              find.widgetWithText(AppMenuItem, en.syncActionCopyRight),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<AppMenuItem>(
              find.widgetWithText(AppMenuItem, en.syncActionDeleteRight),
            )
            .enabled,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(cubit.state.actionOf(1), RowAction.deleteRight);
      await tester.tap(actions);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppMenuItem, en.syncActionSkip));
      await tester.pumpAndSettle();
      expect(cubit.state.actionOf(1), RowAction.skip);
      await tester.tap(actions);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppMenuItem, en.syncActionDefault));
      await tester.pumpAndSettle();
      expect(cubit.state.actionOf(1), RowAction.deleteRight);
      await tester.tap(actions);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppMenuItem, en.cmdSelectAll));
      await tester.pumpAndSettle();
      expect(rows.selected, {0, 1});
      await tester.tap(actions);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppMenuItem, en.cmdDeselectAll));
      await tester.pumpAndSettle();
      expect(rows.selected, isEmpty);
      verifyNever(() => service.synchronize(any()));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a click on the action walks it', (tester) async {
    await pump(tester);
    await compareWith(tester, [row('a.txt', CompareState.different)]);
    expect(cubit.state.actionOf(0), RowAction.skip);
    await tester.tap(find.byIcon(AppIcons.notEqual));
    await tester.pump();
    expect(cubit.state.actionOf(0), RowAction.copyToRight);
  });

  testWidgets('Synchronize asks first, then runs the plan', (tester) async {
    await pump(tester);
    await compareWith(tester, [row('a.txt', CompareState.leftOnly)]);
    await tester.tap(find.text(en.syncSynchronize));
    await tester.pumpAndSettle();
    expect(find.text(en.syncConfirmTitle), findsOneWidget);
    await tester.tap(find.text(en.syncSynchronizeNow));
    await tester.pumpAndSettle();
    final plan =
        verify(() => service.synchronize(captureAny())).captured.single
            as SyncPlan;
    expect(plan.items.single.action, SyncAction.copyToRight);
    expect(plan.preserveAttributes, isTrue);
  });

  testWidgets('long Russian labels and large text wrap, never overflow', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    await pump(tester, textScale: 1.6, locale: const Locale('ru'));
    await compareWith(tester, [row('a.txt', CompareState.leftOnly)]);
    expect(tester.takeException(), isNull);
  });
}
