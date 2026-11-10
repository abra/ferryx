import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_feature/src/source_syntax.dart';
import 'package:viewer_feature/src/text_preview_data.dart';
import 'package:viewer_feature/src/text_preview_format.dart';

void main() {
  test('recognizes document formats without misclassifying source files', () {
    for (final name in [
      'a.HTML',
      'a.htm',
      'a.xhtml',
      'a.RTF',
      'a.adoc',
      'a.asciidoc',
      'a.rst',
      'a.rest',
      'a.csv',
      'a.TSV',
    ]) {
      expect(textPreviewFormatOf(name), isNotNull, reason: name);
    }
    for (final name in ['html', 'a.html.zip', 'a.dart', 'a.json', 'a.txt']) {
      expect(textPreviewFormatOf(name), isNull, reason: name);
    }
    expect(syntaxLanguageOf('Cargo.toml'), 'ini');
    expect(syntaxLanguageOf('.env.local'), 'ini');
    expect(syntaxLanguageOf('a.RS'), 'rust');
    expect(syntaxLanguageOf('a.yml'), 'yaml');
  });

  test('CSV preserves quoted commas, multiline fields, empty cells and leading zeros', () async {
    final data = await prepareTable(
      'id,note,value\r\n001,"line one\r\nline two, ","a""b"\r\n002,,003',
      tsv: false,
    ) as TablePreviewData;
    expect(data.columns, 3);
    expect(data.rows, [
      ['id', 'note', 'value'],
      ['001', 'line one\r\nline two, ', 'a"b'],
      ['002', '', '003'],
    ]);
  });

  test('semicolon CSV detection ignores commas inside quoted values', () async {
    final data = await prepareTable(
      '"Last, First";Age\n"Doe, Jane";32',
      tsv: false,
    ) as TablePreviewData;
    expect(data.rows, [
      ['Last, First', 'Age'],
      ['Doe, Jane', '32'],
    ]);
  });

  test(
    'TSV keeps literal strings and ragged rows without inventing values',
    () async {
      final data = await prepareTable(
        'a\tb\tc\n001\t002\nx',
        tsv: true,
      ) as TablePreviewData;
      expect(data.columns, 3);
      expect(data.rows.last, ['x']);
      expect(data.rows[1], ['001', '002']);
    },
  );

  test(
    'table layout limits are reported without silently truncating data',
    () async {
      for (final source in [
        List.filled(5001, 'a').join('\n'),
        List.filled(65, 'a').join(','),
        'a' * 16385,
      ]) {
        final data =
            await prepareTable(source, tsv: false) as FailedTextPreview;
        expect(data.reason, TextPreviewFailure.limit);
      }
      expect(
        (await prepareTable(
          '"unclosed',
          tsv: false,
        ) as FailedTextPreview).reason,
        TextPreviewFailure.malformed,
      );
    },
  );

  test('HTML keeps document semantics and drops active content and resource styles', () async {
    final data = await prepareHtml(
      '<html><head><script>bad()</script></head><body><h1 id="title">Title</h1><p onclick="bad()" style="font-weight:bold;color:red;background-image:url(https://bad)">Text</p><img src="images/a.png" srcset="https://bad" alt="Photo"><iframe src="file:///tmp/x"></iframe><table><tr><td colspan="999999">Cell</td></tr></table></body></html>',
    ) as HtmlPreviewData;
    expect(data.html, contains('<h1 id="title">Title</h1>'));
    expect(data.html, contains('font-weight:bold'));
    expect(data.html, contains('images/a.png'));
    expect(data.html, contains('colspan="64"'));
    for (final removed in [
      '<script',
      'onclick',
      'color:red',
      'url(',
      'srcset',
      '<iframe',
    ]) {
      expect(data.html, isNot(contains(removed)));
    }
  });

  for (final (language, source) in [
    ('dart', 'final message = "Привет"; // comment\n'),
    ('rust', 'fn main() { let count = 42; }'),
    ('json', '{"name":"Привет","enabled":true}'),
    ('yaml', 'name: example\nenabled: true\n'),
    ('ini', '[package]\nname = "ferryx"\n'),
    ('xml', '<root value="ok">Text</root>'),
    ('javascript', 'const answer = 42;'),
    ('typescript', 'const answer: number = 42;'),
  ]) {
    test(
      '$language highlighting produces scoped ranges in the original text',
      () async {
        final tokens = await highlightSource(language, source);
        final lines = source.split('\n');
        expect(tokens.length, lines.length);
        expect(
          tokens.expand((line) => line).any((t) => t.scope.isNotEmpty),
          isTrue,
        );
        for (var i = 0; i < tokens.length; i++) {
          for (final token in tokens[i]) {
            expect(token.start, greaterThanOrEqualTo(0));
            expect(token.end, lessThanOrEqualTo(lines[i].length));
          }
        }
      },
    );
  }
}
