import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:panels_feature/src/dialogs/names_editor_dialog.dart';

import 'support/workspace_harness.dart';

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);

  late WorkspaceHarness h;
  late List<List<RenameOutcome>> applied;

  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp();
    applied = [];
    when(() => h.rename.apply(any())).thenAnswer((call) async {
      applied.add(call.positionalArguments[0] as List<RenameOutcome>);
      return const [];
    });
  });

  tearDown(() => h.tearDown());

  Future<void> open(WidgetTester tester) => h.press(
    tester,
    LogicalKeyboardKey.keyM,
    control: true,
    shift: true,
  );

  Finder field() => find.descendant(
    of: find.byType(NamesEditorDialog),
    matching: find.byType(EditableText),
  );

  String text(WidgetTester tester) =>
      tester.widget<EditableText>(field()).controller.text;

  FilledButton renameButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Rename'));

  Future<void> applyKey(WidgetTester tester) =>
      h.press(tester, LogicalKeyboardKey.enter, meta: true);

  testWidgets('with nothing selected, every row of the folder; the names '
      'renamed in one batch on ⌘Return, swaps included', (tester) async {
    await h.pump(tester);
    await open(tester);
    expect(find.byType(NamesEditorDialog), findsOneWidget);
    expect(text(tester), 'a.txt\nb.txt\nc.md');
    expect(renameButton(tester).onPressed, isNull, reason: 'nothing changed');
    await tester.enterText(field(), 'b.txt\na.txt\nnotes.md');
    await h.settle(tester);
    expect(find.textContaining('3 to rename'), findsOneWidget);
    expect(renameButton(tester).onPressed, isNotNull);
    await applyKey(tester);
    expect(find.byType(NamesEditorDialog), findsNothing);
    expect(applied.single, const [
      RenameOutcome(
        path: '/home/docs/a.txt',
        oldName: 'a.txt',
        newName: 'b.txt',
      ),
      RenameOutcome(
        path: '/home/docs/b.txt',
        oldName: 'b.txt',
        newName: 'a.txt',
      ),
      RenameOutcome(
        path: '/home/docs/c.md',
        oldName: 'c.md',
        newName: 'notes.md',
      ),
    ]);
  });

  testWidgets('thousands of names are checked once the typing pauses; '
      '⌘Return checks the text as it is', (tester) async {
    h.folders['/home/docs'] = [
      for (var i = 0; i < 2500; i++) h.file('/home/docs', 'IMG_$i.jpg'),
    ];
    await h.pump(tester);
    await open(tester);
    final start = text(tester);
    await tester.enterText(field(), 'IMG_1.jpg${start.substring(9)}');
    await tester.pump();
    expect(find.text('repeated'), findsNothing, reason: 'still typing');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('repeated'), findsNWidgets(2));
    expect(renameButton(tester).onPressed, isNull);
    await tester.enterText(field(), 'first.jpg${start.substring(9)}');
    await tester.pump();
    await applyKey(tester);
    expect(applied.single, const [
      RenameOutcome(
        path: '/home/docs/IMG_0.jpg',
        oldName: 'IMG_0.jpg',
        newName: 'first.jpg',
      ),
    ]);
  });

  testWidgets('a selection: only its names', (tester) async {
    await h.pump(tester);
    await h.press(tester, LogicalKeyboardKey.arrowDown);
    await h.press(tester, LogicalKeyboardKey.arrowDown, shift: true);
    await open(tester);
    expect(text(tester), 'a.txt');
  });

  testWidgets('errors show by their lines and in the summary, and keep '
      'Rename off; Return is a new line, not Rename', (tester) async {
    h.folders['/home/docs']!.add(h.file('/home/docs', '.hidden'));
    await h.pump(tester);
    await open(tester);
    await tester.enterText(field(), 'x.txt\nx.txt\n.hidden');
    await h.settle(tester);
    expect(renameButton(tester).onPressed, isNull);
    expect(find.text('repeated'), findsNWidgets(2));
    expect(find.text('taken'), findsOneWidget, reason: 'a hidden name too');
    expect(find.textContaining('3 errors'), findsOneWidget);
    // The summary names the caret's line's problem.
    expect(
      find.textContaining('Line 3: “.hidden” is in this folder already'),
      findsOneWidget,
    );
    tester.widget<EditableText>(field()).controller.selection =
        const TextSelection.collapsed(offset: 1);
    await h.settle(tester);
    expect(
      find.textContaining('Line 1: the same name as line 2'),
      findsOneWidget,
    );
    await h.press(tester, LogicalKeyboardKey.enter);
    await applyKey(tester);
    expect(applied, isEmpty);
    expect(find.byType(NamesEditorDialog), findsOneWidget);
    // A line too few: said in the summary.
    await tester.enterText(field(), 'a.txt\nb.txt');
    await h.settle(tester);
    expect(
      find.textContaining('The names need 3 lines; there are 2'),
      findsOneWidget,
    );
    expect(find.text('no line'), findsOneWidget);
  });

  testWidgets('Esc leaves at once when nothing was typed; asks before '
      'throwing edits away', (tester) async {
    await h.pump(tester);
    await open(tester);
    await h.press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(NamesEditorDialog), findsNothing);
    await open(tester);
    await tester.enterText(field(), 'z.txt\nb.txt\nc.md');
    await h.settle(tester);
    await h.press(tester, LogicalKeyboardKey.escape);
    expect(find.text('Discard the new names?'), findsOneWidget);
    await tester.tap(find.text('Keep Editing'));
    await h.settle(tester);
    expect(find.byType(NamesEditorDialog), findsOneWidget);
    expect(text(tester), 'z.txt\nb.txt\nc.md');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await h.settle(tester);
    await tester.tap(find.text('Discard'));
    await h.settle(tester);
    expect(find.byType(NamesEditorDialog), findsNothing);
    expect(applied, isEmpty);
  });

  testWidgets('each line sits beside its name and number, scrolled or not; '
      'a long name scrolls sideways instead of wrapping', (tester) async {
    final names = [for (var i = 0; i < 60; i++) 'file-$i.txt'];
    h.folders['/home/many'] = [
      for (final n in names) h.file('/home/many', n),
    ];
    final long = 'a-very-${'long-' * 40}name.txt';
    h.folders['/home/many']!.add(h.file('/home/many', long));
    await h.pump(tester, left: '/home/many');
    await open(tester);
    final editable = tester.state<EditableTextState>(field()).renderEditable;
    final value = text(tester);
    Future<void> expectBeside(int line) async {
      final start = line == 0
          ? 0
          : value.split('\n').take(line).join('\n').length + 1;
      final caret = editable.localToGlobal(
        editable.getLocalRectForCaret(TextPosition(offset: start)).topLeft,
      );
      final number = find.descendant(
        of: find.byType(NamesEditorDialog),
        matching: find.text('${line + 1}'),
      );
      final row = tester.getRect(number);
      expect(
        (caret.dy - row.top).abs(),
        lessThan(2),
        reason: 'line ${line + 1} beside its number',
      );
    }

    await expectBeside(0);
    await expectBeside(3);
    // The last line, after the text scrolled to it.
    final scroll = tester
        .widgetList<SingleChildScrollView>(
          find.descendant(
            of: find.byType(NamesEditorDialog),
            matching: find.byType(SingleChildScrollView),
          ),
        )
        .firstWhere(
          (v) => v.scrollDirection == Axis.vertical && v.controller != null,
        )
        .controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await h.settle(tester);
    final lines = names.length + 1;
    await expectBeside(lines - 1);
    // No wrapping: as many rows of text as lines.
    final lineHeight = editable.preferredLineHeight;
    expect(editable.size.height, closeTo(lines * lineHeight, 1));
  });

  testWidgets('fits a narrow window at the largest text size', (tester) async {
    await h.pump(tester, size: const Size(900, 600), textScale: 1.6);
    await open(tester);
    await tester.enterText(field(), 'x\nx\n');
    await h.settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(AppDialog), findsOneWidget);
  });
}
