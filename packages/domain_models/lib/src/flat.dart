import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import 'file_entry.dart';
import 'listing.dart';

/// The start of a flat view: the folder's header without rows, the walk's
/// generation, and the rows as the walk finds them.
class FlatStart {
  const FlatStart({
    required this.listing,
    required this.generation,
    required this.batches,
  });

  /// The folder's header (free space, the volume); no rows yet.
  final Listing listing;

  /// Tells this walk's rows from an older one's.
  final int generation;

  /// The rows in batches, in the order the walk met them; the last batch
  /// says [FlatBatch.done].
  final Stream<FlatBatch> batches;
}

/// Rows a flat walk found, or its end.
@immutable
class FlatBatch extends Equatable {
  const FlatBatch({
    required this.generation,
    this.entries = const [],
    this.done = false,
    this.count = 0,
    this.capped = false,
  });

  final int generation;

  /// Files, each with [FileEntry.folder] set.
  final List<FileEntry> entries;

  /// The walk ended: no rows come after this batch.
  final bool done;

  /// The rows found so far.
  final int count;

  /// The walk stopped at its cap; the tree holds more.
  final bool capped;

  @override
  List<Object?> get props => [generation, entries, done, count, capped];
}
