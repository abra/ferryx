import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_feature/src/line_layout.dart';
import 'package:viewer_feature/src/text_window.dart';

Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  group('decodeWindow', () {
    test('splits lines and keeps where each starts', () {
      final window = decodeWindow(bytesOf('one\ntwo\r\nthree'));
      expect(window.lines, ['one', 'two', 'three']);
      expect(window.lineStarts, [0, 4, 9]);
      expect(window.binary, isFalse);
    });

    test('a trailing line feed starts an empty line', () {
      final window = decodeWindow(bytesOf('a\n'));
      expect(window.lines, ['a', '']);
      expect(window.lineStarts, [0, 2]);
    });

    test('malformed bytes read as replacement characters, not errors', () {
      final window = decodeWindow(Uint8List.fromList([0x61, 0xFF, 0x0A, 0x62]));
      expect(window.lines.length, 2);
      expect(window.lines[0], startsWith('a'));
      expect(window.lines[1], 'b');
    });

    test('empty bytes are an empty window', () {
      final window = decodeWindow(Uint8List(0));
      expect(window.lines, isEmpty);
      expect(window.lineStarts, isEmpty);
    });

    test('NUL bytes mean binary', () {
      expect(looksBinary(Uint8List.fromList([1, 0, 0, 0, 0, 2])), isTrue);
      expect(looksBinary(bytesOf('plain text\n')), isFalse);
      expect(looksBinary(Uint8List.fromList([0])), isTrue);
    });
  });

  group('find', () {
    test('in lines, case-insensitively, every occurrence', () {
      final matches = findInLines(['Needle', 'hay', 'needle needle'], 'NEEDLE');
      expect(matches, [
        const ViewerMatch(line: 0, start: 0, end: 6),
        const ViewerMatch(line: 2, start: 0, end: 6),
        const ViewerMatch(line: 2, start: 7, end: 13),
      ]);
      expect(findInLines(['x'], ''), isEmpty);
      expect(matchesByLine(matches)[2]!.length, 2);
      expect(matchesByLine(matches).containsKey(1), isFalse);
    });

    test('in bytes, on hex rows, cut at the row end', () {
      final bytes = bytesOf('0123456789abcdeXYZ');
      final matches = findInBytes(bytes, 'exyz');
      expect(matches, [const ViewerMatch(line: 0, start: 14, end: 16)]);
      expect(findInBytes(bytes, '89ab'), [
        const ViewerMatch(line: 0, start: 8, end: 12),
      ]);
      expect(findInBytes(bytes, 'nope'), isEmpty);
      expect(findInBytes(Uint8List(2), 'long'), isEmpty);
    });
  });

  group('parseGoTo', () {
    test('offsets, hex and percentages', () {
      expect(parseGoTo('100', 1000), 100);
      expect(parseGoTo(' 0x10 ', 1000), 16);
      expect(parseGoTo('50%', 1000), 500);
      expect(parseGoTo('100%', 1000), 1000);
      expect(parseGoTo('5000', 1000), 1000);
      expect(parseGoTo('-1', 1000), -1);
      expect(parseGoTo('abc', 1000), -1);
      expect(parseGoTo('', 1000), -1);
      expect(parseGoTo('120%', 1000), -1);
    });
  });

  group('LineLayout', () {
    test('uniform lines', () {
      final layout = LineLayout.uniform(lineHeight: 10, lines: 5);
      expect(layout.extent, 50);
      expect(layout.offsetOfLine(3), 30);
      expect(layout.lineAtOffset(25), 2);
      expect(layout.lineAtOffset(999), 4);
      expect(layout.heightOfLine(1), 10);
    });

    test('wrapped lines take their rows', () {
      final layout = LineLayout(lineHeight: 10, rowsPerLine: [1, 3, 2]);
      expect(layout.extent, 60);
      expect(layout.offsetOfLine(0), 0);
      expect(layout.offsetOfLine(1), 10);
      expect(layout.offsetOfLine(2), 40);
      expect(layout.heightOfLine(1), 30);
      expect(layout.lineAtOffset(0), 0);
      expect(layout.lineAtOffset(15), 1);
      expect(layout.lineAtOffset(39), 1);
      expect(layout.lineAtOffset(40), 2);
      expect(layout.lineAtOffset(1000), 2);
    });

    test('rows a line takes', () {
      expect(LineLayout.rowsFor(0, 8, 100), 1);
      expect(LineLayout.rowsFor(12, 8, 100), 1);
      expect(LineLayout.rowsFor(13, 8, 100), 2);
      expect(LineLayout.rowsFor(100, 8, 0), 1);
    });
  });

  test('image names', () {
    expect(isImageName('photo.JPG'), isTrue);
    expect(isImageName('notes.txt'), isFalse);
    expect(isImageName('README'), isFalse);
  });
}
