import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_feature/src/text_layout.dart';

void main() {
  test('long lines are lossless lazy rows with logical line coordinates', () {
    final source = ['short', 'x' * 10001, 'end', ''];
    final layout = TextLayout(
      sourceLines: source,
      lineHeight: 20,
      columns: 80,
      wrap: true,
    );
    final rendered = List.generate(source.length, (_) => StringBuffer());
    var height = 0.0;
    for (var i = 0; i < layout.fragmentCount; i++) {
      final part = layout.fragmentAt(i);
      final text = source[part.line].substring(part.start, part.end);
      expect(text.length, lessThanOrEqualTo(80));
      rendered[part.line].write(text);
      height += layout.heightOfFragment(i);
    }
    expect(rendered.map((buffer) => buffer.toString()), source);
    expect(height, layout.extent);
    expect(layout.lines, source.length);
    expect(layout.offsetOfPosition(1, 80 * 100 + 3), 20 * 101);
    expect(layout.lineAtOffset(layout.offsetOfPosition(1, 9000)), 1);
    expect(layout.offsetOfLine(2), 20 * 127);
  });

  test('ordinary wrapping and unwrapped logical lines keep their layout', () {
    final lines = ['x' * 100, 'y' * 12000];
    final wrapped = TextLayout(
      sourceLines: lines,
      lineHeight: 10,
      columns: 40,
      wrap: true,
    );
    expect(wrapped.fragmentAt(0).end, 100);
    expect(wrapped.heightOfFragment(0), 30);
    expect(wrapped.offsetOfPosition(0, 90), 20);
    final unwrapped = TextLayout(
      sourceLines: lines,
      lineHeight: 10,
      columns: 40,
      wrap: false,
    );
    expect(unwrapped.fragmentCount, 2);
    expect(unwrapped.maxLineLength, 12000);
    expect(unwrapped.offsetOfPosition(1, 10000), 10);
    expect(unwrapped.lineAtOffset(15), 1);
    expect(unwrapped.extent, 20);
  });

  test('fragment boundaries preserve supplementary Unicode scalars', () {
    final text = '${'a' * 79}😀${'b' * 3000}😀';
    for (final columns in [1, 2, 80, 2048]) {
      final layout = TextLayout(
        sourceLines: [text],
        lineHeight: 10,
        columns: columns,
        wrap: true,
      );
      final parts = <String>[];
      for (var i = 0; i < layout.fragmentCount; i++) {
        final part = layout.fragmentAt(i);
        final slice = text.substring(part.start, part.end);
        expect(slice.runes, isNot(contains(0xFFFD)));
        expect(slice, isNotEmpty);
        parts.add(slice);
      }
      expect(parts.join(), text);
    }
    expect(scalarBoundaryBefore(text, 80), 79);
    expect(scalarBoundaryAfter(text, 80), 81);
  });

  test('empty windows have no fragments or scroll extent', () {
    for (final wrap in [false, true]) {
      final layout = TextLayout(
        sourceLines: [],
        lineHeight: 10,
        columns: 1,
        wrap: wrap,
      );
      expect(layout.fragmentCount, 0);
      expect(layout.extent, 0);
      expect(layout.offsetOfPosition(0, 0), 0);
    }
  });
}
