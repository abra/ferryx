import 'package:domain_models/domain_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart' hide Answer;
import 'package:panels_feature/panels_feature.dart';
import 'package:panels_feature/src/operations/operations_cards.dart';

import 'support/workspace_harness.dart';

/// The core numbers each operation's questions from 1: the window asks
/// every operation's question, not only the first operation's.
void main() {
  setUpAll(() {
    WorkspaceHarness.registerFallbacks();
    registerFallbackValue(Answer.skip);
  });

  late WorkspaceHarness h;
  late List<(int, int, Answer)> answered;

  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp();
    answered = [];
    when(() => h.operations.answer(any(), any(), any())).thenAnswer((call) {
      answered.add((
        call.positionalArguments[0] as int,
        call.positionalArguments[1] as int,
        call.positionalArguments[2] as Answer,
      ));
      return Future<void>.value();
    });
  });

  tearDown(() => h.tearDown());

  OperationProgress waiting(int operation) => OperationProgress(
    id: operation,
    kind: OpKind.copy,
    state: OpState.waiting,
    question: const OperationQuestion(
      id: 1,
      kind: QuestionKind.conflict,
      message: '“notes.txt” already exists',
      answers: [Answer.overwrite, Answer.skip, Answer.keepBoth, Answer.abort],
    ),
  );

  testWidgets('a second operation\'s question 1 is asked too', (tester) async {
    await h.pump(tester);
    h.progress.add(waiting(1));
    await tester.pumpAndSettle();
    // Esc stops the operation: the dialog answers abort.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(answered, [(1, 1, Answer.abort)]);

    h.progress.add(waiting(2));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(answered, [(1, 1, Answer.abort), (2, 1, Answer.abort)]);

    // The same question reported again is not asked twice.
    h.progress.add(waiting(2));
    await tester.pumpAndSettle();
    expect(answered, hasLength(2));
  });

  testWidgets('progress updates cards without rebuilding either panel', (
    tester,
  ) async {
    await h.pump(tester);
    final before = tester
        .widgetList<PanelView>(find.byType(PanelView))
        .toList();
    for (final bytes in [10, 20, 30]) {
      h.progress.add(
        OperationProgress(
          id: 1,
          kind: OpKind.copy,
          state: OpState.running,
          bytesDone: bytes,
          bytesTotal: 100,
        ),
      );
      await tester.pump();
      await tester.pump();
      final after = tester
          .widgetList<PanelView>(find.byType(PanelView))
          .toList();
      expect(after, hasLength(2));
      for (var i = 0; i < after.length; i++) {
        expect(after[i], same(before[i]));
      }
      final cards = tester.widget<OperationsCards>(
        find.byType(OperationsCards),
      );
      expect(cards.operations.single.bytesDone, bytes);
    }
  });
}
