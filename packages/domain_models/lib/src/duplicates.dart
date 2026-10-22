import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// Find files with the same contents under [roots].
@immutable
class DuplicatesRequest extends Equatable {
  const DuplicatesRequest({
    required this.roots,
    this.minSize = 1,
    this.nameMask = '',
    this.includeHidden = false,
  });

  final List<String> roots;

  /// Smaller files are left out; empty files always are.
  final int minSize;

  /// A mask (`*.jpg;*.png`); empty for every name.
  final String nameMask;
  final bool includeHidden;

  @override
  List<Object?> get props => [roots, minSize, nameMask, includeHidden];
}

enum DuplicatesPhase {
  /// Walking the folders.
  scanning,

  /// Hashing the start of the files that share a size.
  comparing,

  /// Hashing whole files that still look alike.
  hashing,
}

@immutable
class DuplicateFile extends Equatable {
  const DuplicateFile({required this.path, this.modified});

  final String path;
  final DateTime? modified;

  String get name {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  String get parentPath {
    final slash = path.lastIndexOf('/');
    return slash <= 0 ? '/' : path.substring(0, slash);
  }

  @override
  List<Object?> get props => [path, modified];
}

/// Files with the same contents.
@immutable
class DuplicateGroup extends Equatable {
  const DuplicateGroup({required this.size, required this.files});

  final int size;
  final List<DuplicateFile> files;

  /// What removing all copies but one frees.
  int get wasted => size * (files.length - 1);

  @override
  List<Object?> get props => [size, files];
}

/// What a running search says: its phase and counts, the groups settled
/// since the last update, whether it ended.
@immutable
class DuplicatesUpdate extends Equatable {
  const DuplicatesUpdate({
    required this.taskId,
    this.phase,
    this.filesScanned = 0,
    this.candidates = 0,
    this.filesHashed = 0,
    this.bytesDone = 0,
    this.current,
    this.groups = const [],
    this.done = false,
    this.error,
  });

  final int taskId;
  final DuplicatesPhase? phase;
  final int filesScanned;

  /// Files that share their size with another.
  final int candidates;
  final int filesHashed;

  /// Bytes read so far, starts and whole files.
  final int bytesDone;
  final String? current;
  final List<DuplicateGroup> groups;
  final bool done;

  /// Why the search could not run (a bad mask).
  final String? error;

  @override
  List<Object?> get props => [
    taskId,
    phase,
    filesScanned,
    candidates,
    filesHashed,
    bytesDone,
    current,
    groups,
    done,
    error,
  ];
}
