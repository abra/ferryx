import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/testing.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  group('variable-length integers', () {
    test('read forward: seven bits per byte, the high bit ends', () {
      expect(readVarLen(Uint8List.fromList([0x85])), (value: 5, length: 1));
      expect(readVarLen(Uint8List.fromList([0x01, 0x80])), (
        value: 128,
        length: 2,
      ));
      expect(
        readVarLen(Uint8List.fromList([0x7F, 0x7F, 0x7F, 0x7F, 0x01]), 0),
        (value: 0x0FFFFFFF, length: 4),
        reason: 'at most four bytes are read',
      );
      expect(readVarLen(Uint8List.fromList([0, 0x81]), 1), (
        value: 1,
        length: 1,
      ));
    });

    test('read from the end: the high bit starts the value', () {
      expect(readVarLenFromEnd(Uint8List.fromList([1, 2, 0x83])), 3);
      expect(readVarLenFromEnd(Uint8List.fromList([0x81, 0x02])), 130);
      expect(readVarLenFromEnd(Uint8List.fromList([0x7F, 0x81, 0x02])), 130);
    });

    test('bit helpers', () {
      expect(countBitsSet(0), 0);
      expect(countBitsSet(11), 3);
      expect(countUnsetEnd(8), 3);
      expect(countUnsetEnd(1), 0);
    });
  });

  group('trailing entries', () {
    test('strips one entry per flag bit, then the multibyte overlap', () {
      final record = Uint8List.fromList([
        ...'text'.codeUnits,
        0xAB, 0xC1, // multibyte overlap: last byte & 3 = 1, so 2 bytes
        0x81, // one trailing entry: its length (1) counts its own byte
      ]);
      // Flags: bit 1 set (one entry), bit 0 set (multibyte). The entry
      // goes first, then the overlap.
      final stripped = removeTrailingEntries(record, 3);
      expect(String.fromCharCodes(stripped), 'text');
    });

    test('a size past the start leaves nothing, as subarray clamps', () {
      // A two-byte record whose trailing size reads 0x41 (65).
      final record = Uint8List.fromList([0x61, 0xC1]);
      expect(removeTrailingEntries(record, 2), isEmpty);
      expect(removeTrailingEntries(Uint8List(0), 3), isEmpty);
    });

    test('no flags leaves the record alone', () {
      final record = Uint8List.fromList('abc'.codeUnits);
      expect(removeTrailingEntries(record, 0), record);
    });
  });

  group('PalmDOC', () {
    test('decodes literals, runs, back references and space pairs', () {
      // "ab ab ab" → literal a, b, then " a" as a space pair (0xE1),
      // then a back reference.
      final decoded = decompressPalmDoc(
        // The pair 0x8018: distance 3, length 3.
        Uint8List.fromList([0x61, 0x62, 0xE1, 0x62, 0x80, 0x18]),
      );
      expect(String.fromCharCodes(decoded), 'ab ab ab');
    });

    test('a literal run copies the next bytes verbatim', () {
      final decoded = decompressPalmDoc(
        Uint8List.fromList([3, 0xC3, 0xA9, 0x01, 0x41]),
      );
      expect(decoded, [0xC3, 0xA9, 0x01, 0x41]);
    });

    test('round-trips through the test compressor on text and binary', () {
      final random = Random(3);
      final samples = <Uint8List>[
        Uint8List.fromList(
          ('The quick brown fox jumps over the lazy dog. ' * 40).codeUnits,
        ),
        Uint8List.fromList(
          '<p>Привет, мир &amp; друзья</p>'.codeUnits
              .expand((c) => c > 255 ? [c >> 8, c & 0xFF] : [c])
              .toList(),
        ),
        Uint8List.fromList(List.generate(5000, (_) => random.nextInt(256))),
        Uint8List(0),
        Uint8List.fromList([0, 0, 0, 1, 2, 3]),
      ];
      for (final sample in samples) {
        final compressed = compressPalmDoc(sample);
        expect(decompressPalmDoc(compressed), sample);
      }
    });

    test('a truncated back reference stops cleanly', () {
      expect(decompressPalmDoc(Uint8List.fromList([0x61, 0x80])), [0x61]);
    });
  });

  group('HTML entities', () {
    test('decodes numeric and the common named references', () {
      expect(
        unescapeHtml('A &amp; B &lt;C&gt; &#8212; &#x2014; &mdash; &nbsp;x'),
        'A & B <C> — — —  x',
      );
      expect(unescapeHtml('&unknown; &#xZZ; &amp'), '&unknown; &#xZZ; &amp');
      expect(unescapeHtml(null), '');
      expect(unescapeHtml('plain'), 'plain');
      expect(unescapeHtml('&#55296;'), '�');
    });
  });
}
