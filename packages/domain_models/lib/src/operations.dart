import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

enum OpKind {
  copy,
  move,
  delete,
  trash,
  duplicate,
  compress,

  /// Members of an archive copied out to a folder.
  extract,

  /// The sizes of folders, for the panel.
  calcSizes,

  // ─── Operations stream ───

  /// Two folders made alike: copies both ways, deletions to the trash.
  synchronize,

  /// Pairs of files compared byte for byte (Compare Folders).
  compareContents,

  /// A step of the journal undone or redone.
  undo,
  redo,
}

/// What to do when the destination already has the item.
enum ConflictPolicy { ask, overwrite, overwriteOlder, skip, keepBoth }

@immutable
class OperationRequest extends Equatable {
  const OperationRequest({
    required this.kind,
    required this.sources,
    this.archive,
    this.destination,
    this.newName,
    this.conflicts = ConflictPolicy.ask,
    this.preserveAttributes = true,
    this.verify = false,
    this.password,
    this.intoFolders = false,
    this.sourceServer,
    this.destinationServer,
  });

  final OpKind kind;

  /// Paths on disk; for [OpKind.extract], member paths inside [archive],
  /// or archives on disk to extract whole when there is none.
  final List<String> sources;
  final String? archive;

  /// The folder written into (copy, move, extract, compress).
  final String? destination;

  /// Copy As / Move As with one source, or the archive's name.
  final String? newName;
  final ConflictPolicy conflicts;
  final bool preserveAttributes;
  final bool verify;

  /// Compress: an AES-256 password. Extract: the archives' password.
  final String? password;

  /// Extract whole archives ([sources] are archives on disk, no
  /// [archive]): each into a folder named after it.
  final bool intoFolders;

  // ─── Network ───

  /// The server [sources] are on (its key, `sftp://me@host:22`); `null`
  /// on disk.
  final String? sourceServer;

  /// The server [destination] is on; `null` on disk.
  final String? destinationServer;

  /// A server is on one side or both: the operation goes over the
  /// network (copy, move, delete and folder sizes only; never on the undo
  /// journal).
  bool get crossesNetwork => sourceServer != null || destinationServer != null;

  @override
  List<Object?> get props => [
    kind,
    sources,
    archive,
    destination,
    newName,
    conflicts,
    preserveAttributes,
    verify,
    password,
    intoFolders,
    sourceServer,
    destinationServer,
  ];
}

enum OpState {
  scanning,
  running,
  paused,

  /// Waiting for an answer to [OperationProgress.question].
  waiting,
  done,
  doneWithErrors,
  cancelled,
  failed;

  bool get isFinished =>
      this == done ||
      this == doneWithErrors ||
      this == cancelled ||
      this == failed;

  bool get isActive => !isFinished;
}

enum QuestionKind { conflict, error }

enum Answer {
  overwrite,
  overwriteAll,
  overwriteOlderAll,
  skip,
  skipAll,
  keepBoth,
  keepBothAll,
  merge,
  mergeAll,
  retry,
  abort,
}

@immutable
class ConflictSide extends Equatable {
  const ConflictSide({
    required this.path,
    this.size,
    this.modified,
    this.isDir = false,
  });

  final String path;
  final int? size;
  final DateTime? modified;
  final bool isDir;

  @override
  List<Object?> get props => [path, size, modified, isDir];
}

@immutable
class OperationQuestion extends Equatable {
  const OperationQuestion({
    required this.id,
    required this.kind,
    required this.message,
    required this.answers,
    this.source,
    this.existing,
  });

  final int id;
  final QuestionKind kind;
  final String message;
  final List<Answer> answers;
  final ConflictSide? source;
  final ConflictSide? existing;

  @override
  List<Object?> get props => [id, kind, message, answers, source, existing];
}

@immutable
class OperationError extends Equatable {
  const OperationError({required this.path, required this.message});

  final String path;
  final String message;

  @override
  List<Object?> get props => [path, message];
}

@immutable
class FolderSize extends Equatable {
  const FolderSize({required this.path, required this.bytes});

  final String path;
  final int bytes;

  @override
  List<Object?> get props => [path, bytes];
}

/// What an operation reports; every change comes through the service's
/// stream.
@immutable
class OperationProgress extends Equatable {
  const OperationProgress({
    required this.id,
    required this.kind,
    required this.state,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.itemsDone = 0,
    this.itemsTotal = 0,
    this.current = '',
    this.started,
    this.elapsed = Duration.zero,
    this.bytesPerSecond = 0,
    this.errors = const [],
    this.question,
    this.sizes = const [],
    this.resultPath,
    this.sources = const [],
    this.destination,
  });

  final int id;
  final OpKind kind;
  final OpState state;
  final int bytesDone;
  final int bytesTotal;
  final int itemsDone;
  final int itemsTotal;

  /// The item being worked on.
  final String current;
  final DateTime? started;
  final Duration elapsed;
  final int bytesPerSecond;
  final List<OperationError> errors;
  final OperationQuestion? question;

  /// [OpKind.calcSizes]: the folders done so far.
  final List<FolderSize> sizes;

  /// What the operation made: the archive, the duplicate, the copy.
  final String? resultPath;
  final List<String> sources;
  final String? destination;

  /// 0…1 of the work done, by bytes where there are any, else by items.
  double? get fraction {
    if (bytesTotal > 0) return (bytesDone / bytesTotal).clamp(0, 1);
    if (itemsTotal > 0) return (itemsDone / itemsTotal).clamp(0, 1);
    return null;
  }

  /// How long the rest should take at the current speed.
  Duration? get remaining {
    if (bytesPerSecond <= 0 || bytesTotal <= bytesDone) return null;
    return Duration(seconds: (bytesTotal - bytesDone) ~/ bytesPerSecond);
  }

  @override
  List<Object?> get props => [
    id,
    kind,
    state,
    bytesDone,
    bytesTotal,
    itemsDone,
    itemsTotal,
    current,
    started,
    elapsed,
    bytesPerSecond,
    errors,
    question,
    sizes,
    resultPath,
    sources,
    destination,
  ];
}
