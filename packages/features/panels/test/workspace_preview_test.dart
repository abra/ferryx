import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:shortcuts/shortcuts.dart';

import 'support/workspace_harness.dart';

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);
  late WorkspaceHarness h;
  late _PreviewLog log;

  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp();
    h.addFolder('/tmp', ['other.txt']);
    log = _PreviewLog();
  });
  tearDown(() => h.tearDown());

  Finder panelView(PanelSide side) => find.byWidgetPredicate(
    (widget) => widget is PanelView && widget.key == ValueKey(side),
    skipOffstage: false,
  );
  PanelCubit panel(WidgetTester tester, PanelSide side) =>
      tester.element(panelView(side)).read<PanelCubit>();
  Future<void> pump(
    WidgetTester tester, {
    ValueChanged<WorkspaceSnapshot>? onSnapshot,
    WindowDecor decor = WindowDecor.none,
  }) => h.pump(
    tester,
    preview: WorkspacePreview(
      builder: (context, view) => _PreviewBody(
        key: ValueKey(view.location),
        view: view,
        log: log,
      ),
    ),
    onSnapshot: onSnapshot,
    decor: decor,
  );
  void focusFile(PanelCubit cubit, String name) => cubit.moveCursorTo(
    cubit.state.active!.rows.indexWhere((row) => row.name == name),
  );

  testWidgets('Space previews focused file, follows cursor after a pause, '
      'and preserves the covered panel', (tester) async {
    await pump(tester);
    final left = panel(tester, PanelSide.left);
    final right = panel(tester, PanelSide.right);
    await right.newTab();
    right.selectAll();
    final covered = right.state;
    final coveredView = tester.state(panelView(PanelSide.right));
    focusFile(left, 'a.txt');
    left.selectWhere((row) => row.name == 'c.md', select: true);
    await h.press(tester, LogicalKeyboardKey.space);
    expect(
      log.current!.widget.view.location,
      const Location.native('/home/docs/a.txt'),
    );
    expect(log.current!.widget.view.startInPreview, isTrue);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'left panel');
    expect(find.byType(PanelView), findsOneWidget);
    expect(tester.state(panelView(PanelSide.right)), same(coveredView));
    expect(right.state, same(covered));
    expect(
      tester.getTopLeft(find.byType(_PreviewBody)).dx,
      greaterThan(tester.getTopLeft(panelView(PanelSide.left)).dx),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // b.txt
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // c.md
    await tester.pump(const Duration(milliseconds: 100));
    expect(log.opened, [const Location.native('/home/docs/a.txt')]);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(log.opened, [
      const Location.native('/home/docs/a.txt'),
      const Location.native('/home/docs/c.md'),
    ]);
    expect(log.closed, [const Location.native('/home/docs/a.txt')]);
    left.selectAll();
    await tester.pump(const Duration(milliseconds: 200));
    expect(log.opened.length, 2, reason: 'selection is not the preview target');
    await h.press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(_PreviewBody), findsNothing);
    expect(find.byType(PanelView), findsNWidgets(2));
    expect(tester.state(panelView(PanelSide.right)), same(coveredView));
    expect(right.state, same(covered));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'left panel');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tab and click focus preview content; file commands are absent '
      'until Tab returns to the source', (tester) async {
    await pump(tester);
    final left = panel(tester, PanelSide.left);
    final right = panel(tester, PanelSide.right);
    focusFile(left, 'a.txt');
    await h.press(tester, LogicalKeyboardKey.space);
    final strip = find.byType(KeyHintStrip);
    final hintRect = tester.getRect(strip);
    final previewRect = tester.getRect(find.byType(_PreviewBody));
    await h.press(tester, LogicalKeyboardKey.tab);
    expect(log.current!.contentFocus.hasPrimaryFocus, isTrue);
    expect(strip, findsOneWidget);
    expect(tester.getRect(strip), hintRect);
    expect(tester.getRect(find.byType(_PreviewBody)), previewRect);
    final hints = tester.widget<KeyHintStrip>(strip);
    expect(hints.vim, isFalse);
    expect(hints.hints.whereType<CommandHint>().map((h) => h.command), [
      AppCommand.switchPanel,
      AppCommand.dismiss,
      AppCommand.internalViewer,
    ]);
    final before = left.state;
    await h.press(tester, LogicalKeyboardKey.arrowDown);
    expect(log.current!.position, 1);
    expect(left.state, same(before));
    final context = FocusManager.instance.primaryFocus!.context!;
    for (final command in [
      AppCommand.deleteItems,
      AppCommand.selectAll,
      AppCommand.newTab,
      AppCommand.renameInPlace,
    ]) {
      expect(canInvokeCommand(context, command), isFalse, reason: command.name);
      expect(invokeCommand(context, command), isFalse);
    }
    expect(right.state.tabs.length, 1);
    expect(h.started, isEmpty);
    await h.press(tester, LogicalKeyboardKey.tab);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'left panel');
    expect(tester.getRect(strip), hintRect);
    expect(
      canInvokeCommand(
        FocusManager.instance.primaryFocus!.context!,
        AppCommand.selectAll,
      ),
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('preview content')));
    await tester.pumpAndSettle();
    expect(log.current!.contentFocus.hasPrimaryFocus, isTrue);
    expect(strip, findsOneWidget);
    expect(tester.getRect(strip), hintRect);
    expect(tester.getRect(find.byType(_PreviewBody)), previewRect);
    await tester.tap(find.text('Close preview'));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'left panel');
    expect(find.byType(_PreviewBody), findsNothing);
  });

  testWidgets('F3 and placement toggle keep the same viewer and position; '
      'Tab from full window reveals the source', (tester) async {
    await pump(tester);
    focusFile(panel(tester, PanelSide.left), 'a.txt');
    final leftView = tester.state(panelView(PanelSide.left));
    final rightView = tester.state(panelView(PanelSide.right));
    await h.press(tester, LogicalKeyboardKey.f3);
    expect(log.current!.widget.view.fullWindow, isTrue);
    expect(log.current!.widget.view.startInPreview, isFalse);
    expect(find.byType(PanelView), findsNothing);
    expect(log.current!.contentFocus.hasPrimaryFocus, isTrue);
    final opened = log.current!;
    await h.press(tester, LogicalKeyboardKey.arrowDown);
    await tester.tap(find.text('Toggle placement'));
    await tester.pumpAndSettle();
    expect(log.current, same(opened));
    expect(opened.position, 1);
    expect(opened.widget.view.fullWindow, isFalse);
    expect(opened.widget.view.startInPreview, isFalse);
    expect(log.closed, isEmpty);
    expect(tester.state(panelView(PanelSide.left)), same(leftView));
    expect(tester.state(panelView(PanelSide.right)), same(rightView));
    await h.press(tester, LogicalKeyboardKey.f3);
    expect(log.current, same(opened));
    expect(opened.widget.view.fullWindow, isTrue);
    await h.press(tester, LogicalKeyboardKey.tab);
    expect(opened.widget.view.fullWindow, isFalse);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'left panel');
    expect(log.current, same(opened));
    expect(opened.position, 1);
    await h.press(tester, LogicalKeyboardKey.space);
    expect(log.closed, [const Location.native('/home/docs/a.txt')]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single-pane preview uses the opposite side temporarily and '
      'directories provide no file', (tester) async {
    unawaited(h.preferences.update((p) => p.copyWith(singlePane: true)));
    final snapshots = <WorkspaceSnapshot>[];
    await pump(tester, onSnapshot: snapshots.add);
    final left = panel(tester, PanelSide.left);
    final original = tester.state(panelView(PanelSide.left));
    expect(left.state.active!.focused!.isParent, isTrue);
    await h.press(tester, LogicalKeyboardKey.space);
    expect(log.current!.widget.view.location, isNull);
    expect(log.current!.widget.view.fullWindow, isFalse);
    expect(tester.getSize(find.byType(_PreviewBody)).width, lessThan(1200));
    expect(h.preferences.current.singlePane, isTrue);
    focusFile(left, 'b.txt');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(
      log.current!.widget.view.location,
      const Location.native('/home/docs/b.txt'),
    );
    await h.press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(PanelView), findsOneWidget);
    expect(tester.state(panelView(PanelSide.left)), same(original));
    expect(tester.getSize(panelView(PanelSide.left)).width, 1200);
    expect(h.preferences.current.singlePane, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(snapshots.last.singlePane, isTrue);
    expect(snapshots.last.active, PanelSide.left);
    expect(tester.takeException(), isNull);
  });

  testWidgets('right pane remains the source and Vim i toggles preview', (
    tester,
  ) async {
    unawaited(h.preferences.update((p) => p.copyWith(vimMode: true)));
    await pump(tester);
    await h.press(tester, LogicalKeyboardKey.tab);
    final right = panel(tester, PanelSide.right);
    focusFile(right, 'other.txt');
    await h.press(tester, LogicalKeyboardKey.keyI, character: 'i');
    expect(
      log.current!.widget.view.location,
      const Location.native('/tmp/other.txt'),
    );
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'right panel');
    expect(
      tester.getTopLeft(find.byType(_PreviewBody)).dx,
      lessThan(tester.getTopLeft(panelView(PanelSide.right)).dx),
    );
    await h.press(tester, LogicalKeyboardKey.keyI, character: 'i');
    expect(find.byType(_PreviewBody), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'right panel');
  });

  testWidgets('preview reserves only its window-button edge, with full '
      'decor in full-window and the stacked top pane', (tester) async {
    final decor = WindowDecor(
      leadingInset: 72,
      trailingInset: 48,
      dragArea: (child) => child,
    );
    await pump(tester, decor: decor);
    await h.press(tester, LogicalKeyboardKey.space);
    var shown = log.current!.widget.view.decor;
    expect(shown.leadingInset, 0);
    expect(shown.trailingInset, 48);
    expect(shown.dragArea, same(decor.dragArea));
    log.current!.widget.view.onToggleFullWindow();
    await tester.pumpAndSettle();
    expect(log.current!.widget.view.decor, same(decor));
    await h.press(tester, LogicalKeyboardKey.escape);
    await h.press(tester, LogicalKeyboardKey.tab);
    await h.press(tester, LogicalKeyboardKey.space);
    shown = log.current!.widget.view.decor;
    expect(shown.leadingInset, 72);
    expect(shown.trailingInset, 0);
    expect(shown.dragArea, same(decor.dragArea));
    unawaited(
      h.preferences.update(
        (p) => p.copyWith(panelArrangement: PanelArrangement.stacked),
      ),
    );
    await h.settle(tester);
    expect(log.current!.widget.view.decor, same(decor));
    await h.press(tester, LogicalKeyboardKey.escape);
    await h.press(tester, LogicalKeyboardKey.tab);
    await h.press(tester, LogicalKeyboardKey.space);
    expect(log.current!.widget.view.decor, same(WindowDecor.none));
    expect(tester.takeException(), isNull);
  });
}

class _PreviewLog {
  final opened = <Location?>[];
  final closed = <Location?>[];
  _PreviewBodyState? current;
}

/// Mirrors the root's ownership: a file change creates a viewer, placement
/// moves preserve it, and an explicit scope request focuses its content.
class _PreviewBody extends StatefulWidget {
  const _PreviewBody({required this.view, required this.log, super.key});
  final WorkspacePreviewView view;
  final _PreviewLog log;

  @override
  State<_PreviewBody> createState() => _PreviewBodyState();
}

class _PreviewBodyState extends State<_PreviewBody> {
  final contentFocus = FocusNode(debugLabel: 'preview content');
  var position = 0;

  @override
  void initState() {
    super.initState();
    widget.log.current = this;
    widget.log.opened.add(widget.view.location);
  }

  @override
  void dispose() {
    widget.log.closed.add(widget.view.location);
    contentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusScope(
    node: widget.view.focusScope,
    onFocusChange: (_) {
      if (widget.view.focusScope.hasPrimaryFocus) contentFocus.requestFocus();
    },
    child: Column(
      children: [
        TextButton(
          onPressed: widget.view.onClose,
          child: const Text('Close preview'),
        ),
        TextButton(
          onPressed: widget.view.onToggleFullWindow,
          child: const Text('Toggle placement'),
        ),
        Expanded(
          child: Focus(
            focusNode: contentFocus,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.arrowDown) {
                setState(() => position++);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: GestureDetector(
              onTap: contentFocus.requestFocus,
              behavior: HitTestBehavior.opaque,
              child: SizedBox.expand(
                key: const ValueKey('preview content'),
                child: Text(
                  '${widget.view.location?.path ?? 'No file'}: $position',
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
