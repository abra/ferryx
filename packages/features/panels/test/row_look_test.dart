import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/src/panel/panel_row.dart';

/// The colours a row takes: the cursor emphasized in the active panel,
/// greyed elsewhere; a selection tinted in the active panel, greyed
/// elsewhere; nothing on a plain row.
void main() {
  late AppColorsExt colors;
  late BuildContext context;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: Builder(
          builder: (c) {
            context = c;
            colors = c.appColors;
            return const SizedBox();
          },
        ),
      ),
    );
  }

  RowLook look({
    bool cursor = false,
    bool active = true,
    bool selected = false,
    bool dimmed = false,
  }) => RowLook(
    cursor: cursor,
    active: active,
    selected: selected,
    match: null,
    dimmed: dimmed,
  );

  testWidgets('the cursor row of the active panel takes the emphasized '
      'selection with its own text colours', (tester) async {
    await pump(tester);
    final row = look(cursor: true);
    expect(row.emphasized, isTrue);
    expect(row.background(colors), colors.selectionAccent);
    expect(row.foreground(context), colors.onSelection);
    expect(row.secondary(colors), colors.onSelectionMuted);
    expect(row.checkMark(colors), colors.onSelection);
  });

  testWidgets('the cursor row elsewhere greys and keeps the normal text', (
    tester,
  ) async {
    await pump(tester);
    final row = look(cursor: true, active: false);
    expect(row.emphasized, isFalse);
    expect(row.background(colors), colors.selectionMuted);
    expect(row.foreground(context), context.colors.onSurface);
    expect(row.secondary(colors), colors.textMuted);
  });

  testWidgets('a selected row is tinted in the active panel, grey in the '
      'other', (tester) async {
    await pump(tester);
    final active = look(selected: true);
    expect(active.background(colors), colors.accentSoft);
    expect(active.foreground(context), colors.link);
    expect(active.checkMark(colors), colors.accent);
    final inactive = look(selected: true, active: false);
    expect(inactive.background(colors), colors.selectionMuted);
    expect(inactive.foreground(context), context.colors.onSurface);
    expect(inactive.checkMark(colors), colors.textMuted);
  });

  testWidgets('the cursor on a selected row wins; a plain row has no fill '
      'and a dimmed one fades', (tester) async {
    await pump(tester);
    expect(
      look(cursor: true, selected: true).background(colors),
      colors.selectionAccent,
    );
    expect(look().background(colors), isNull);
    expect(look().foreground(context), context.colors.onSurface);
    expect(look(dimmed: true).foreground(context), colors.textFaint);
    expect(look(dimmed: true).secondary(colors), colors.textFaint);
  });

  testWidgets('a renamed cursor row keeps its icon\'s own colour: the '
      'field takes the row\'s fill away', (tester) async {
    await pump(tester);
    const entry = FileEntry(
      name: 'notes.txt',
      path: '/home/notes.txt',
      kind: EntryKind.file,
      isDir: false,
    );
    Future<Color?> iconColor({Widget? field}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppPlatformStyle.macos),
          home: Material(
            child: RowName(
              entry: entry,
              look: look(cursor: true),
              field: field,
            ),
          ),
        ),
      );
      return tester.widget<Icon>(find.byType(Icon)).color;
    }

    expect(await iconColor(), colors.onSelection);
    expect(await iconColor(field: const SizedBox()), isNot(colors.onSelection));
  });
}
