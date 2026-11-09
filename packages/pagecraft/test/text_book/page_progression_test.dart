import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/src/text_book/page_progression.dart';
import 'package:pagecraft/src/text_book/text_book_source.dart';

const _arabic = 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ ';
const _latin = 'The reader continues through the next chapter. ';

String _xhtml(String body, {String head = ''}) =>
    '<html xmlns="http://www.w3.org/1999/xhtml"><head>$head</head>'
    '<body>$body</body></html>';

class _Source implements TextBookSource {
  _Source(
    this.markup, {
    this.language,
    this.rtl = false,
    this.isFixedLayout = false,
    this.nonLinear = const {},
    this.failures = const {},
    this.sizes = const {},
    this.mediaType = 'application/xhtml+xml',
  });

  final List<String> markup;
  @override
  final String? language;
  @override
  final bool rtl;
  @override
  final bool isFixedLayout;
  final Set<int> nonLinear;
  final Set<int> failures;
  final Map<int, int> sizes;
  final String mediaType;
  final reads = <int>[];
  var activeReads = 0;
  var peakReads = 0;

  @override
  int get sectionCount => markup.length;

  @override
  bool isLinear(int index) => !nonLinear.contains(index);

  @override
  int sectionSize(int index) =>
      sizes[index] ?? utf8.encode(markup[index]).length;

  @override
  Future<TextSection> section(int index) async {
    reads.add(index);
    activeReads++;
    if (activeReads > peakReads) peakReads = activeReads;
    try {
      await Future<void>.delayed(Duration.zero);
      if (failures.contains(index)) throw StateError('unreadable section');
      return TextSection(
        text: markup[index],
        href: '$index.xhtml',
        mediaType: mediaType,
      );
    } finally {
      activeReads--;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'Malay metadata and Latin front matter do not hide an Arabic book',
    () async {
      final source = _Source([
        _xhtml('Penerbit dan pengenalan. $_latin'),
        for (var index = 1; index < 30; index++) _xhtml(_arabic * 40),
      ], language: 'ms');

      expect(await resolvePageProgressionRtl(source), isTrue);
      expect(source.reads, hasLength(12));
      expect(source.reads.toSet(), hasLength(12));
      expect(source.reads, containsAll([0, 1, 2, 14, 29]));
      expect(
        source.peakReads,
        1,
        reason: 'stateful formats must stay sequential',
      );
    },
  );

  test(
    'English metadata and an LTR source permit the legacy content fallback',
    () async {
      final source = _Source([_xhtml(_arabic * 100)], language: 'en');
      expect(source.rtl, isFalse);
      expect(await resolvePageProgressionRtl(source), isTrue);
    },
  );

  test('an Arabic quotation does not reverse a mostly Latin book', () async {
    final source = _Source([
      _xhtml('${_latin * 80}<p>$_arabic</p>'),
    ], language: 'en');
    expect(await resolvePageProgressionRtl(source), isFalse);
  });

  test(
    'middle and final windows account for Arabic after a long Latin introduction',
    () async {
      final source = _Source([_xhtml('${'A' * 5001}${_arabic * 600}')]);
      expect(await resolvePageProgressionRtl(source), isTrue);
    },
  );

  test('declared RTL returns without reading sections', () async {
    final source = _Source([_xhtml(_latin)], rtl: true, language: 'en');
    expect(await resolvePageProgressionRtl(source), isTrue);
    expect(source.reads, isEmpty);
  });

  for (final language in ['ar', 'he-IL', 'fa_IR', ' ur ']) {
    test('RTL language $language returns without reading sections', () async {
      final source = _Source([_xhtml(_latin)], language: language);
      expect(await resolvePageProgressionRtl(source), isTrue);
      expect(source.reads, isEmpty);
    });
  }

  test(
    'fixed-layout pages retain their declared printed order without sampling',
    () async {
      final source = _Source(
        [_xhtml(_arabic)],
        language: 'ar',
        isFixedLayout: true,
      );
      expect(await resolvePageProgressionRtl(source), isFalse);
      expect(source.reads, isEmpty);
    },
  );

  test('non-linear notes do not change the main reading order', () async {
    final source = _Source(
      [
        _xhtml(_latin),
        _xhtml(_arabic * 200),
        _xhtml(_arabic * 200),
      ],
      nonLinear: {1, 2},
    );
    expect(await resolvePageProgressionRtl(source), isFalse);
    expect(source.reads, [0]);
  });

  test(
    'an unreadable sample does not prevent detecting the remaining book',
    () async {
      final source = _Source(
        [
          _xhtml(_latin),
          _xhtml(_latin),
          _xhtml(_arabic * 100),
        ],
        failures: {1},
      );
      expect(await resolvePageProgressionRtl(source), isTrue);
      expect(source.reads, [0, 1, 2]);
    },
  );

  test(
    'head, script and style contents do not outweigh readable body text',
    () async {
      final source = _Source([
        _xhtml(
          '<script>${_arabic * 100}</script><style>${_arabic * 100}</style>$_latin',
          head: '<title>${_arabic * 100}</title>',
        ),
      ]);
      expect(await resolvePageProgressionRtl(source), isFalse);
    },
  );

  test(
    'malformed XHTML falls back to the same HTML parsing as reading',
    () async {
      final source = _Source(['<html><body><p>${_arabic * 20}']);
      expect(await resolvePageProgressionRtl(source), isTrue);
    },
  );

  test('HTML fragments use their implied body', () async {
    final source = _Source(['<p>$_arabic</p>'], mediaType: 'text/html');
    expect(await resolvePageProgressionRtl(source), isTrue);
  });

  test('known oversized sections are skipped before any read', () async {
    final source = _Source(
      [_xhtml(_latin), _xhtml(_arabic * 20)],
      sizes: {
        0: 512 * 1024 + 1,
      },
    );
    expect(await resolvePageProgressionRtl(source), isTrue);
    expect(source.reads, [1]);
  });

  test(
    'cumulative uncompressed reads stay within the two MiB startup budget',
    () async {
      const limit = 512 * 1024;
      const prefix = '<html><body>';
      const suffix = '</body></html>';
      final markup =
          '$prefix${'A' * (limit - prefix.length - suffix.length)}$suffix';
      final source = _Source(List.filled(12, markup));
      expect(await resolvePageProgressionRtl(source), isFalse);
      expect(source.reads, hasLength(4));
      expect(
        source.reads.fold<int>(
          0,
          (size, index) => size + source.sectionSize(index),
        ),
        2 * 1024 * 1024,
      );
    },
  );

  test(
    'returned markup exceeding its size hint is not parsed or sampled',
    () async {
      final source = _Source(
        [
          _xhtml('ا' * (300 * 1024)),
          _xhtml(_arabic * 20),
        ],
        sizes: {0: 100},
      );
      expect(await resolvePageProgressionRtl(source), isFalse);
      expect(source.reads, [
        0,
      ], reason: 'stop when a source violates the read estimate');
    },
  );

  test('empty and non-alphabetic books keep LTR fallback', () async {
    expect(await resolvePageProgressionRtl(_Source([])), isFalse);
    expect(
      await resolvePageProgressionRtl(_Source([_xhtml('123 — ... !')])),
      isFalse,
    );
  });
}
