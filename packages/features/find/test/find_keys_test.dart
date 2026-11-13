import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:find_feature/find_feature.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operations_service/operations_service.dart';

class _MockFindService extends Mock implements FindService {}

/// The search, its hits and back without the pointer: Return searches and
/// leaves the keys in the field, ↓ goes down into the hits, Return goes to
/// one, Esc leaves.
void main() {
  late _MockFindService service;
  late StreamController<FindUpdate> updates;

  setUpAll(() => registerFallbackValue(const FindRequest(root: '/')));

  setUp(() {
    service = _MockFindService();
    updates = StreamController<FindUpdate>.broadcast();
    when(() => service.updates).thenAnswer((_) => updates.stream);
    when(() => service.start(any())).thenAnswer((_) async => 7);
    when(() => service.cancel(any())).thenAnswer((_) async {});
  });

  tearDown(() => updates.close());

  testWidgets('Return searches with the keys kept in the field; ↓ takes '
      'them to the hits, Return goes to one', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Future<String?> result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        localizationsDelegates: FerryxLocalizations.localizationsDelegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => result = showFindDialog(
                context,
                root: '/home',
                find: service,
                onView: (_) async {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    EditableText nameField() => tester
        .widgetList<EditableText>(find.byType(EditableText))
        .firstWhere(
          (field) => field.focusNode.debugLabel == 'find name',
        );
    expect(nameField().focusNode.hasPrimaryFocus, isTrue);
    await tester.enterText(find.byWidget(nameField()), '*.md');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    verify(() => service.start(any())).called(1);
    expect(
      nameField().focusNode.hasPrimaryFocus,
      isTrue,
      reason: 'the dialog stays, and so do the keys',
    );
    // As the core sends them: the last hits, then the end.
    updates
      ..add(
        const FindUpdate(
          findId: 7,
          hits: [
            FindHit(path: '/home/a.md', isDir: false, size: 4),
            FindHit(path: '/home/docs/b.md', isDir: false, size: 4),
          ],
        ),
      )
      ..add(const FindUpdate(findId: 7, done: true));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(nameField().focusNode.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(await result, '/home/a.md');
  });
}
