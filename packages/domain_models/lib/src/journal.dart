import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// What a step of the undo journal did, for "Undo Move of 3 items".
enum StepKind {
  copy,
  move,
  trash,
  rename,
  createFolder,
  createFile,
  createLink,
  duplicate,
  compress,
  extract,
  synchronize,
}

/// One step of the journal: what undo or redo would act on.
@immutable
class StepSummary extends Equatable {
  const StepSummary({
    required this.id,
    required this.kind,
    required this.items,
    required this.firstName,
    this.partial = false,
    this.at,
  });

  final int id;
  final StepKind kind;

  /// How many items the user acted on.
  final int items;

  /// The first of them, by name.
  final String firstName;

  /// Some items were overwritten: undo cannot bring their earlier contents
  /// back.
  final bool partial;
  final DateTime? at;

  @override
  List<Object?> get props => [id, kind, items, firstName, partial, at];
}

/// What undo and redo would do next; `null` where there is nothing.
@immutable
class JournalSummary extends Equatable {
  const JournalSummary({this.undo, this.redo});

  static const empty = JournalSummary();

  final StepSummary? undo;
  final StepSummary? redo;

  @override
  List<Object?> get props => [undo, redo];
}

/// Why a change of a step cannot be walked back as it was.
enum UndoIssueKind {
  /// The item is gone (deleted or moved away since).
  missing,

  /// The place it goes back to is taken.
  occupied,

  /// It changed since; it still goes (a warning).
  changed,

  /// The step overwrote it: its earlier contents are gone (a warning).
  lost,

  /// The trashed item is no longer in the trash.
  notInTrash,

  /// Items cannot be put back from the trash on this desktop.
  unsupported,

  /// The step changed more items than the journal keeps.
  truncated,
}

@immutable
class UndoIssue extends Equatable {
  const UndoIssue({
    required this.kind,
    required this.path,
    required this.blocks,
  });

  final UndoIssueKind kind;
  final String path;

  /// Whether the change is left out; else it is a warning.
  final bool blocks;

  @override
  List<Object?> get props => [kind, path, blocks];
}

/// A look at the step undo (or redo) would take, against the disk.
@immutable
class UndoCheck extends Equatable {
  const UndoCheck({
    required this.step,
    this.issues = const [],
    this._issuesTotal,
    required this.doable,
    required this.total,
  });

  final StepSummary step;

  /// The first issues found; [issuesTotal] counts them all.
  final List<UndoIssue> issues;
  final int? _issuesTotal;

  int get issuesTotal => _issuesTotal ?? issues.length;

  /// Changes that can be walked back, of [total].
  final int doable;
  final int total;

  /// Nothing of the step can be done any more.
  bool get nothingDoable => doable == 0 && issues.any((i) => i.blocks);

  /// Everything goes as it was, with no warning.
  bool get clean => issues.isEmpty;

  @override
  List<Object?> get props => [step, issues, issuesTotal, doable, total];
}
