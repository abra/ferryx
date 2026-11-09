import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/src/formats/mobi/mobi6_markup.dart';

/// The expressions `mobi.js` runs over a Latin-1 view of the stream.
final _pagebreak = RegExp(
  r'<\s*(?:mbp:)?pagebreak[^>]*>',
  caseSensitive: false,
);
final _filepos = RegExp(
  r'''<[^<>]+filepos=['"]{0,1}(\d+)[^<>]*>''',
  caseSensitive: false,
);

Uint8List latin1(String text) => Uint8List.fromList(text.codeUnits);

void main() {
  group('pagebreaks', () {
    test('start at each tag, with or without the prefix, in any case', () {
      const text =
          'a<mbp:pagebreak/>b< \tMBP:PageBreak >c<pagebreak>d'
          '<mbp:pagebreaker x="<">e';
      expect(mobiPagebreakStarts(latin1(text)), [1, 18, 37, 49]);
    });

    test('a no-break space counts as space, other bytes do not', () {
      expect(mobiPagebreakStarts(latin1('<\u00A0pagebreak>')), [0]);
      expect(mobiPagebreakStarts(latin1('<\u0085pagebreak>')), isEmpty);
    });

    test('need a closing bracket and the whole name', () {
      expect(mobiPagebreakStarts(latin1('<mbp:pagebrea>')), isEmpty);
      expect(mobiPagebreakStarts(latin1('<mbp:x pagebreak>')), isEmpty);
      expect(mobiPagebreakStarts(latin1('<mbp:pagebreak')), isEmpty);
      expect(mobiPagebreakStarts(latin1('')), isEmpty);
    });

    test('do not overlap: a tag inside a match is skipped', () {
      expect(mobiPagebreakStarts(latin1('<pagebreak <pagebreak>>')), [0]);
    });
  });

  group('filepos values', () {
    test('as written, quoted or not, in any case', () {
      const text =
          '<a filepos=0012>x</a><a FILEPOS="34">y</a>'
          "<reference type=\"toc\" filepos='0000056'/>";
      expect(mobiFileposValues(latin1(text)), ['0012', '34', '0000056']);
    });

    test('a tag naming filepos twice gives the last with digits', () {
      expect(mobiFileposValues(latin1('<a filepos=1 filepos=2>')), ['2']);
      expect(mobiFileposValues(latin1('<a filepos=1 filepos=x>')), ['1']);
    });

    test('need a character before the name, digits and a closing bracket', () {
      expect(mobiFileposValues(latin1('<filepos=1>')), isEmpty);
      expect(mobiFileposValues(latin1('<a filepos=>')), isEmpty);
      expect(mobiFileposValues(latin1('<a filepos="">')), isEmpty);
      expect(mobiFileposValues(latin1('<a filepos=1')), isEmpty);
      expect(mobiFileposValues(latin1('<a filepos=1 <b>')), isEmpty);
      expect(mobiFileposValues(latin1('<a <b filepos=3>')), ['3']);
    });
  });

  test('an anchor inside a tag goes before the tag', () {
    final bytes = latin1('<p>a</p><p class="x">b</p>');
    final tag = '<p>a</p>'.length;
    expect(mobiAnchorOffset(bytes, tag + 3), tag, reason: 'inside the tag');
    expect(mobiAnchorOffset(bytes, tag), tag, reason: 'at its start');
    expect(mobiAnchorOffset(bytes, 3), 3, reason: 'in text after a tag');
    expect(mobiAnchorOffset(latin1('plain text'), 4), 4);
    expect(mobiAnchorOffset(bytes, 0), 0);
  });

  test('both scans match the expressions on random markup', () {
    const pieces = [
      '<',
      '>',
      ' ',
      '\t',
      '\u00A0',
      '\u0085',
      '\u00FF',
      'a',
      '=',
      '"',
      "'",
      '/',
      '0',
      '7',
      'x',
      'mbp:',
      'MbP:',
      'pagebreak',
      'PAGEBREAK',
      'pagebrea',
      'filepos=',
      'FilePos=',
      'filepos',
      '\n',
      '<mbp:pagebreak',
      '< pagebreak',
      '<a filepos=',
      "<a filepos='",
      '<x FILEPOS="',
      '12>',
      '0"/>',
    ];
    final random = Random(7);
    var pagebreaks = 0;
    var fileposes = 0;
    for (var round = 0; round < 3000; round++) {
      final text = [
        for (var i = random.nextInt(40); i > 0; i--)
          pieces[random.nextInt(pieces.length)],
      ].join();
      final bytes = latin1(text);
      pagebreaks += _pagebreak.allMatches(text).length;
      fileposes += _filepos.allMatches(text).length;
      expect(
        mobiPagebreakStarts(bytes),
        [for (final m in _pagebreak.allMatches(text)) m.start],
        reason: text,
      );
      expect(
        mobiFileposValues(bytes),
        [for (final m in _filepos.allMatches(text)) m.group(1)],
        reason: text,
      );
    }
    expect(pagebreaks, greaterThan(500), reason: 'the markup matches');
    expect(fileposes, greaterThan(500), reason: 'the markup matches');
  });
}
