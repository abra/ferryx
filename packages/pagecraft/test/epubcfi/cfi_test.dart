import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  group('parse and toString', () {
    // Strings the readers save, each in its canonical form.
    const canonical = [
      'epubcfi(/6/2)',
      'epubcfi(/6/14!/4/290,/1:175,/3:88)',
      'epubcfi(/6/28!/4,/70,/84/1:198)',
      'epubcfi(/6/32!/4/2/2[applying_psychological_principles_in_de]'
          '/10/2[ch11-conclusion]/4,/5:331,/7:7)',
      'epubcfi(/6/24!/4/2/2[aestheticen_dashusability_effect]/12/2[id32]'
          '/16/2[psychology_concept_07]/4,/11:40,/11:48)',
      'epubcfi(/6/4!/4/2/1:0)',
      'epubcfi(/6/2!/2[pagecraft],/1:3,/1:9)',
      'epubcfi(/6/4!/4/2[chap01ref]/10/2[para05]/3:10)',
      'epubcfi(/6/4!/4/2/1:5[Hello^,,world])',
      'epubcfi(/6/4!/4/2/1:5[;s=b])',
      'epubcfi(/6/4!/4/2[id^[1^];s=a]/1:0)',
      'epubcfi(/6/4!/4/2~1.5@0.5:0.25)',
      'epubcfi(/6/4!/4/2~12@3:4)',
      'epubcfi(/2/2[p],/1:3,/1:8)',
    ];

    for (final text in canonical) {
      test('round-trips $text', () {
        final cfi = Cfi.parse(text);
        expect(cfi.toString(), text);
        expect(Cfi.parse(cfi.toString()), cfi);
      });
    }

    test('reads steps, assertions and offsets into the model', () {
      final cfi = Cfi.parse('epubcfi(/6/4!/4/2[id;s=a]/1:5[pre,post])');
      final location = cfi as CfiLocation;
      expect(location.paths, hasLength(2));
      expect(location.paths[0], [const CfiStep(6), const CfiStep(4)]);
      final local = location.localPath;
      expect(local[0], const CfiStep(4));
      expect(local[1].index, 2);
      expect(local[1].id, 'id');
      expect(local[1].side, 'a');
      expect(local[2].index, 1);
      expect(local[2].offset, 5);
      expect(local[2].textAssertions, ['pre', 'post']);
      expect(cfi.firstPath, [const CfiStep(6), const CfiStep(4)]);
    });

    test('reads a range into parent, start and end', () {
      final cfi = Cfi.parse('/6/14!/4/290,/1:175,/3:88') as CfiRange;
      expect(cfi.parent.paths, [
        [const CfiStep(6), const CfiStep(14)],
        [const CfiStep(4), const CfiStep(290)],
      ]);
      expect(cfi.start.localPath, [const CfiStep(1, offset: 175)]);
      expect(cfi.end.localPath, [const CfiStep(3, offset: 88)]);
      expect(cfi.firstPath, [const CfiStep(6), const CfiStep(14)]);
      expect(
        (Cfi.parse('epubcfi(,/1:1,/2/2/1:2)') as CfiRange).firstPath,
        isEmpty,
      );
      expect(cfi.collapse().toString(), 'epubcfi(/6/14!/4/290/1:175)');
      expect(
        cfi.collapse(toEnd: true).toString(),
        'epubcfi(/6/14!/4/290/3:88)',
      );
    });

    test('accepts the string with or without its wrapper and spaces', () {
      expect(Cfi.parse('/6/2'), Cfi.parse('epubcfi(/6/2)'));
      expect(Cfi.parse('  /6/2 '), Cfi.parse('epubcfi(/6/2)'));
      expect(Cfi.isCfi('epubcfi(/6/2)'), isTrue);
      expect(Cfi.isCfi('/6/2'), isFalse);
      expect(unwrapCfi('epubcfi(/6/2)'), '/6/2');
      expect(unwrapCfi('/6/2'), '/6/2');
    });

    test('offsets print only on character data steps, as the spec asks', () {
      // Parsed on an element step the offset is kept for comparison but
      // not written back, as epubcfi.js does.
      final cfi = Cfi.parse('/6/4:3') as CfiLocation;
      expect(cfi.localPath.last.offset, 3);
      expect(cfi.toString(), 'epubcfi(/6/4)');
      expect(
        Cfi.parse('epubcfi(/6/4[page],/4/2:0,/4/2:5)').toString(),
        'epubcfi(/6/4[page],/4/2,/4/2)',
      );
    });

    test('escapes reserved characters in assertions', () {
      expect(escapeCfi('a^b[c]d(e)f,g;h=i'), 'a^^b^[c^]d^(e^)f^,g^;h^=i');
      final cfi = CfiLocation([
        [
          const CfiStep(4, id: 'x,y;z'),
          const CfiStep(1, offset: 2, textAssertions: ['a]b', 'c^d']),
        ],
      ]);
      expect(cfi.toString(), 'epubcfi(/4[x^,y^;z]/1:2[a^]b,c^^d])');
      expect(Cfi.parse(cfi.toString()), cfi);
    });

    test('an empty assertion with a side bias is kept, like epubcfi.js', () {
      final cfi = Cfi.parse('/6/4!/4/2/1:5[;s=b]');
      expect(cfi.toString(), 'epubcfi(/6/4!/4/2/1:5[;s=b])');
      final step = (cfi as CfiLocation).localPath.last;
      expect(step.side, 'b');
      expect(step.textAssertions, ['']);
    });

    test('joins indirections and unwraps the parts', () {
      expect(
        joinCfiIndirections(['epubcfi(/6/4)', '/4/2/1:0']),
        'epubcfi(/6/4!/4/2/1:0)',
      );
      expect(joinCfiIndirections(['epubcfi(/6/4)']), 'epubcfi(/6/4)');
    });

    test('rejects strings that are not CFIs', () {
      for (final bad in [
        '',
        'epubcfi()',
        'page 3',
        '/',
        '/a',
        ':3',
        '/6/4!/4[unterminated',
        '/6/4,/1:0',
        '/6/4,/1:0,/1:2,/1:3',
        '/6/4~x',
        '/6/4 /2',
      ]) {
        expect(
          () => Cfi.parse(bad),
          throwsA(isA<CfiFormatException>()),
          reason: bad,
        );
        expect(Cfi.tryParse(bad), isNull, reason: bad);
      }
    });

    test('fuzzing: random strings never throw anything but a format error', () {
      final random = Random(7);
      const alphabet = r'/!,:~@[];=^0123456789ab epubcfi()';
      for (var i = 0; i < 5000; i++) {
        final length = random.nextInt(24);
        final text = String.fromCharCodes([
          for (var j = 0; j < length; j++)
            alphabet.codeUnitAt(random.nextInt(alphabet.length)),
        ]);
        try {
          final cfi = Cfi.parse(text);
          // Whatever parses must round-trip through its canonical form.
          expect(Cfi.parse(cfi.toString()), cfi, reason: text);
        } on CfiFormatException {
          // Expected for most random strings.
        }
      }
    });

    test('fuzzing: generated CFIs round-trip through their strings', () {
      final random = Random(11);
      String word() => String.fromCharCodes([
        for (var j = 0, n = random.nextInt(6); j < n; j++)
          r'ab,;[]^=x1'.codeUnitAt(random.nextInt(10)),
      ]);
      // Text assertions belong to character data steps with an offset;
      // anywhere else the grammar reads the first one as an id, in
      // epubcfi.js as here.
      CfiStep step({required bool last}) {
        final index = random.nextInt(40);
        final offset = last && random.nextBool() ? random.nextInt(500) : null;
        return CfiStep(
          index,
          id: random.nextBool() ? null : 'id${random.nextInt(9)}${word()}',
          offset: offset,
          textAssertions:
              index.isOdd && offset != null && random.nextInt(3) == 0
              ? [word(), if (random.nextBool()) word()]
              : null,
          side: random.nextInt(4) == 0 ? (random.nextBool() ? 'a' : 'b') : null,
        );
      }

      CfiPath path() => [
        for (var i = 0, n = 1 + random.nextInt(5); i < n; i++)
          step(last: i == n - 1),
      ];
      for (var i = 0; i < 2000; i++) {
        final Cfi cfi = random.nextBool()
            ? CfiLocation([path(), if (random.nextBool()) path()])
            : CfiRange(
                parent: CfiLocation([path()]),
                start: CfiLocation([path()]),
                end: CfiLocation([path()]),
              );
        // An offset on an element step is not written: normalise first.
        final text = cfi.toString();
        final parsed = Cfi.parse(text);
        expect(parsed.toString(), text, reason: text);
      }
    });
  });

  group('compare', () {
    int order(String a, String b) => Cfi.parse(a).compareTo(Cfi.parse(b));

    test('orders by step, then by offset at the last step', () {
      expect(order('/6/4!/4/2/1:5', '/6/4!/4/2/1:9'), -1);
      expect(order('/6/4!/4/2/1:9', '/6/4!/4/2/1:5'), 1);
      expect(order('/6/4!/4/2/1:5', '/6/4!/4/2/1:5'), 0);
      expect(order('/6/4!/4/2/1:5', '/6/4!/4/4/1:0'), -1);
      expect(order('/6/6!/4/2', '/6/4!/4/8'), 1);
      expect(order('/6/4!/4/2[a]/1:5', '/6/4!/4/2[b]/1:5'), 0);
    });

    test('a missing step sorts first; an offset without a peer is equal', () {
      expect(order('/6/4', '/6/4!/2'), -1);
      expect(order('/6/4!/2', '/6/4!/2!/2'), -1);
      expect(order('/6/4!/2!/2', '/6/4!/2'), 1);
      expect(order('/6/4!/2', '/6/4!/2'), 0);
      expect(order('/6/4!/4/2', '/6/4!/4/2/1:5'), -1);
      expect(order('/6/4!/4/2/1', '/6/4!/4/2/1:5'), 0);
    });

    test('ranges compare by start, then by end', () {
      expect(order('/6/4!/4,/2/1:0,/2/1:5', '/6/4!/4/2/1:3'), -1);
      expect(order('/6/4!/4,/2/1:0,/2/1:5', '/6/4!/4,/2/1:0,/2/1:9'), -1);
      expect(order('/6/4!/4,/2/1:0,/2/1:9', '/6/4!/4,/2/1:0,/2/1:5'), 1);
      expect(order('/6/4!/4,/2/1:0,/2/1:5', '/6/4!/4,/2/1:0,/2/1:5'), 0);
    });

    test('sorts the readers\' saved anchors in reading order', () {
      final anchors = [
        'epubcfi(/6/28!/4,/70,/84/1:198)',
        'epubcfi(/6/14!/4/290,/1:175,/3:88)',
        'epubcfi(/6/14!/4/292,/1:322,/1:326)',
        'epubcfi(/6/2)',
        'epubcfi(/6/14!/4/290/1:10)',
      ].map(Cfi.parse).toList()..sort();
      expect(anchors.map((c) => c.toString()), [
        'epubcfi(/6/2)',
        'epubcfi(/6/14!/4/290/1:10)',
        'epubcfi(/6/14!/4/290,/1:175,/3:88)',
        'epubcfi(/6/14!/4/292,/1:322,/1:326)',
        'epubcfi(/6/28!/4,/70,/84/1:198)',
      ]);
    });
  });

  group('performance', () {
    // Highlights and bookmarks are parsed and ordered on every load; the
    // budget is generous against CI noise but catches a quadratic slip.
    test('parses and orders ten thousand saved anchors well under a second', () {
      final texts = [
        for (var i = 0; i < 10000; i++)
          'epubcfi(/6/${2 * (i % 50 + 1)}!/4/2/2[chapter-$i]/10/2[para]/4,'
              '/${2 * (i % 7) + 1}:${i % 300},/${2 * (i % 7) + 1}:${i % 300 + 5})',
      ];
      final watch = Stopwatch()..start();
      final parsed = texts.map(Cfi.parse).toList()..sort();
      final strings = parsed.map((c) => c.toString()).toList();
      watch.stop();
      expect(strings, hasLength(10000));
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });
  });

  group('buildCfiRange', () {
    test('shares the steps the points have in common', () {
      final range = buildCfiRange(
        Cfi.parse('/6/4!/4/2/1:3'),
        Cfi.parse('/6/4!/4/2/3:8'),
      );
      expect(range.toString(), 'epubcfi(/6/4!/4/2,/1:3,/3:8)');
    });

    test('a shared step with an offset is not shared', () {
      final range = buildCfiRange(
        Cfi.parse('/6/4!/4/2/1:3'),
        Cfi.parse('/6/4!/4/2/1:8'),
      );
      expect(range.toString(), 'epubcfi(/6/4!/4/2,/1:3,/1:8)');
    });

    test('paths of different depth split where they part', () {
      final range = buildCfiRange(
        Cfi.parse('/6/4!/4/2/1:0'),
        Cfi.parse('/6/4!/4/6/2/1:4'),
      );
      expect(range.toString(), 'epubcfi(/6/4!/4,/2/1:0,/6/2/1:4)');
    });

    test('ranges collapse to their ends before building', () {
      final range = buildCfiRange(
        Cfi.parse('/6/4!/4,/2/1:0,/2/1:5'),
        Cfi.parse('/6/4!/4,/4/1:0,/4/1:5'),
      );
      expect(range.toString(), 'epubcfi(/6/4!/4,/2/1:0,/4/1:5)');
    });
  });
}
