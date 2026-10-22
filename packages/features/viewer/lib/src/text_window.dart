import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// A match of the find query: a line (a hex row in hex mode) and the
/// span inside it, in UTF-16 code units (bytes in hex mode).
@immutable
class ViewerMatch extends Equatable {
  const ViewerMatch({
    required this.line,
    required this.start,
    required this.end,
  });

  final int line;
  final int start;
  final int end;

  @override
  List<Object?> get props => [line, start, end];
}

/// A window of bytes read as text: its lines (without their line ends)
/// and where each starts, as a byte offset into the window.
@immutable
class DecodedWindow {
  const DecodedWindow({
    required this.lines,
    required this.lineStarts,
    required this.binary,
  });

  static const empty = DecodedWindow(lines: [], lineStarts: [], binary: false);

  final List<String> lines;
  final List<int> lineStarts;

  /// Enough NUL bytes that the bytes are not text.
  final bool binary;
}

/// Decodes [bytes] as UTF-8, leniently, and splits them into lines. A
/// line feed is one byte in UTF-8 and never part of another character,
/// so the starts are read from the bytes and agree with the lines.
DecodedWindow decodeWindow(Uint8List bytes) {
  if (bytes.isEmpty) return DecodedWindow.empty;
  final starts = <int>[0];
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] == 0x0A) starts.add(i + 1);
  }
  final text = utf8.decode(bytes, allowMalformed: true);
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].endsWith('\r')) {
      lines[i] = lines[i].substring(0, lines[i].length - 1);
    }
  }
  // A window that ends in a line feed starts a line that holds nothing
  // yet; keep it so its number is right, as editors do.
  return DecodedWindow(
    lines: lines,
    lineStarts: lines.length == starts.length
        ? starts
        : List.generate(
            lines.length,
            (i) => i < starts.length ? starts[i] : bytes.length,
          ),
    binary: looksBinary(bytes),
  );
}

/// Whether the first bytes hold NUL characters, as no text does.
bool looksBinary(Uint8List bytes) {
  final sample = bytes.length < 4096 ? bytes.length : 4096;
  var nulls = 0;
  for (var i = 0; i < sample; i++) {
    if (bytes[i] == 0) nulls++;
  }
  return nulls > 0 && (nulls >= 4 || nulls * 200 > sample);
}

/// Every place [query] appears in [lines], case-insensitively.
List<ViewerMatch> findInLines(List<String> lines, String query) {
  if (query.isEmpty) return const [];
  final needle = query.toLowerCase();
  final out = <ViewerMatch>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].toLowerCase();
    var from = 0;
    while (true) {
      final at = line.indexOf(needle, from);
      if (at < 0) break;
      out.add(ViewerMatch(line: i, start: at, end: at + needle.length));
      from = at + needle.length;
    }
  }
  return out;
}

/// Every place [query] (as UTF-8) appears in [bytes], ASCII letters
/// compared without case; a match names its first hex row and the
/// columns there, cut at the row's end.
List<ViewerMatch> findInBytes(
  Uint8List bytes,
  String query, {
  int rowLength = 16,
}) {
  if (query.isEmpty) return const [];
  final needle = utf8.encode(query);
  if (needle.isEmpty || needle.length > bytes.length) return const [];
  final out = <ViewerMatch>[];
  final last = bytes.length - needle.length;
  for (var i = 0; i <= last; i++) {
    var hit = true;
    for (var j = 0; j < needle.length; j++) {
      if (_fold(bytes[i + j]) != _fold(needle[j])) {
        hit = false;
        break;
      }
    }
    if (!hit) continue;
    final row = i ~/ rowLength;
    final start = i % rowLength;
    final end = start + needle.length;
    out.add(
      ViewerMatch(
        line: row,
        start: start,
        end: end > rowLength ? rowLength : end,
      ),
    );
  }
  return out;
}

int _fold(int byte) => byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte;

/// Groups [matches] by their line, in order.
Map<int, List<ViewerMatch>> matchesByLine(List<ViewerMatch> matches) {
  final out = <int, List<ViewerMatch>>{};
  for (final match in matches) {
    (out[match.line] ??= []).add(match);
  }
  return out;
}

/// What the Go To dialog typed: a byte offset (`4096`, `0x1000`) or a
/// share of the file (`50%`); -1 when it reads as neither.
int parseGoTo(String input, int size) {
  final text = input.trim().replaceAll(' ', '');
  if (text.isEmpty) return -1;
  if (text.endsWith('%')) {
    final percent = double.tryParse(text.substring(0, text.length - 1));
    if (percent == null || percent < 0 || percent > 100) return -1;
    return (size * percent / 100).floor();
  }
  final value = text.toLowerCase().startsWith('0x')
      ? int.tryParse(text.substring(2), radix: 16)
      : int.tryParse(text);
  if (value == null || value < 0) return -1;
  return value > size ? size : value;
}

/// Whether [name] is a picture the preview can show.
bool isImageName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return false;
  const kinds = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
  return kinds.contains(name.substring(dot + 1).toLowerCase());
}
