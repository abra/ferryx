import 'package:component_library/component_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const style = TextStyle(fontSize: 14, fontFamily: 'Ahem');

  Future<void> pump(WidgetTester tester, String text, double width) =>
      tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: width,
              child: AppMiddleEllipsis(text, style: style),
            ),
          ),
        ),
      );

  String shown(WidgetTester tester) =>
      tester.widget<Text>(find.byType(Text)).data!;

  testWidgets('a name that fits is shown whole', (tester) async {
    await pump(tester, 'notes.txt', 400);
    expect(shown(tester), 'notes.txt');
  });

  testWidgets('a long name keeps its extension and loses its middle', (
    tester,
  ) async {
    // Ahem glyphs are 14 wide: 10 of them fit.
    await pump(tester, 'analysis_options.yaml', 140);
    // The tail is the extension and two letters; the head takes the rest.
    expect(shown(tester), 'an\u2026ns.yaml');
  });

  testWidgets('a name without an extension keeps its last letters', (
    tester,
  ) async {
    await pump(tester, 'abcdefghijklmnopqrstuvwxyz', 140);
    final text = shown(tester);
    expect(text, endsWith('xyz'));
    expect(text, contains('…'));
  });

  testWidgets('with no room for the tail the end is cut instead', (
    tester,
  ) async {
    await pump(tester, 'analysis_options.yaml', 30);
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, 'analysis_options.yaml');
    expect(text.overflow, TextOverflow.ellipsis);
  });

  test('the default tail is the extension and two letters, capped', () {
    expect(AppMiddleEllipsis.defaultTail('analysis_options.yaml'), 7);
    expect(AppMiddleEllipsis.defaultTail('Makefile'), 3);
    expect(AppMiddleEllipsis.defaultTail('a.verylongextension'), 7);
    expect(AppMiddleEllipsis.defaultTail('.bashrc'), 3);
  });
}
