import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  test('bullets ignore the ordinal', () {
    expect(listMarkerText('disc', 7), '•');
    expect(listMarkerText('circle', 1), '◦');
    expect(listMarkerText('square', 1), '▪');
    expect(listMarkerText('none', 1), isNull);
  });

  test('numeric and alphabetic styles', () {
    expect(listMarkerText('decimal', 12), '12. ');
    expect(listMarkerText('decimal-leading-zero', 3), '03. ');
    expect(listMarkerText('decimal-leading-zero', -3), '-03. ');
    expect(listMarkerText('lower-alpha', 1), 'a. ');
    expect(listMarkerText('lower-latin', 26), 'z. ');
    expect(listMarkerText('upper-alpha', 27), 'AA. ');
    expect(listMarkerText('upper-alpha', 702), 'ZZ. ');
    expect(listMarkerText('upper-alpha', 703), 'AAA. ');
    expect(
      listMarkerText('lower-alpha', 0),
      '0. ',
      reason: 'out of range: decimal',
    );
    expect(listMarkerText('lower-greek', 3), 'γ. ');
    expect(listMarkerText('lower-roman', 4), 'iv. ');
    expect(listMarkerText('upper-roman', 1994), 'MCMXCIV. ');
    expect(listMarkerText('upper-roman', 4000), '4000. ');
    expect(listMarkerText('cjk-decimal', 205), '二〇五、');
  });

  test(
    'unsupported keywords count in decimal; strings are their own marker',
    () {
      expect(listMarkerText('armenian', 5), '5. ');
      expect(listMarkerText('→ ', 5), '→ ');
      expect(isOrderedListStyle('decimal'), isTrue);
      expect(isOrderedListStyle('disc'), isFalse);
      expect(isOrderedListStyle('→ '), isFalse);
    },
  );
}
