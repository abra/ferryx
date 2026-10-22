import 'package:domain_models/domain_models.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// A tab's flat view: every file under its folder in one list, each row
/// with its folder relative to the tab's (`FileEntry.folder`).
///
/// The first walk shows its rows as they come, in the order the walk met
/// them, and sorts them when it ends. A walk again (⌘R, a change in the
/// folder, the hidden files shown or not) keeps the rows shown and gathers
/// the new ones in [pending] until it ends, so nothing flickers; the cursor
/// and the selection stay on their rows by their keys.
@immutable
class FlatView extends Equatable {
  const FlatView({
    required this.generation,
    this.walking = true,
    this.refreshing = false,
    this.count = 0,
    this.capped = false,
    this.walked = const [],
    this.pending = const [],
    this.again = false,
  });

  /// The walk the rows come from; older walks' rows are dropped.
  final int generation;

  /// The first walk is under way: its rows show as they come.
  final bool walking;

  /// A walk again is under way: its rows wait in [pending].
  final bool refreshing;

  /// The rows the walk found so far (the `..` row included).
  final int count;

  /// The walk stopped at its cap; the tree holds more.
  final bool capped;

  /// The rows in the order the walk sent them: the core answers a sort
  /// as indices into this list.
  final List<FileEntry> walked;

  /// A walk again's rows, in walk order, until it ends.
  final List<FileEntry> pending;

  /// The folder changed while a walk again was under way: one more walk
  /// follows when it ends.
  final bool again;

  /// A walk is under way.
  bool get busy => walking || refreshing;

  FlatView copyWith({
    bool? walking,
    bool? refreshing,
    int? count,
    bool? capped,
    List<FileEntry>? walked,
    List<FileEntry>? pending,
    bool? again,
  }) => FlatView(
    generation: generation,
    walking: walking ?? this.walking,
    refreshing: refreshing ?? this.refreshing,
    count: count ?? this.count,
    capped: capped ?? this.capped,
    walked: walked ?? this.walked,
    pending: pending ?? this.pending,
    again: again ?? this.again,
  );

  @override
  List<Object?> get props => [
    generation,
    walking,
    refreshing,
    count,
    capped,
    walked,
    pending,
    again,
  ];
}
