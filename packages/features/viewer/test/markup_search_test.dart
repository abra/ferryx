import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:viewer_feature/src/markup_search.dart';

void main() {
  test('matches formatted words across inline nodes and preserves markup', () {
    final result = searchMarkup((
      '<p>Caf<b>é</b> &amp; <i>TEA</i></p><p>other tea</p>',
      'cafe & tea',
    ));
    expect(result.excerpts.length, 1);
    final doc = html.parseFragment(result.html);
    expect(doc.querySelectorAll('b').single.text, 'é');
    expect(
      doc.querySelectorAll('mark').map((m) => m.text).join(),
      'Café & TEA',
    );
    expect(doc.querySelector('#ferryx-find-0-start'), isNotNull);
    expect(doc.text, 'Café & TEAother tea');
  });
  test(
    'ignores hidden executable text, keeps entities escaped and caps results',
    () {
      final result = searchMarkup((
        '<script>needle</script><p>&lt;needle&gt;</p>',
        'needle',
      ));
      expect(result.excerpts.length, 1);
      expect(result.html, contains('&lt;'));
      expect(
        searchMarkup(('<p>${List.filled(2000, 'x').join(' ')}</p>', 'x'))
            .excerpts
            .length,
        1001,
      );
    },
  );
}
