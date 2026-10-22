import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// Compare two folder trees (Synchronize Folders).
@immutable
class FolderCompareRequest extends Equatable {
  const FolderCompareRequest({
    required this.left,
    required this.right,
    this.recursive = true,
    this.compareContent = false,
    this.timeTolerance = const Duration(seconds: 1),
    this.nameMask = '',
    this.includeHidden = false,
    this.caseSensitive = false,
  });

  final String left;
  final String right;

  /// Into subfolders; else the top level only.
  final bool recursive;

  /// Files of one size are compared byte for byte; equal contents are
  /// equal whatever their times.
  final bool compareContent;

  /// Times this close count as the same (FAT keeps two seconds).
  final Duration timeTolerance;

  /// A mask for files (`*.jpg;*.png`); empty for every name.
  final String nameMask;
  final bool includeHidden;

  /// Names that differ in case only are different names.
  final bool caseSensitive;

  @override
  List<Object?> get props => [
    left,
    right,
    recursive,
    compareContent,
    timeTolerance,
    nameMask,
    includeHidden,
    caseSensitive,
  ];
}

/// One side of a compared item, as the comparison saw it.
@immutable
class SideInfo extends Equatable {
  const SideInfo({
    required this.size,
    this.modifiedMs,
    this.isDir = false,
    this.isSymlink = false,
  });

  final int size;

  /// Unix milliseconds, kept exact: a synchronization checks the item is
  /// still what was compared.
  final int? modifiedMs;
  final bool isDir;
  final bool isSymlink;

  DateTime? get modified => modifiedMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(modifiedMs!, isUtc: true).toLocal();

  @override
  List<Object?> get props => [size, modifiedMs, isDir, isSymlink];
}

enum CompareState {
  leftOnly,
  rightOnly,
  leftNewer,
  rightNewer,
  equal,

  /// The same time, other sizes or contents: neither is newer.
  different,

  /// A file on one side, a folder (or a link) on the other.
  conflict,
}

/// One compared item. Kept lean: a big tree has a hundred thousand.
@immutable
class CompareRow {
  const CompareRow({
    required this.leftRel,
    required this.rightRel,
    required this.state,
    this.isDir = false,
    this.left,
    this.right,
  });

  /// The path under the left folder, with `/`; where it would go there
  /// for an item on the right only.
  final String leftRel;

  /// The same under the right folder (another spelling when names matched
  /// ignoring case).
  final String rightRel;
  final bool isDir;
  final SideInfo? left;
  final SideInfo? right;
  final CompareState state;

  /// The path the table shows.
  String get path => left != null ? leftRel : rightRel;

  @override
  bool operator ==(Object other) =>
      other is CompareRow &&
      other.leftRel == leftRel &&
      other.rightRel == rightRel &&
      other.isDir == isDir &&
      other.left == left &&
      other.right == right &&
      other.state == state;

  @override
  int get hashCode => Object.hash(leftRel, rightRel, isDir, left, right, state);

  @override
  String toString() => 'CompareRow($leftRel, $state)';
}

@immutable
class CompareError extends Equatable {
  const CompareError({required this.path, required this.message});

  final String path;
  final String message;

  @override
  List<Object?> get props => [path, message];
}

/// What a running comparison says: rows since the last update, where it
/// is, whether it ended.
@immutable
class CompareUpdate extends Equatable {
  const CompareUpdate({
    required this.taskId,
    this.rows = const [],
    this.folders = 0,
    this.files = 0,
    this.bytesCompared = 0,
    this.current,
    this.errors = const [],
    this.done = false,
    this.error,
  });

  final int taskId;
  final List<CompareRow> rows;
  final int folders;
  final int files;
  final int bytesCompared;

  /// The folder being read, relative to the left one.
  final String? current;
  final List<CompareError> errors;
  final bool done;

  /// Why the comparison could not run (a missing folder, a bad mask).
  final String? error;

  @override
  List<Object?> get props => [
    taskId,
    rows,
    folders,
    files,
    bytesCompared,
    current,
    errors,
    done,
    error,
  ];
}

/// What happens to a compared item.
enum SyncAction {
  copyToRight,
  copyToLeft,
  deleteLeft,
  deleteRight;

  bool get deletes => this == deleteLeft || this == deleteRight;
}

/// One item to synchronize: a compared row and what to do with it.
@immutable
class SyncItem extends Equatable {
  const SyncItem({required this.row, required this.action});

  final CompareRow row;
  final SyncAction action;

  @override
  List<Object?> get props => [row, action];
}

/// What Synchronize carries out.
@immutable
class SyncPlan extends Equatable {
  const SyncPlan({
    required this.left,
    required this.right,
    required this.recursive,
    required this.items,
    this.preserveAttributes = true,
    this.verify = false,
  });

  final String left;
  final String right;

  /// The comparison went into subfolders: a folder row stands for the
  /// folder alone.
  final bool recursive;
  final List<SyncItem> items;
  final bool preserveAttributes;
  final bool verify;

  @override
  List<Object?> get props => [
    left,
    right,
    recursive,
    items,
    preserveAttributes,
    verify,
  ];
}

/// Two files to compare byte for byte (Compare Folders by contents).
@immutable
class ContentPair extends Equatable {
  const ContentPair({required this.left, required this.right});

  final String left;
  final String right;

  @override
  List<Object?> get props => [left, right];
}
