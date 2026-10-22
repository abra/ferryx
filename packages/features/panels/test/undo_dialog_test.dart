import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/src/dialogs/undo_dialog.dart';
import 'package:panels_feature/src/workspace/context_menu.dart';
import 'package:panels_feature/src/panel/panel_state.dart';
import 'package:panels_feature/src/workspace/key_hints.dart';
import 'package:shortcuts/shortcuts.dart';

const _step = StepSummary(
  id: 7,
  kind: StepKind.move,
  items: 3,
  firstName: 'a.txt',
);

void main() {
  final en = lookupFerryxLocalizations(const Locale('en'));

  Future<UndoChoice?> open(
    WidgetTester tester,
    UndoCheck check, {
    bool redo = false,
  }) async {
    UndoChoice? result;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showUndoDialog(
                    context,
                    check: check,
                    redo: redo,
                  );
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    addTearDown(() => expect(closed, isTrue));
    return result;
  }

  testWidgets('a partial step names what cannot be undone and why', (
    tester,
  ) async {
    await open(
      tester,
      const UndoCheck(
        step: _step,
        issues: [
          UndoIssue(
            kind: UndoIssueKind.occupied,
            path: '/home/a.txt',
            blocks: true,
          ),
          UndoIssue(kind: UndoIssueKind.lost, path: '/b/c.txt', blocks: false),
        ],
        issuesTotal: 5,
        doable: 2,
        total: 3,
      ),
    );
    expect(find.text(en.undoDialogTitle(en.stepLabel(_step))), findsOneWidget);
    expect(find.text(en.undoPartly(2, 3)), findsOneWidget);
    expect(find.text(en.undoIssueOccupied), findsOneWidget);
    expect(find.text(en.undoIssueLost), findsOneWidget);
    expect(find.text(en.undoMoreIssues(3)), findsOneWidget);
    // Return runs the default action: Undo what can be.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  });

  testWidgets('Return undoes the rest; Esc leaves the step alone', (
    tester,
  ) async {
    const check = UndoCheck(
      step: _step,
      issues: [
        UndoIssue(kind: UndoIssueKind.changed, path: '/c', blocks: false),
      ],
      doable: 1,
      total: 1,
    );
    UndoChoice? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => picked = await showUndoDialog(
                context,
                check: check,
                redo: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(en.redoWarnings), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, UndoChoice.proceed);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });

  testWidgets('a step with nothing left offers to forget it', (tester) async {
    UndoChoice? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => picked = await showUndoDialog(
                context,
                check: const UndoCheck(
                  step: _step,
                  issues: [
                    UndoIssue(
                      kind: UndoIssueKind.missing,
                      path: '/gone',
                      blocks: true,
                    ),
                  ],
                  doable: 0,
                  total: 1,
                ),
                redo: false,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(en.undoNone), findsOneWidget);
    await tester.tap(find.text(en.undoForget));
    await tester.pumpAndSettle();
    expect(picked, UndoChoice.forget);
  });

  group('step labels', () {
    test('one item by name, several by count', () {
      expect(en.stepLabel(_step), 'Move of 3 items');
      expect(
        en.stepLabel(
          const StepSummary(
            id: 1,
            kind: StepKind.rename,
            items: 1,
            firstName: 'a.txt',
          ),
        ),
        'Rename of “a.txt”',
      );
      final ru = lookupFerryxLocalizations(const Locale('ru'));
      expect(ru.stepLabel(_step), 'перемещение 3 объектов');
      expect(
        ru.stepLabel(
          const StepSummary(
            id: 1,
            kind: StepKind.trash,
            items: 21,
            firstName: 'x',
          ),
        ),
        'перемещение в Корзину 21 объекта',
      );
    });
  });

  testWidgets('the panel menu names the next undo and greys an empty redo', (
    tester,
  ) async {
    late List<AppMenuEntry<AppCommand>> entries;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: Builder(
          builder: (context) {
            entries = panelMenuEntries(
              context,
              showHidden: false,
              singlePane: false,
              native: true,
              map: ShortcutMap.defaults(TargetPlatform.macOS),
              journal: const JournalSummary(undo: _step),
            );
            return const SizedBox();
          },
        ),
      ),
    );
    final actions = entries.whereType<AppMenuAction<AppCommand>>().toList();
    final undo = actions.firstWhere((a) => a.value == AppCommand.undo);
    final redo = actions.firstWhere((a) => a.value == AppCommand.redo);
    expect(undo.label, 'Undo Move of 3 items');
    expect(undo.enabled, isTrue);
    expect(undo.shortcut, '⌘Z');
    expect(redo.label, en.cmdRedo);
    expect(redo.enabled, isFalse);
  });

  test('a checksum file under the cursor hints the Checksums command', () {
    for (final (name, hinted) in [
      ('SHA256SUMS', true),
      ('disk.iso.md5', true),
      ('notes.txt', false),
    ]) {
      final tab = PanelTabState(
        id: 't',
        location: const Location.native('/home'),
        sort: const SortOptions(),
        rows: [
          FileEntry(
            name: name,
            path: '/home/$name',
            kind: EntryKind.file,
            isDir: false,
          ),
        ],
        cursor: 0,
      );
      final hints = hintsFor(tab: tab, vim: false, hasRegister: false);
      expect(
        hints.whereType<CommandHint>().any(
          (h) => h.command == AppCommand.checksums,
        ),
        hinted,
        reason: name,
      );
    }
  });
}
