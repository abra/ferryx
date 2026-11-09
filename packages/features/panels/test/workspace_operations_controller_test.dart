import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart' hide Answer;
import 'package:operations_service/operations_service.dart';
import 'package:panels_feature/src/workspace/workspace_operations_controller.dart';

class _Operations extends Mock implements OperationsService {}

OperationProgress _report(
  int id, {
  OpState state = OpState.running,
  OpKind kind = OpKind.copy,
  List<OperationError> errors = const [],
  OperationQuestion? question,
  int bytes = 0,
}) => OperationProgress(
  id: id,
  kind: kind,
  state: state,
  errors: errors,
  question: question,
  bytesDone: bytes,
);

OperationQuestion _question(int id) => OperationQuestion(
  id: id,
  kind: QuestionKind.conflict,
  message: 'Already exists',
  answers: const [Answer.skip, Answer.abort],
);

void main() {
  late _Operations service;
  late StreamController<OperationProgress> progress;
  late Map<int, OperationProgress> current;
  WorkspaceOperationsController? controller;
  late List<int> forgotten;
  late List<(int, int, Answer)> answered;
  late List<int> asked;
  late int finished;

  setUpAll(() => registerFallbackValue(Answer.skip));

  setUp(() {
    service = _Operations();
    progress = StreamController<OperationProgress>.broadcast(sync: true);
    current = {};
    forgotten = [];
    answered = [];
    asked = [];
    finished = 0;
    when(() => service.progress).thenAnswer((_) => progress.stream);
    when(() => service.current).thenAnswer((_) => current);
    when(() => service.forget(any())).thenAnswer((call) async {
      forgotten.add(call.positionalArguments[0] as int);
    });
    when(() => service.answer(any(), any(), any())).thenAnswer((call) async {
      answered.add((
        call.positionalArguments[0] as int,
        call.positionalArguments[1] as int,
        call.positionalArguments[2] as Answer,
      ));
    });
  });

  tearDown(() async {
    controller?.dispose();
    controller = null;
    await progress.close();
  });

  WorkspaceOperationsController start({
    Future<Answer?> Function(OperationQuestion)? ask,
  }) => controller = WorkspaceOperationsController(
    service: service,
    ask: (question) {
      asked.add(question.id);
      return ask?.call(question) ?? Future.value(Answer.skip);
    },
    onFinished: () => finished++,
  );

  testWidgets('restores current cards and applies the same completion rules', (
    tester,
  ) async {
    current.addAll({
      3: _report(3),
      1: _report(1, state: OpState.done),
      2: _report(2, kind: OpKind.calcSizes),
    });
    final cards = start();
    expect(cards.operations.map((p) => p.id), [1, 3]);
    expect(finished, 1);
    await tester.pump(const Duration(milliseconds: 2999));
    expect(forgotten, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(forgotten, [1]);
    expect(cards.operations.map((p) => p.id), [3]);
  });

  testWidgets(
    'success dismisses at three seconds, errors stay until dismissed',
    (tester) async {
      final cards = start();
      progress.add(_report(1, state: OpState.done));
      progress.add(_report(2, state: OpState.failed));
      progress.add(_report(3, state: OpState.doneWithErrors));
      progress.add(
        _report(
          4,
          state: OpState.done,
          errors: const [
            OperationError(path: '/file', message: 'Could not copy'),
          ],
        ),
      );
      progress.add(_report(5, kind: OpKind.calcSizes, state: OpState.done));
      expect(finished, 4);
      cards.setTitle(2, 'Undo copy');
      await tester.pump(const Duration(seconds: 3));
      expect(forgotten, [1]);
      expect(cards.operations.map((p) => p.id), [2, 3, 4]);
      cards.dismiss(2);
      expect(forgotten, [1, 2]);
      expect(cards.titles, isEmpty);
      await tester.pump(const Duration(seconds: 10));
      expect(cards.operations.map((p) => p.id), [3, 4]);
    },
  );

  testWidgets('new progress and a late undo title notify card listeners', (
    tester,
  ) async {
    final cards = start();
    var notifications = 0;
    cards.addListener(() => notifications++);
    progress.add(_report(1, bytes: 10));
    expect(cards.operations.single.bytesDone, 10);
    progress.add(_report(1, bytes: 20));
    expect(cards.operations.single.bytesDone, 20);
    cards.setTitle(1, 'Undo copy');
    expect(notifications, 3);
    expect(cards.titles, {1: 'Undo copy'});
    cards.setTitle(1, 'Undo copy');
    progress.add(_report(2, kind: OpKind.calcSizes));
    expect(notifications, 3);
  });

  testWidgets(
    'questions deduplicate by operation and question, including restore',
    (tester) async {
      current[1] = _report(1, state: OpState.waiting, question: _question(1));
      final cards = start();
      await tester.pump();
      progress.add(current[1]!);
      progress.add(_report(2, state: OpState.waiting, question: _question(1)));
      progress.add(_report(1, state: OpState.waiting, question: _question(2)));
      await tester.pump();
      expect(asked, [1, 1, 2]);
      expect(answered, [
        (1, 1, Answer.skip),
        (2, 1, Answer.skip),
        (1, 2, Answer.skip),
      ]);
      await cards.ask(1);
      expect(answered.last, (1, 2, Answer.skip));
      expect(answered, hasLength(4));
    },
  );

  testWidgets('one dialog at a time per question; dismissal answers abort', (
    tester,
  ) async {
    final answer = Completer<Answer?>();
    final cards = start(ask: (_) => answer.future);
    progress.add(_report(1, state: OpState.waiting, question: _question(1)));
    await cards.ask(1);
    expect(asked, [1]);
    answer.complete(null);
    await tester.pump();
    expect(answered, [(1, 1, Answer.abort)]);
  });

  testWidgets('a late dialog cannot answer a finished or replaced question', (
    tester,
  ) async {
    final replies = <int, Completer<Answer?>>{};
    start(
      ask: (question) => (replies[question.id] = Completer<Answer?>()).future,
    );
    progress.add(_report(1, state: OpState.waiting, question: _question(1)));
    progress.add(_report(1, state: OpState.waiting, question: _question(2)));
    replies[1]!.complete(Answer.skip);
    await tester.pump();
    expect(answered, isEmpty);
    progress.add(_report(1, state: OpState.failed));
    replies[2]!.complete(Answer.skip);
    await tester.pump();
    expect(answered, isEmpty);
  });

  testWidgets(
    'dispose cancels subscriptions and timers and ignores late answers',
    (tester) async {
      final answer = Completer<Answer?>();
      final cards = start(ask: (_) => answer.future);
      progress.add(_report(1, state: OpState.done));
      progress.add(_report(2, state: OpState.waiting, question: _question(1)));
      expect(progress.hasListener, isTrue);
      cards.dispose();
      controller = null;
      expect(progress.hasListener, isFalse);
      answer.complete(Answer.skip);
      progress.add(_report(3, state: OpState.done));
      await tester.pump(const Duration(seconds: 4));
      expect(finished, 1);
      expect(forgotten, isEmpty);
      expect(answered, isEmpty);
      expect(cards.operations, isEmpty);
    },
  );
}
