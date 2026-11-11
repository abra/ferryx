import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:monitoring/monitoring.dart';
import 'package:panels_feature/panels_feature.dart';

import 'support/workspace_harness.dart';

class _Logs with LogObserver {
  final messages = <LogMessage>[];
  @override
  void onLog(LogMessage logMessage) => messages.add(logMessage);
}

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);
  const home = Location.native('/home/docs');
  const bad = Location.native('/home/docs/......');
  late WorkspaceHarness h;
  late PanelCubit panel;
  late _Logs logs;
  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp();
    logs = _Logs();
    panel = PanelCubit(
      side: PanelSide.left,
      files: h.files,
      operations: h.operations,
      preferences: h.preferences,
      logger: Logger(observers: [logs]),
    );
    await panel.start(null, home);
  });
  tearDown(() async {
    await panel.close();
    await h.tearDown();
  });

  for (final kind in [
    FerryxErrorKind.notFound,
    FerryxErrorKind.notADirectory,
    FerryxErrorKind.permissionDenied,
    FerryxErrorKind.invalidName,
  ]) {
    test(
      '$kind preserves the view and is logged without a stack trace',
      () async {
        panel.moveCursorTo(1);
        panel.selectWhere((row) => row.name == 'a.txt', select: true);
        panel.quickSearchType('a');
        final before = panel.state.active!;
        when(() => h.files.openListing(any(), bad, any())).thenThrow(
          FerryxException(kind, bad.path),
        );
        await panel.open(bad);
        final after = panel.state.active!;
        expect(after.location, before.location);
        expect(after.rows, same(before.rows));
        expect(after.cursor, before.cursor);
        expect(after.selected, before.selected);
        expect(after.quickSearch, before.quickSearch);
        expect(after.history, before.history);
        expect(after.historyIndex, before.historyIndex);
        expect(after.loading, isFalse);
        expect(after.error!.kind, kind);
        expect(after.failedLocation, bad);
        expect(logs.messages.single.level, LogLevel.info);
        expect(logs.messages.single.stackTrace, isNull);
        panel.dismissError();
        expect(panel.state.active!.error, isNull);
        expect(panel.state.active!.failedLocation, isNull);
        expect(panel.state.active!.selected, before.selected);
      },
    );
  }

  test(
    'Retry opens the failed target instead of refreshing the old folder',
    () async {
      await panel.open(bad);
      expect(panel.state.active!.location, home);
      h.addFolder(bad.path, ['recovered.txt']);
      await panel.retryFailedRead();
      expect(panel.state.active!.location, bad);
      expect(panel.state.active!.error, isNull);
      expect(panel.state.active!.failedLocation, isNull);
      expect(
        panel.state.active!.rows.any((row) => row.name == 'recovered.txt'),
        isTrue,
      );
    },
  );

  test('a late failure cannot overwrite newer navigation', () async {
    final response = Completer<Listing>();
    when(() => h.files.openListing(any(), bad, any()))
        .thenAnswer((_) => response.future);
    final old = panel.open(bad);
    await panel.open(const Location.native('/tmp'));
    response.completeError(
      const FerryxException(FerryxErrorKind.notFound, 'old failure'),
    );
    await old;
    expect(panel.state.active!.location, const Location.native('/tmp'));
    expect(panel.state.active!.error, isNull);
    expect(panel.state.active!.loading, isFalse);
    expect(logs.messages, isEmpty);
  });

  test('a reordered tab receives its own failure', () async {
    final response = Completer<Listing>();
    when(() => h.files.openListing(any(), bad, any()))
        .thenAnswer((_) => response.future);
    final oldId = panel.state.active!.id;
    final pending = panel.open(bad);
    await panel.newTab(location: const Location.native('/tmp'));
    panel.moveTab(0, 1);
    response.completeError(
      const FerryxException(FerryxErrorKind.notFound, 'missing'),
    );
    await pending;
    final original = panel.state.tabs.singleWhere((tab) => tab.id == oldId);
    expect(original.loading, isFalse);
    expect(original.failedLocation, bad);
    expect(panel.state.active!.location, const Location.native('/tmp'));
    expect(panel.state.active!.error, isNull);
  });

  for (final fail in [false, true]) {
    test(
      'a late background refresh (failure=$fail) cannot replace newer navigation',
      () async {
        final response = Completer<Listing>();
        final before = panel.state.active!.listing!;
        when(() => h.files.refreshListing(any()))
            .thenAnswer((_) => response.future);
        final old = panel.refresh();
        await panel.open(const Location.native('/tmp'));
        if (fail) {
          response.completeError(
            const FerryxException(
              FerryxErrorKind.notFound,
              'old folder removed',
            ),
          );
        } else {
          response.complete(before);
        }
        await old;
        expect(panel.state.active!.location, const Location.native('/tmp'));
        expect(
          panel.state.active!.listing!.location,
          const Location.native('/tmp'),
        );
        expect(panel.state.active!.error, isNull);
      },
    );
  }

  test('cancelled navigation stops loading without showing an error', () async {
    when(() => h.files.openListing(any(), bad, any()))
        .thenThrow(const FerryxException(FerryxErrorKind.cancelled, 'stopped'));
    await panel.open(bad);
    expect(panel.state.active!.loading, isFalse);
    expect(panel.state.active!.location, home);
    expect(panel.state.active!.error, isNull);
    expect(logs.messages, isEmpty);
  });

  test(
    'unexpected failures keep diagnostics in the log and allow recovery',
    () async {
      when(() => h.files.openListing(any(), bad, any()))
          .thenThrow(StateError('internal diagnostic'));
      await panel.open(bad);
      final after = panel.state.active!;
      expect(after.location, home);
      expect(after.loading, isFalse);
      expect(after.error!.kind, FerryxErrorKind.io);
      expect(after.error!.message, isNot(contains('internal diagnostic')));
      expect(logs.messages.single.level, LogLevel.error);
      expect(logs.messages.single.error, isA<StateError>());
      expect(logs.messages.single.stackTrace, isNotNull);
      await panel.open(const Location.native('/tmp'));
      expect(panel.state.active!.error, isNull);
    },
  );

  test(
    'a failed Back leaves the history cursor at the shown location',
    () async {
      await panel.open(const Location.native('/tmp'));
      final before = panel.state.active!;
      h.folders.remove(home.path);
      await panel.goBack();
      expect(panel.state.active!.location, before.location);
      expect(panel.state.active!.historyIndex, before.historyIndex);
      h.addFolder(home.path);
      await panel.goBack();
      expect(panel.state.active!.location, home);
      expect(panel.state.active!.historyIndex, 0);
    },
  );
}
