/// Byte scans of a MOBI 6 text stream for the tags `mobi.js` finds with
/// regular expressions over a Latin-1 view of the whole book. The scans
/// match exactly what those expressions match, offsets included, without
/// building the string: a RegExp over a few megabytes of text took most
/// of a book's opening time.
library;

import 'dart:typed_data';

const _lt = 0x3C; // <
const _gt = 0x3E; // >

/// Where each `<\s*(?:mbp:)?pagebreak[^>]*>` (case-insensitive) starts
/// in [bytes], matches not overlapping.
List<int> mobiPagebreakStarts(Uint8List bytes) {
  final starts = <int>[];
  final length = bytes.length;
  for (var i = 0; i < length; i++) {
    if (bytes[i] != _lt) continue;
    var at = i + 1;
    while (at < length && _isSpace(bytes[at])) {
      at++;
    }
    if (_startsWith(bytes, at, 'mbp:')) at += 4;
    if (!_startsWith(bytes, at, 'pagebreak')) continue;
    final end = bytes.indexOf(_gt, at + 9);
    // Without a later `>` no tag after this one can close either.
    if (end < 0) break;
    starts.add(i);
    i = end;
  }
  return starts;
}

/// The digits of each `<[^<>]+filepos=['"]{0,1}(\d+)[^<>]*>`
/// (case-insensitive) in [bytes], as written, in order: in a tag naming
/// `filepos=` twice the regex backtracks to the last one with digits.
List<String> mobiFileposValues(Uint8List bytes) {
  final values = <String>[];
  final length = bytes.length;
  for (var i = 0; i < length; i++) {
    if (bytes[i] != _lt) continue;
    var end = i + 1;
    while (end < length && bytes[end] != _lt && bytes[end] != _gt) {
      end++;
    }
    if (end == length) break;
    if (bytes[end] == _lt) {
      i = end - 1;
      continue;
    }
    // At least one character before `filepos=` and a digit after it.
    for (var at = end - 9; at >= i + 2; at--) {
      if (!_startsWith(bytes, at, 'filepos=')) continue;
      var from = at + 8;
      if (bytes[from] == 0x22 || bytes[from] == 0x27) from++;
      var to = from;
      while (to < end && _isDigit(bytes[to])) {
        to++;
      }
      if (to == from) continue;
      values.add(String.fromCharCodes(bytes, from, to));
      break;
    }
    i = end;
  }
  return values;
}

/// Where an anchor for a `filepos` at [offset] goes: before the tag that
/// [offset] falls inside, or at [offset]. `mobi.js` inserts it where the
/// offset points, and inside a tag the `<a>` breaks it: the rest of the
/// tag shows as text and a browser can lose the paragraphs after it.
/// KindleUnpack moves it out the same way.
int mobiAnchorOffset(Uint8List bytes, int offset) {
  for (var i = offset - 1; i >= 0; i--) {
    final byte = bytes[i];
    if (byte == _gt) return offset;
    if (byte == _lt) return i;
  }
  return offset;
}

/// Whether [pattern] (lower case ASCII) is at [at], letters in any case.
bool _startsWith(Uint8List bytes, int at, String pattern) {
  if (at + pattern.length > bytes.length) return false;
  for (var k = 0; k < pattern.length; k++) {
    final unit = pattern.codeUnitAt(k);
    final byte = bytes[at + k];
    final isLetter = unit >= 0x61 && unit <= 0x7A;
    if ((isLetter ? byte | 0x20 : byte) != unit) return false;
  }
  return true;
}

/// `\s` over Latin-1: tab to carriage return, space and no-break space.
bool _isSpace(int byte) =>
    (byte >= 0x09 && byte <= 0x0D) || byte == 0x20 || byte == 0xA0;

bool _isDigit(int byte) => byte >= 0x30 && byte <= 0x39;
