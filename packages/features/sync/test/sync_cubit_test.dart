import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operations_service/operations_service.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:sync_feature/sync_feature.dart';

class _Service extends Mock implements FolderSyncService {}

const _a = SideInfo(size: 5, modifiedMs: 2000);
const _b = SideInfo(size: 5, modifiedMs: 1000);

CompareRow row(String rel, CompareState state) => CompareRow(
  leftRel: rel,
  rightRel: rel,
  state: state,
  left: state == CompareState.rightOnly ? null : _a,
  right: state == CompareState.leftOnly ? null : _b,
);

void main() {
  late _Service service;
  late StreamController<CompareUpdate> updates;
  late List<CompareOptions> saved;

  setUpAll(() {
    registerFallbackValue(const FolderCompareRequest(left: '', right: ''));
    registerFallbackValue(
      const SyncPlan(left: '', right: '', recursive: true, items: []),
    );
  });

  setUp(() {
    service = _Service();
    updates = StreamController<CompareUpdate>.broadcast();
    saved = [];
    when(() => service.updates).thenAnswer((_) => updates.stream);
    when(() => service.compare(any())).thenAnswer((_) async => 7);
    when(() => service.cancel(any())).thenAnswer((_) async {});
    when(() => service.synchronize(any())).thenAnswer((_) async => 42);
  });

  tearDown(() => updates.close());

  SyncCubit cubit({CompareOptions options = const CompareOptions()}) =>
      SyncCubit(service: service, options: options, onOptions: saved.add);

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('compares with the options and gathers rows as they come', () async {
    final sync = cubit(options: const CompareOptions(fatTime: true));
    await sync.compare(left: '/l', right: '/r', mask: ' *.txt ');
    final request =
        verify(() => service.compare(captureAny())).captured.single
            as FolderCompareRequest;
    expect(request.left, '/l');
    expect(request.nameMask, '*.txt');
    expect(request.timeTolerance, const Duration(seconds: 2));
    expect(sync.state.running, isTrue);
    expect(saved, hasLength(1));

    updates.add(
      CompareUpdate(
        taskId: 7,
        rows: [
          row('new.txt', CompareState.leftOnly),
          row('same.txt', CompareState.equal),
        ],
      ),
    );
    await flush();
    expect(sync.state.rowCount, 2);
    // Identical rows are hidden by default.
    expect(sync.state.visibleCount, 1);
    expect(sync.state.rowAt(0).leftRel, 'new.txt');
    expect(sync.state.actionOf(0), RowAction.copyToRight);
    expect(sync.state.groups[RowGroup.identical], 1);
    expect(sync.state.summary.toRight, 1);

    // Another task's update is not this one's.
    updates.add(
      CompareUpdate(taskId: 99, rows: [row('x', CompareState.leftOnly)]),
    );
    await flush();
    expect(sync.state.rowCount, 2);

    updates.add(
      CompareUpdate(
        taskId: 7,
        rows: [row('old.txt', CompareState.rightNewer)],
        errors: const [CompareError(path: '/l/locked', message: 'denied')],
        done: true,
      ),
    );
    await flush();
    expect(sync.state.phase, SyncPhase.compared);
    expect(sync.state.visibleCount, 2);
    expect(sync.state.unreadable, 1);
    expect(sync.state.summary.toLeft, 1);
    await sync.close();
  });

  blocTest<SyncCubit, SyncState>(
    'refuses the same folder or a missing one before asking',
    build: cubit,
    act: (sync) async {
      await sync.compare(left: '/same/', right: '/same');
      await sync.compare(left: '', right: '/r');
    },
    expect: () => [
      isA<SyncState>()
          .having((s) => s.problem, 'problem', SyncProblem.sameFolder)
          .having((s) => s.phase, 'phase', SyncPhase.idle),
      isA<SyncState>().having(
        (s) => s.problem,
        'problem',
        SyncProblem.missingFolder,
      ),
    ],
    verify: (_) => verifyNever(() => service.compare(any())),
  );

  test('filters, actions by hand, Space and the suggested action', () async {
    final sync = cubit();
    await sync.compare(left: '/l', right: '/r');
    updates.add(
      CompareUpdate(
        taskId: 7,
        rows: [
          row('a', CompareState.leftOnly),
          row('b', CompareState.different),
          row('c', CompareState.equal),
        ],
        done: true,
      ),
    );
    await flush();
    expect(sync.state.visibleCount, 2);

    sync.setOptions(sync.state.options.copyWith(showIdentical: true));
    expect(sync.state.visibleCount, 3);
    expect(saved.last.showIdentical, isTrue);

    // `b` (shown second) to the left by hand, then walked by Space.
    sync.setAction([1], RowAction.copyToLeft);
    expect(sync.state.actionOf(1), RowAction.copyToLeft);
    sync.cycleAction([1]);
    expect(sync.state.actionOf(1), RowAction.skip);
    // Several rows follow the first one's next action, where they can.
    sync.cycleAction([1, 0]);
    expect(sync.state.actionOf(1), RowAction.copyToRight);
    expect(sync.state.actionOf(0), RowAction.copyToRight);
    // A left-only row cannot be copied to the left.
    sync.setAction([0], RowAction.copyToLeft);
    expect(sync.state.actionOf(0), RowAction.copyToRight);
    sync.resetActions([1]);
    expect(sync.state.actionOf(1), RowAction.skip);

    // One way with deletions: actions are set anew.
    sync.setOptions(
      sync.state.options.copyWith(
        direction: SyncDirection.rightToLeft,
        deleteMissing: true,
      ),
    );
    expect(sync.state.actionOf(0), RowAction.deleteLeft);
    expect(sync.state.actionOf(1), RowAction.copyToLeft);
    expect(sync.state.summary.toDelete, 1);
    await sync.close();
  });

  test('the plan holds the shown rows with an action', () async {
    final sync = cubit();
    await sync.compare(left: '/l', right: '/r');
    updates.add(
      CompareUpdate(
        taskId: 7,
        rows: [
          row('a', CompareState.leftOnly),
          row('b', CompareState.rightNewer),
          row('c', CompareState.different),
        ],
        done: true,
      ),
    );
    await flush();
    // `b` is hidden: it is not synchronized whatever its action.
    sync.setOptions(sync.state.options.copyWith(showNewer: false));
    final plan = sync.plan(preserveAttributes: true, verify: true);
    expect(plan.items.map((i) => (i.row.leftRel, i.action)), [
      ('a', SyncAction.copyToRight),
    ]);
    expect(plan.left, '/l');
    expect(plan.recursive, isTrue);
    expect(await sync.synchronize(preserveAttributes: true, verify: false), 42);
    await sync.close();
  });

  test('stopping keeps the rows and cancels the task; closing too', () async {
    final sync = cubit();
    await sync.compare(left: '/l', right: '/r');
    updates.add(
      CompareUpdate(taskId: 7, rows: [row('a', CompareState.leftOnly)]),
    );
    await flush();
    await sync.stop();
    verify(() => service.cancel(7)).called(1);
    expect(sync.state.phase, SyncPhase.compared);
    expect(sync.state.rowCount, 1);
    await sync.compare(left: '/l', right: '/r');
    await sync.close();
    verify(() => service.cancel(7)).called(1);
  });
}
