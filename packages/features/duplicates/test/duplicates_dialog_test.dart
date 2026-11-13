import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:duplicates_feature/duplicates_feature.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operations_service/operations_service.dart';
import 'package:shortcuts/shortcuts.dart';

class _Service extends Mock implements DuplicatesService {}

class _Operations extends Mock implements OperationsService {}

void main() {
  late _Service service;
  late _Operations operations;
  late StreamController<DuplicatesUpdate> updates;
  final en = lookupFerryxLocalizations(const Locale('en'));

  setUpAll(() {
    registerFallbackValue(const DuplicatesRequest(roots: []));
    registerFallbackValue(
      const OperationRequest(kind: OpKind.trash, sources: []),
    );
  });

  setUp(() {
    service = _Service();
    operations = _Operations();
    updates = StreamController<DuplicatesUpdate>.broadcast();
    when(() => service.updates).thenAnswer((_) => updates.stream);
    when(() => service.start(any())).thenAnswer((_) async => 1);
    when(() => service.cancel(any())).thenAnswer((_) async {});
    when(() => operations.start(any())).thenAnswer((_) async => 77);
  });

  tearDown(() => updates.close());

  Future<DuplicatesCubit> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cubit = DuplicatesCubit(service: service);
    addTearDown(cubit.close);
    const platform = TargetPlatform.macOS;
    final map = ShortcutMap.defaults(platform);
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
              child: DuplicatesDialog(
                root: '/home',
                other: '/backup',
                operations: operations,
                shortcutMap: map,
              ),
            ),
          ),
        ),
      ),
    );
    return cubit;
  }

  Future<void> search(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    updates.add(
      DuplicatesUpdate(
        taskId: 1,
        groups: [
          DuplicateGroup(
            size: 2048,
            files: [
              DuplicateFile(path: '/home/a.jpg', modified: DateTime(2026)),
              DuplicateFile(path: '/home/b.jpg', modified: DateTime(2025)),
            ],
          ),
        ],
        done: true,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Return searches the folder, the other one on request', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(en.dupesStartHint), findsOneWidget);
    await tester.tap(find.text(en.dupesAlsoIn('/backup')));
    await tester.pump();
    await search(tester);
    final request =
        verify(() => service.start(captureAny())).captured.single
            as DuplicatesRequest;
    expect(request.roots, ['/home', '/backup']);
    expect(request.minSize, 1);
    expect(find.text('a.jpg'), findsOneWidget);
    expect(find.textContaining(en.dupesGroups(1)), findsOneWidget);
  });

  testWidgets('Space marks; Move to Trash asks, then trashes the marked', (
    tester,
  ) async {
    final cubit = await pump(tester);
    await search(tester);
    // ↓ to the heading, ↓ to the first file, Space marks it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(cubit.state.marked, {'/home/a.jpg'});
    expect(find.textContaining(en.dupesMarked(1)), findsOneWidget);

    await tester.tap(find.text(en.cmdMoveToTrash));
    await tester.pumpAndSettle();
    expect(find.text(en.dupesTrashTitle(1)), findsOneWidget);
    await tester.tap(find.text(en.cmdMoveToTrash).last);
    await tester.pumpAndSettle();
    final request =
        verify(() => operations.start(captureAny())).captured.single
            as OperationRequest;
    expect(request.kind, OpKind.trash);
    expect(request.sources, ['/home/a.jpg']);
    // The group is down to one file: gone from the results.
    expect(cubit.state.groups, isEmpty);
  });

  testWidgets('marking every copy warns before trashing', (tester) async {
    final cubit = await pump(tester);
    await search(tester);
    cubit.toggleMarks([1, 2]);
    // The state reaches the dialog, then its frame.
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.cmdMoveToTrash));
    await tester.pumpAndSettle();
    // The warning follows the message, on a line of its own.
    expect(find.textContaining(en.dupesTrashAllCopies(1)), findsOneWidget);
    // Destructive: Return cancels.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    verifyNever(() => operations.start(any()));
  });
}
