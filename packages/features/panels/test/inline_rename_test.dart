import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/src/panel/inline_rename.dart';
import 'package:panels_feature/src/panel/panel_state.dart';
import 'package:shortcuts/shortcuts.dart';

void main() {
  late List<String> committed;

  setUp(() => committed = []);

  Future<void> pump(
    WidgetTester tester,
    String name, {
    RenameCaret caret = RenameCaret.stem,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: Material(
          child: InlineRename(
            // A field of its own per name, as a row's rename is.
            key: ValueKey(name),
            name: name,
            caret: caret,
            shortcutMap: ShortcutMap.defaults(TargetPlatform.macOS),
            onCommit: committed.add,
            onCancel: () {},
          ),
        ),
      ),
    );
    // The field takes the focus a frame after it shows.
    await tester.pump();
  }

  TextSelection selection(WidgetTester tester) => tester
      .widget<EditableText>(find.byType(EditableText))
      .controller
      .selection;

  // On the desktops a one-line field selects all of itself on focus,
  // unless told not to: the tests run as on macOS so that default applies.
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets(
    'the stem is selected once the field has the focus, so typing '
    'keeps the extension',
    variant: desktop,
    (tester) async {
      await pump(tester, 'report.final.txt');
      expect(
        selection(tester),
        const TextSelection(baseOffset: 0, extentOffset: 12),
      );
      // The desktop is told the same selection, so what is typed replaces
      // the stem only.
      expect(tester.testTextInput.editingState?['selectionBase'], 0);
      expect(tester.testTextInput.editingState?['selectionExtent'], 12);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'renamed.txt',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(committed, ['renamed.txt']);
    },
  );

  testWidgets(
    'a name without an extension, or a hidden one, is selected '
    'whole',
    variant: desktop,
    (tester) async {
      await pump(tester, 'Makefile');
      expect(
        selection(tester),
        const TextSelection(baseOffset: 0, extentOffset: 8),
      );
      await pump(tester, '.gitignore');
      expect(
        selection(tester),
        const TextSelection(baseOffset: 0, extentOffset: 10),
      );
    },
  );

  testWidgets('Vim\'s I and A put the caret at an end', variant: desktop, (
    tester,
  ) async {
    await pump(tester, 'a.txt', caret: RenameCaret.start);
    expect(selection(tester), const TextSelection.collapsed(offset: 0));
    await pump(tester, 'b.txt', caret: RenameCaret.end);
    expect(selection(tester), const TextSelection.collapsed(offset: 5));
  });
}
