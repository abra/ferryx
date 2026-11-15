import 'package:component_library/component_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:viewer_feature/src/source_spans.dart';
import 'package:viewer_feature/src/source_syntax.dart';
import 'package:viewer_feature/src/text_window.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name}: fragment edges retain syntax and active matches',
      (tester) async {
        const match = ViewerMatch(line: 0, start: 9999, end: 10005);
        final matches = [
          for (var i = 0; i < 9990; i += 10)
            ViewerMatch(line: 0, start: i, end: i + 3),
          match,
          const ViewerMatch(line: 0, start: 20000, end: 20005),
        ];
        late TextSpan span;
        late AppColorsExt colors;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.of(AppPlatformStyle.macos, brightness),
            home: Builder(
              builder: (context) {
                colors = context.appColors;
                span = sourceSpans(
                  context,
                  'abcdxyz',
                  context.mono,
                  const [
                    SourceToken(0, 10003, 'string'),
                    SourceToken(10003, 30000, 'keyword'),
                  ],
                  matches,
                  match,
                  sourceOffset: 10001,
                );
                return Text.rich(span);
              },
            ),
          ),
        );
        expect(span.toPlainText(), 'abcdxyz');
        final parts = span.children!.whereType<TextSpan>().toList();
        expect(parts.map((part) => part.text), ['ab', 'cd', 'xyz']);
        for (final part in parts.take(2)) {
          expect(part.style!.backgroundColor, colors.accent);
          expect(part.style!.color, colors.onAccent);
        }
        expect(parts.last.style!.color, colors.ink(5));
        expect(parts.last.style!.backgroundColor, isNull);
      },
    );

    testWidgets(
      '${brightness.name}: search stays readable over syntax without changing text',
      (tester) async {
        const source = 'final text = "Привет";';
        final start = source.indexOf('Привет');
        final match = ViewerMatch(
          line: 0,
          start: start,
          end: start + 'Привет'.length,
        );
        late TextSpan span;
        late AppColorsExt colors;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.of(AppPlatformStyle.macos, brightness),
            home: Builder(
              builder: (context) {
                colors = context.appColors;
                span = sourceSpans(
                  context,
                  source,
                  context.mono,
                  [
                    const SourceToken(0, 5, 'keyword'),
                    SourceToken(
                      source.indexOf('"'),
                      source.lastIndexOf('"') + 1,
                      'string',
                    ),
                  ],
                  [match],
                  match,
                );
                return Text.rich(span);
              },
            ),
          ),
        );
        expect(span.toPlainText(), source);
        final marked = span.children!.whereType<TextSpan>().singleWhere(
          (s) => s.text == 'Привет',
        );
        expect(marked.style!.backgroundColor, colors.accent);
        expect(marked.style!.color, colors.onAccent);
        expect(
          span.children!.whereType<TextSpan>().first.style!.color,
          colors.ink(5),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
