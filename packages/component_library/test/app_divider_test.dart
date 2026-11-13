import 'package:component_library/component_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light(AppPlatformStyle.macos),
    home: Material(
      child: Align(alignment: Alignment.topLeft, child: child),
    ),
  ),
);

double _ruleWidth(WidgetTester tester) =>
    tester.getSize(find.byType(AppRule).first).width;

void main() {
  testWidgets('a divider spans the width it is given, as the line between '
      'a menu\'s groups and under a dialog\'s header must', (tester) async {
    // A column that does not stretch: the divider still takes its width.
    await _pump(
      tester,
      const SizedBox(
        width: 300,
        child: Column(children: [Text('above'), AppDivider(), Text('below')]),
      ),
    );
    expect(_ruleWidth(tester), 300);

    // In a menu: inset by its padding.
    await _pump(
      tester,
      const SizedBox(
        width: 200,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: AppDivider(height: 1),
        ),
      ),
    );
    expect(_ruleWidth(tester), 184);
    expect(tester.getSize(find.byType(AppRule)).height, 1);

    // With indents.
    await _pump(
      tester,
      const SizedBox(width: 300, child: AppDivider(indent: 20, endIndent: 10)),
    );
    expect(_ruleWidth(tester), 270);
  });

  testWidgets('a rule down a box spans its height; one with no bound to '
      'span takes none, without an error', (tester) async {
    await _pump(
      tester,
      const SizedBox(
        height: 120,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('left'),
            AppRule(axis: Axis.vertical),
            Text('right'),
          ],
        ),
      ),
    );
    expect(tester.getSize(find.byType(AppRule)).height, 120);
    expect(tester.getSize(find.byType(AppRule)).width, 1);

    await _pump(
      tester,
      const Row(
        mainAxisSize: MainAxisSize.min,
        children: [Text('a'), AppRule(), Text('b')],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(_ruleWidth(tester), 0);
  });
}
