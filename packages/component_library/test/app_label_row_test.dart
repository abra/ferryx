import 'package:component_library/component_library.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  // The test font draws every glyph as a 10 px square at size 10.
  const style = TextStyle(fontSize: 10, height: 1);
  const label = 'Markdown'; // 80 px
  const hint = '.md / .zip'; // 100 px

  Future<void> pumpAt(WidgetTester tester, double width) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: AppLabelRow(
            gap: 8,
            label: const Text(
              label,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Text(
              hint,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    ),
  );

  RenderParagraph paragraph(WidgetTester tester, String text) =>
      tester.renderObject(find.text(text));
  RenderAppLabelRow row(WidgetTester tester) =>
      tester.renderObject(find.byType(AppLabelRow));

  testWidgets('both whole where they fit; the trailing text at the end', (
    tester,
  ) async {
    await pumpAt(tester, 300);
    expect(paragraph(tester, label).didExceedMaxLines, isFalse);
    expect(paragraph(tester, hint).didExceedMaxLines, isFalse);
    expect(tester.getTopRight(find.text(hint)).dx, 300);
    expect(tester.getSize(find.byType(AppLabelRow)).width, 300);
  });

  testWidgets('short of room the label keeps its width and the trailing '
      'text ends in an ellipsis', (tester) async {
    await pumpAt(tester, 140);
    expect(paragraph(tester, label).didExceedMaxLines, isFalse);
    expect(tester.getSize(find.text(label)).width, 80);
    expect(paragraph(tester, hint).didExceedMaxLines, isTrue);
    expect(tester.getSize(find.text(hint)).width, 140 - 80 - 8);
    expect(row(tester).showsTrailing, isTrue);
  });

  testWidgets('with less than the minimum left the trailing text hides and '
      'the label takes the row', (tester) async {
    await pumpAt(tester, 100);
    expect(row(tester).showsTrailing, isFalse);
    await pumpAt(tester, 60);
    expect(row(tester).showsTrailing, isFalse);
    expect(paragraph(tester, label).didExceedMaxLines, isTrue);
    expect(tester.getSize(find.text(label)).width, 60);
  });

  testWidgets('AppNavItem gives its label the priority over its hint', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: const Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              child: AppNavItem(
                label: 'Markdown',
                trailing: Text(
                  'folder / .md / .zip',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('Markdown'))
          .didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}
