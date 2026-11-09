import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  // Snapshot of `Intl.Collator('en', {numeric: true, sensitivity:
  // 'variant'})` from Node: the sorted list uses the WebView reader's
  // code-unit tie-break, the pairs are the bare collator sign.
  final fixture =
      jsonDecode(
            File('test/fixtures/icu_natural_order.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final sorted = (fixture['sorted'] as List).cast<String>();
  final pairs = (fixture['pairs'] as List)
      .map((p) => (p as List).cast<Object>())
      .toList();

  group('naturalFilenameCompare', () {
    test('sorts the ICU fixture into the same order', () {
      final shuffled = [...sorted]..shuffle();
      shuffled.sort(naturalFilenameCompare);
      expect(shuffled, sorted);
    });

    test('agrees with the collator on every pair, ties by code unit', () {
      final disagreements = <String>[];
      for (final pair in pairs) {
        final a = pair[0] as String;
        final b = pair[1] as String;
        final icu = pair[2] as int;
        final expected = icu != 0 ? icu : a.compareTo(b).sign;
        final actual = naturalFilenameCompare(a, b).sign;
        if (actual != expected) {
          disagreements.add('$a vs $b: expected $expected, got $actual');
        }
      }
      expect(disagreements, isEmpty, reason: disagreements.join('\n'));
      expect(pairs.length, 3080);
    });

    // Probed on the same collator, for letters and symbols outside the
    // fixture list.
    const probes = <(String, String, int)>[
      ('ø.jpg', 'o.jpg', 1),
      ('ø.jpg', 'p.jpg', -1),
      ('đ.jpg', 'd.jpg', 1),
      ('đ.jpg', 'e.jpg', -1),
      ('ł.jpg', 'l.jpg', 1),
      ('ł.jpg', 'm.jpg', -1),
      ('æ.jpg', 'ae.jpg', 1),
      ('æ.jpg', 'af.jpg', -1),
      ('œ.jpg', 'oe.jpg', 1),
      ('ı.jpg', 'i.jpg', 1),
      ('ı.jpg', 'j.jpg', -1),
      ('ё.jpg', 'е.jpg', 1),
      ('ё.jpg', 'ж.jpg', -1),
      ('й.jpg', 'и.jpg', 1),
      ('й.jpg', 'к.jpg', -1),
      ('Ё.jpg', 'ё.jpg', 1),
      ('ß.jpg', 'st.jpg', -1),
      ('ẞ.jpg', 'ß.jpg', 1),
      ('a b.jpg', 'a_b.jpg', -1),
      ('a~b.jpg', 'a\$b.jpg', -1),
      ('a\$b.jpg', 'a0b.jpg', -1),
      ('a#b.jpg', 'a%b.jpg', -1),
      ('ñ.jpg', 'n.jpg', 1),
      ('ñ.jpg', 'o.jpg', -1),
      ('ç.jpg', 'c.jpg', 1),
      ('þ.jpg', 'z.jpg', 1),
      ('ð.jpg', 'd.jpg', 1),
      ('ð.jpg', 'e.jpg', -1),
      ('ŋ.jpg', 'n.jpg', 1),
      ('ŋ.jpg', 'o.jpg', -1),
      ('α.jpg', 'z.jpg', 1),
      ('α.jpg', 'я.jpg', -1),
      ('ゆ.jpg', 'я.jpg', 1),
      ('١.jpg', '2.jpg', -1),
      ('€.jpg', '\$.jpg', 1),
      ('€.jpg', '0.jpg', -1),
      ('—.jpg', '-.jpg', 1),
      ('—.jpg', '_.jpg', 1),
      ('—.jpg', '.jpg', -1),
      (' a.jpg', ' a.jpg', 1),
      ('©.jpg', 'a.jpg', -1),
      ('©.jpg', '0.jpg', -1),
    ];

    for (final (a, b, sign) in probes) {
      test('orders "$a" ${sign < 0 ? 'before' : 'after'} "$b"', () {
        expect(naturalFilenameCompare(a, b).sign, sign);
        expect(naturalFilenameCompare(b, a).sign, -sign);
      });
    }

    test('non-ASCII digits equal ASCII digits at every level', () {
      // The collator returns 0; the code-unit tie-break decides.
      expect(naturalFilenameCompare('1.jpg', '١.jpg'), lessThan(0));
      expect(naturalFilenameCompare('x١.jpg', 'x2.jpg'), lessThan(0));
    });

    test('compares long numbers by magnitude, not digit by digit', () {
      expect(
        naturalFilenameCompare(
          'page99999999999999999999.jpg',
          'page100000000000000000000.jpg',
        ),
        lessThan(0),
      );
      expect(naturalFilenameCompare('a0.jpg', 'a.jpg'), greaterThan(0));
      expect(naturalFilenameCompare('a.jpg', 'a0.jpg'), lessThan(0));
    });

    test('is a total order: equal names compare equal', () {
      expect(naturalFilenameCompare('x.jpg', 'x.jpg'), 0);
      expect(NaturalSortKey('x.jpg').name, 'x.jpg');
    });
  });

  group('selectComicPages', () {
    const names = [
      'Comic/page10.JPG',
      'Comic/page2.jpg',
      'Comic/page1.png',
      'Comic/cover.webp',
      '__MACOSX/Comic/._page1.png',
      'Comic/._page2.jpg',
      'Comic/notes.txt',
      'Comic/thumbs.db',
      'Comic/',
      'Comic/Extras/bonus.gif',
    ];

    test('version 1 takes any extension case, skips resource forks, '
        'orders naturally', () {
      expect(selectComicPages(names, pageOrderVersion: 1), [
        'Comic/cover.webp',
        'Comic/Extras/bonus.gif',
        'Comic/page1.png',
        'Comic/page2.jpg',
        'Comic/page10.JPG',
      ]);
    });

    test('version 0 keeps the legacy case-sensitive, code-unit order', () {
      expect(selectComicPages(names, pageOrderVersion: 0), [
        'Comic/._page2.jpg',
        'Comic/Extras/bonus.gif',
        'Comic/cover.webp',
        'Comic/page1.png',
        'Comic/page2.jpg',
        '__MACOSX/Comic/._page1.png',
      ]);
    });

    test('throws when no page images are present', () {
      expect(
        () => selectComicPages(['a.txt', 'b/'], pageOrderVersion: 1),
        throwsA(
          isA<PagecraftException>().having(
            (e) => e.message,
            'message',
            'No supported image files in archive',
          ),
        ),
      );
    });

    test('orders a large archive in natural order quickly', () {
      final names = [
        for (var i = 2000; i >= 1; i--) 'Chapter ${i % 7}/Page $i (scan).jpg',
      ];
      final watch = Stopwatch()..start();
      final pages = selectComicPages(names, pageOrderVersion: 1);
      watch.stop();
      expect(pages.first, 'Chapter 0/Page 7 (scan).jpg');
      expect(pages.last, 'Chapter 6/Page 1994 (scan).jpg');
      expect(watch.elapsedMilliseconds, lessThan(200));
    });
  });
}
