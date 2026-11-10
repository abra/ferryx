import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:panels_feature/src/workspace/pending_deletions_controller.dart';

void main() {
  late List<PendingDeletion> executed;
  late PendingDeletionsController controller;

  setUp(() {
    executed = [];
    controller = PendingDeletionsController(
      onExecute: (deletion) async => executed.add(deletion),
    );
  });
  tearDown(() => controller.dispose());

  bool schedule({
    PanelSide side = PanelSide.left,
    OpKind kind = OpKind.trash,
    List<String> paths = const ['/files/a.txt', '/files/b.txt'],
    Location location = const Location.native('/files'),
  }) => controller.schedule(
    side: side,
    location: location,
    kind: kind,
    paths: paths,
  );

  testWidgets('nothing executes before the deadline, then executes once', (
    tester,
  ) async {
    expect(schedule(), isTrue);
    final pending = controller.pendingFor(PanelSide.left)!;
    expect(pending.delay, const Duration(seconds: 5));
    expect(executed, isEmpty);
    await tester.pump(const Duration(milliseconds: 4999));
    expect(executed, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(executed, [pending]);
    expect(controller.pendingFor(PanelSide.left), isNull);
    expect(controller.cancel(PanelSide.left), isFalse);
    await tester.pump(const Duration(seconds: 10));
    expect(executed, hasLength(1));
  });

  testWidgets('Cancel just before the deadline prevents the entire batch', (
    tester,
  ) async {
    schedule();
    await tester.pump(const Duration(milliseconds: 4999));
    expect(controller.cancel(PanelSide.left), isTrue);
    expect(controller.cancel(PanelSide.left), isFalse);
    await tester.pump(const Duration(seconds: 10));
    expect(executed, isEmpty);
  });

  testWidgets('captures immutable paths, origin and server before waiting', (
    tester,
  ) async {
    final paths = ['/files/a.txt'];
    const source = Location.remote(server: 'sftp://host', path: '/files');
    schedule(
      kind: OpKind.delete,
      paths: paths,
      location: source,
      side: PanelSide.right,
    );
    paths[0] = '/files/other.txt';
    final pending = controller.pendingFor(PanelSide.right)!;
    expect(() => pending.request.sources.clear(), throwsUnsupportedError);
    await tester.pump(const Duration(seconds: 5));
    expect(executed.single.location, source);
    expect(executed.single.side, PanelSide.right);
    expect(executed.single.request.sources, ['/files/a.txt']);
    expect(executed.single.request.sourceServer, 'sftp://host');
    expect(executed.single.request.kind, OpKind.delete);
  });

  testWidgets('repeated requests neither replace nor extend a pending batch', (
    tester,
  ) async {
    schedule();
    await tester.pump(const Duration(seconds: 2));
    expect(schedule(paths: ['/files/other.txt']), isFalse);
    await tester.pump(const Duration(seconds: 3));
    expect(executed.single.request.sources, ['/files/a.txt', '/files/b.txt']);
  });

  testWidgets('panels are independent and Esc prefers the current panel', (
    tester,
  ) async {
    schedule();
    schedule(side: PanelSide.right, paths: ['/right.txt']);
    expect(controller.cancelFrom(PanelSide.right), isTrue);
    expect(controller.pendingFor(PanelSide.left), isNotNull);
    expect(controller.pendingFor(PanelSide.right), isNull);
    expect(controller.cancelFrom(PanelSide.right), isTrue);
    expect(controller.cancelFrom(PanelSide.right), isFalse);
    await tester.pump(const Duration(seconds: 6));
    expect(executed, isEmpty);
  });

  testWidgets('a cancelled callback cannot execute a replacement batch', (
    tester,
  ) async {
    schedule();
    await tester.pump(const Duration(seconds: 2));
    controller.cancel(PanelSide.left);
    schedule(paths: ['/replacement.txt']);
    await tester.pump(const Duration(seconds: 3));
    expect(executed, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    expect(executed.single.request.sources, ['/replacement.txt']);
  });

  testWidgets('closing the workspace drops pending work without executing', (
    tester,
  ) async {
    schedule();
    controller.dispose();
    controller = PendingDeletionsController(onExecute: (deletion) async {});
    await tester.pump(const Duration(seconds: 10));
    expect(executed, isEmpty);
  });
}
