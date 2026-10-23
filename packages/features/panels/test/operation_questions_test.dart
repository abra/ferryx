import 'package:domain_models/domain_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart' hide Answer;

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
}
