import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_feature/src/source_spans.dart';
import 'package:viewer_feature/src/source_syntax.dart';
import 'package:viewer_feature/src/text_window.dart';

void main() {
  for (final brightness in Brightness.values) {
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
