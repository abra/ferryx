import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether the area holding [label]'s field is the active one, as what it
/// holds reads it.
bool _active(WidgetTester tester, String label) => AppFocusArea.activeOf(
  tester.element(find.byKey(ValueKey('probe $label'))),
);

/// The bar across the top of the area around [label].
Color _bar(WidgetTester tester, String label) {
  final area = find.ancestor(
    of: find.byKey(ValueKey('probe $label')),
    matching: find.byType(AppFocusArea),
  );
  return tester
      .widget<ColoredBox>(
        find.descendant(of: area.first, matching: find.byType(ColoredBox)).last,
      )
      .color;
}

Widget _field(String label, FocusNode node) => Builder(
  key: ValueKey('probe $label'),
  builder: (context) => TextField(
    focusNode: node,
    decoration: InputDecoration(hintText: label),
  ),
);

void main() {
  testWidgets('the area around the focus draws the bar and takes the '
      'accent; the innermost wins, and a menu keeps the last one', (
    tester,
  ) async {
    final pages = FocusNode();
    final notes = FocusNode();
    final outer = FocusNode();
    final menu = FocusNode();
    addTearDown(pages.dispose);
    addTearDown(notes.dispose);
    addTearDown(outer.dispose);
    addTearDown(menu.dispose);
    final theme = AppTheme.light(AppPlatformStyle.macos);
    final accent = theme.extension<AppColorsExt>()!.accent;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(
            children: [
              _field('outside', menu),
              Expanded(
                child: AppFocusArea(
                  child: Column(
                    children: [
                      _field('pane', outer),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: AppFocusArea(
                                child: _field('pages', pages),
                              ),
                            ),
                            Expanded(
                              child: AppFocusArea(
                                child: _field('notes', notes),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(_bar(tester, 'pages'), const Color(0x00000000));
    expect(_active(tester, 'outside'), isTrue, reason: 'outside every area');

    pages.requestFocus();
    await tester.pump();
    expect(_active(tester, 'pages'), isTrue);
    expect(_active(tester, 'notes'), isFalse);
    expect(_active(tester, 'pane'), isFalse, reason: 'the innermost wins');
    expect(_bar(tester, 'pages'), accent);
    expect(_bar(tester, 'notes'), const Color(0x00000000));
    expect(_bar(tester, 'pane'), const Color(0x00000000));

    notes.requestFocus();
    await tester.pump();
    expect(_active(tester, 'pages'), isFalse);
    expect(_active(tester, 'notes'), isTrue);
    expect(_bar(tester, 'notes'), accent);
    expect(_bar(tester, 'pages'), const Color(0x00000000));

    // A focus outside every area, as a menu's or a dialog's, leaves the
    // last area marked.
    menu.requestFocus();
    await tester.pump();
    expect(_active(tester, 'notes'), isTrue);
    expect(_bar(tester, 'notes'), accent);

    outer.requestFocus();
    await tester.pump();
    expect(_active(tester, 'pane'), isTrue);
    expect(_active(tester, 'notes'), isFalse);
    expect(_bar(tester, 'pane'), accent);
  });

  testWidgets('an area mounted around the focus is active at once', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    Widget app({required bool area}) => MaterialApp(
      theme: AppTheme.light(AppPlatformStyle.macos),
      home: Scaffold(
        body: area
            ? AppFocusArea(child: _field('field', node))
            : _field('field', node),
      ),
    );
    await tester.pumpWidget(app(area: false));
    node.requestFocus();
    await tester.pump();
    await tester.pumpWidget(app(area: true));
    await tester.pump();
    expect(_active(tester, 'field'), isTrue);
  });
}
