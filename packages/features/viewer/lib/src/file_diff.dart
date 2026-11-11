import 'dart:convert';
import 'dart:typed_data';

import 'package:diff_match_patch/diff_match_patch.dart';

enum FileDiffKind { equal, added, removed, changed }

enum FileDiffFailure { tooLarge, binary }

class FileDiffRow {
  const FileDiffRow(
    this.kind,
    this.left,
    this.right,
    this.leftNumber,
    this.rightNumber,
  );
  final FileDiffKind kind;
  final String? left, right;
  final int? leftNumber, rightNumber;
}

class FileDiff {
  const FileDiff({
    required this.rows,
    required this.changes,
    required this.identicalBytes,
    this.failure,
  });
  static const maxBytes = 4 * 1024 * 1024;
  static const maxLines = 25000;
  static const maxLineLength = 16384;
  final List<FileDiffRow> rows;
  final List<int> changes;
  final bool identicalBytes;
  final FileDiffFailure? failure;
}

/// Bounded line-level Myers diff, run in a worker isolate by the viewer.
/// Each distinct line becomes one token, avoiding character-level work on
/// multi-megabyte inputs. The library's deadline bounds pathological edits.
FileDiff compareFileBytes((Uint8List, Uint8List) input) {
  final (leftBytes, rightBytes) = input;
  bool sameBytes() {
    if (leftBytes.length != rightBytes.length) return false;
    for (var i = 0; i < leftBytes.length; i++) {
      if (leftBytes[i] != rightBytes[i]) return false;
    }
    return true;
  }

  final identical = sameBytes();
  FileDiff failed(FileDiffFailure failure) => FileDiff(
    rows: const [],
    changes: const [],
    identicalBytes: identical,
    failure: failure,
  );
  if (leftBytes.length > FileDiff.maxBytes ||
      rightBytes.length > FileDiff.maxBytes) {
    return failed(FileDiffFailure.tooLarge);
  }
  String decode(Uint8List bytes) {
    final text = utf8.decode(bytes);
    if (text.contains('\u0000')) throw const FormatException('binary');
    return text.replaceFirst(RegExp(r'^\uFEFF'), '').replaceAll('\r\n', '\n');
  }

  final String left, right;
  try {
    left = decode(leftBytes);
    right = decode(rightBytes);
  } on FormatException {
    return failed(FileDiffFailure.binary);
  }
  List<String> lines(String text) => text.isEmpty ? [] : text.split('\n');
  final leftLines = lines(left), rightLines = lines(right);
  if (leftLines.length > FileDiff.maxLines ||
      rightLines.length > FileDiff.maxLines ||
      leftLines.any((line) => line.length > FileDiff.maxLineLength) ||
      rightLines.any((line) => line.length > FileDiff.maxLineLength)) {
    return failed(FileDiffFailure.tooLarge);
  }
  final tokens = <String, int>{};
  String encode(List<String> lines) => String.fromCharCodes([
    for (final line in lines) tokens.putIfAbsent(line, () => tokens.length + 1),
  ]);
  final encodedLeft = encode(leftLines), encodedRight = encode(rightLines);
  final edits = (DiffMatchPatch()..diffTimeout = 2).diff(
    encodedLeft,
    encodedRight,
    false,
  );
  final rows = <FileDiffRow>[];
  final changes = <int>[];
  var leftAt = 0, rightAt = 0;
  final removed = <int>[], added = <int>[];
  void flush() {
    if (removed.isEmpty && added.isEmpty) return;
    changes.add(rows.length);
    final count = removed.length > added.length ? removed.length : added.length;
    for (var i = 0; i < count; i++) {
      final l = i < removed.length ? removed[i] : null;
      final r = i < added.length ? added[i] : null;
      rows.add(
        FileDiffRow(
          l == null
              ? FileDiffKind.added
              : r == null
              ? FileDiffKind.removed
              : FileDiffKind.changed,
          l == null ? null : leftLines[l],
          r == null ? null : rightLines[r],
          l == null ? null : l + 1,
          r == null ? null : r + 1,
        ),
      );
    }
    removed.clear();
    added.clear();
  }

  for (final edit in edits) {
    if (edit.operation == DIFF_EQUAL) {
      flush();
      for (var i = 0; i < edit.text.length; i++) {
        rows.add(
          FileDiffRow(
            FileDiffKind.equal,
            leftLines[leftAt],
            rightLines[rightAt],
            leftAt + 1,
            rightAt + 1,
          ),
        );
        leftAt++;
        rightAt++;
      }
    } else if (edit.operation == DIFF_DELETE) {
      for (var i = 0; i < edit.text.length; i++) {
        removed.add(leftAt++);
      }
    } else {
      for (var i = 0; i < edit.text.length; i++) {
        added.add(rightAt++);
      }
    }
  }
  flush();
  return FileDiff(
    rows: List.unmodifiable(rows),
    changes: List.unmodifiable(changes),
    identicalBytes: identical,
  );
}
