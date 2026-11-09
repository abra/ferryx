import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:panels_feature/src/workspace/workspace_preview_cubit.dart';

void main() {
  const a = Location.native('/a.epub');
  const b = Location.native('/b.pdf');
  const c = Location.native('/c.cbz');

  testWidgets('coalesces cursor moves and ignores duplicate file updates', (
    tester,
  ) async {
    final changes = StreamController<Location?>.broadcast(sync: true);
    final cubit = WorkspacePreviewCubit();
    final emitted = <WorkspacePreviewState>[];
    final subscription = cubit.stream.listen(emitted.add);
    cubit.show(
      source: PanelSide.left,
      location: a,
      changes: changes.stream,
      fullWindow: false,
    );
    changes.add(b);
    await tester.pump(const Duration(milliseconds: 100));
    changes.add(c);
    await tester.pump(const Duration(milliseconds: 100));
    changes.add(c); // Selection/metadata changes must not restart the delay.
    expect(cubit.state.location, a);
    await tester.pump(const Duration(milliseconds: 50));
    expect(cubit.state.location, c);
    expect(emitted.map((state) => state.location), [a, c]);

    changes.add(b);
    changes.add(c); // Returning to the displayed file cancels pending b.
    await tester.pump(const Duration(seconds: 1));
    expect(emitted.map((state) => state.location), [a, c]);
    unawaited(cubit.close());
    unawaited(subscription.cancel());
    unawaited(changes.close());
  });

  testWidgets('folders clear the file and placement preserves pending follow', (
    tester,
  ) async {
    final changes = StreamController<Location?>.broadcast(sync: true);
    final cubit = WorkspacePreviewCubit();
    cubit.show(
      source: PanelSide.right,
      location: a,
      changes: changes.stream,
      fullWindow: false,
    );
    changes.add(null);
    cubit.setFullWindow(true);
    await tester.pump(const Duration(milliseconds: 150));
    expect(cubit.state.location, isNull);
    expect(cubit.state.shown, isTrue);
    expect(cubit.state.source, PanelSide.right);
    expect(cubit.state.fullWindow, isTrue);
    unawaited(cubit.close());
    unawaited(changes.close());
  });

  testWidgets('replacement, hide and dispose cancel subscriptions and timers', (
    tester,
  ) async {
    final left = StreamController<Location?>.broadcast(sync: true);
    final right = StreamController<Location?>.broadcast(sync: true);
    final cubit = WorkspacePreviewCubit();
    cubit.show(
      source: PanelSide.left,
      location: a,
      changes: left.stream,
      fullWindow: false,
    );
    left.add(b);
    cubit.show(
      source: PanelSide.right,
      location: c,
      changes: right.stream,
      fullWindow: true,
    );
    expect(left.hasListener, isFalse);
    left.add(null);
    await tester.pump(const Duration(seconds: 1));
    expect(cubit.state.location, c);
    right.add(b);
    cubit.hide();
    expect(right.hasListener, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(cubit.state.shown, isFalse);
    cubit.show(
      source: PanelSide.left,
      location: a,
      changes: left.stream,
      fullWindow: false,
    );
    left.add(b);
    unawaited(cubit.close());
    expect(left.hasListener, isFalse);
    await tester.pump(const Duration(seconds: 1));
    unawaited(left.close());
    unawaited(right.close());
  });
}
