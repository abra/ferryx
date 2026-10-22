import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// What is wrong with a line of the names editor.
enum NameProblem {
  /// Nothing but spaces.
  empty,

  /// A `/`: a path, not a name.
  separator,

  /// `.`, `..`, or a NUL: no file can be called that.
  invalid,

  /// The same new name as another line.
  duplicate,

  /// The name of an item of the folder that is not being renamed.
  exists,

  /// A line past the last name.
  extra,

  /// A name with no line for it (lines were deleted).
  missing,
}

/// The editor's text read against the names it started from: per line
/// its new name and problem, what changes, how many errors.
@immutable
class NamesCheck extends Equatable {
  NamesCheck({
    required this.originals,
    required this.newNames,
    required this.problems,
    required this.duplicateOf,
    required this.lineCount,
  }) : changed = List.unmodifiable([
         for (var i = 0; i < newNames.length; i++)
           if (problems[i] == null &&
               newNames[i] != null &&
               newNames[i] != originals[i])
             i,
       ]);

  /// The names the items have now, in order.
  final List<String> originals;

  /// The name each original takes: the line as typed when it is the old
  /// name exactly, else trimmed; `null` for a name with no line.
  final List<String?> newNames;

  /// Per row (the longer of the lines and the names), its problem.
  final List<NameProblem?> problems;

  /// For a [NameProblem.duplicate] row, the first other row with its name.
  final Map<int, int> duplicateOf;

  /// Lines that count: a trailing empty line past the names does not.
  final int lineCount;

  int get nameCount => newNames.length;

  bool get linesMatch => lineCount == nameCount;

  int get errors => problems.where((p) => p != null).length;

  /// The rows whose name changes, in order.
  final List<int> changed;

  late final Set<int> _changedRows = changed.toSet();

  /// Whether row [index] renames its item.
  bool changes(int index) => _changedRows.contains(index);

  /// Whether row [index]'s line differs from its name, valid or not.
  bool edited(int index) {
    final name = newNames.elementAtOrNull(index);
    return name != null && name != originals[index];
  }

  bool get canApply => errors == 0 && changed.isNotEmpty;

  /// The first row with a problem, or -1.
  int get firstProblem => problems.indexWhere((p) => p != null);

  @override
  List<Object?> get props => [
    originals,
    newNames,
    problems,
    duplicateOf,
    lineCount,
  ];
}

/// Checks [text], one name per line, against [originals] (the names of
/// the items renamed, in order) and [existing] (the other names of their
/// folder). A line kept exactly as it was renames nothing; another one is
/// trimmed. Empty lines after the last name are a trailing newline, not
/// lines of their own.
NamesCheck checkNames({
  required List<String> originals,
  required String text,
  required Set<String> existing,
}) {
  final lines = text.split('\n');
  while (lines.length > originals.length && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  final rows = lines.length > originals.length
      ? lines.length
      : originals.length;
  final newNames = <String?>[
    for (var i = 0; i < originals.length; i++)
      i >= lines.length
          ? null
          : lines[i] == originals[i]
          ? originals[i]
          : lines[i].trim(),
  ];
  final problems = List<NameProblem?>.filled(rows, null);
  final firstWith = <String, int>{};
  final duplicateOf = <int, int>{};
  for (var i = 0; i < rows; i++) {
    if (i >= originals.length) {
      problems[i] = NameProblem.extra;
      continue;
    }
    final name = newNames[i];
    if (name == null) {
      problems[i] = NameProblem.missing;
      continue;
    }
    final changes = name != originals[i];
    if (name.isEmpty) {
      problems[i] = NameProblem.empty;
    } else if (name.contains('/')) {
      problems[i] = NameProblem.separator;
    } else if (name.contains('\u0000') || name == '.' || name == '..') {
      problems[i] = NameProblem.invalid;
    } else if (changes && existing.contains(name)) {
      problems[i] = NameProblem.exists;
    }
    if (name.isEmpty) continue;
    final first = firstWith[name];
    if (first == null) {
      firstWith[name] = i;
    } else {
      problems[i] ??= NameProblem.duplicate;
      problems[first] ??= NameProblem.duplicate;
      duplicateOf[i] = first;
      duplicateOf.putIfAbsent(first, () => i);
    }
  }
  return NamesCheck(
    originals: originals,
    newNames: List.unmodifiable(newNames),
    problems: List.unmodifiable(problems),
    duplicateOf: Map.unmodifiable(duplicateOf),
    lineCount: lines.length,
  );
}
