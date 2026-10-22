import 'package:domain_models/domain_models.dart';
import 'package:meta/meta.dart';
import 'package:preferences_service/preferences_service.dart';

/// What happens to a row of the comparison; [skip] leaves it as it is.
enum RowAction {
  copyToRight,
  copyToLeft,
  deleteLeft,
  deleteRight,
  skip;

  /// The synchronization's action, `null` for [skip].
  SyncAction? get sync => switch (this) {
    copyToRight => SyncAction.copyToRight,
    copyToLeft => SyncAction.copyToLeft,
    deleteLeft => SyncAction.deleteLeft,
    deleteRight => SyncAction.deleteRight,
    skip => null,
  };

  bool get deletes => this == deleteLeft || this == deleteRight;
}

/// The action a row starts with: what is alone or newer goes to the other
/// side (both ways); one way, the source wins where the sides differ, a
/// newer file on the target side is left for the user to decide, and
/// what the source lacks is deleted only when [deleteMissing] asks.
/// Identical rows and a file against a folder are left alone.
RowAction defaultAction(
  CompareRow row,
  SyncDirection direction, {
  required bool deleteMissing,
}) {
  final state = row.state;
  return switch (direction) {
    SyncDirection.bothWays => switch (state) {
      CompareState.leftOnly || CompareState.leftNewer => RowAction.copyToRight,
      CompareState.rightOnly || CompareState.rightNewer => RowAction.copyToLeft,
      _ => RowAction.skip,
    },
    SyncDirection.leftToRight => switch (state) {
      CompareState.leftOnly ||
      CompareState.leftNewer ||
      CompareState.different => RowAction.copyToRight,
      CompareState.rightOnly when deleteMissing => RowAction.deleteRight,
      _ => RowAction.skip,
    },
    SyncDirection.rightToLeft => switch (state) {
      CompareState.rightOnly ||
      CompareState.rightNewer ||
      CompareState.different => RowAction.copyToLeft,
      CompareState.leftOnly when deleteMissing => RowAction.deleteLeft,
      _ => RowAction.skip,
    },
  };
}

/// The actions a row can take, in the order Space walks them. Deleting
/// is on offer only with [deletions] (the explicit option); a file
/// against a folder can only be left alone.
List<RowAction> allowedActions(CompareRow row, {required bool deletions}) {
  if (row.state == CompareState.conflict) return const [RowAction.skip];
  final onLeft = row.left != null;
  final onRight = row.right != null;
  return [
    if (onLeft) RowAction.copyToRight,
    if (onRight) RowAction.copyToLeft,
    if (deletions && onLeft && !onRight) RowAction.deleteLeft,
    if (deletions && onRight && !onLeft) RowAction.deleteRight,
    RowAction.skip,
  ];
}

/// The next of [allowedActions] after [current], round.
RowAction nextAction(
  CompareRow row,
  RowAction current, {
  required bool deletions,
}) {
  final allowed = allowedActions(row, deletions: deletions);
  final at = allowed.indexOf(current);
  return allowed[(at + 1) % allowed.length];
}

/// Whether the filters of [options] show [row].
bool rowShown(CompareRow row, CompareOptions options) => switch (row.state) {
  CompareState.leftOnly => options.showLeftOnly,
  CompareState.rightOnly => options.showRightOnly,
  CompareState.leftNewer || CompareState.rightNewer => options.showNewer,
  CompareState.different || CompareState.conflict => options.showDifferent,
  CompareState.equal => options.showIdentical,
};

/// Which filter a row counts under.
enum RowGroup { leftOnly, rightOnly, newer, different, identical }

RowGroup groupOf(CompareRow row) => switch (row.state) {
  CompareState.leftOnly => RowGroup.leftOnly,
  CompareState.rightOnly => RowGroup.rightOnly,
  CompareState.leftNewer || CompareState.rightNewer => RowGroup.newer,
  CompareState.different || CompareState.conflict => RowGroup.different,
  CompareState.equal => RowGroup.identical,
};

/// What Synchronize would do with the rows shown.
@immutable
class SyncSummary {
  const SyncSummary({
    this.toRight = 0,
    this.toLeft = 0,
    this.toDelete = 0,
    this.bytes = 0,
    this.overwrites = 0,
  });

  final int toRight;
  final int toLeft;
  final int toDelete;

  /// Bytes the copies write.
  final int bytes;

  /// Copies onto a file that is there: its earlier version is lost.
  final int overwrites;

  bool get isEmpty => toRight == 0 && toLeft == 0 && toDelete == 0;

  /// The summary of the [visible] rows (indexes into [rows]) under
  /// [actionOf].
  factory SyncSummary.of(
    List<CompareRow> rows,
    Iterable<int> visible,
    RowAction Function(int index) actionOf,
  ) {
    var toRight = 0;
    var toLeft = 0;
    var toDelete = 0;
    var bytes = 0;
    var overwrites = 0;
    for (final index in visible) {
      final row = rows[index];
      switch (actionOf(index)) {
        case RowAction.copyToRight:
          toRight++;
          bytes += row.left?.size ?? 0;
          if (row.right != null && !row.isDir) overwrites++;
        case RowAction.copyToLeft:
          toLeft++;
          bytes += row.right?.size ?? 0;
          if (row.left != null && !row.isDir) overwrites++;
        case RowAction.deleteLeft || RowAction.deleteRight:
          toDelete++;
        case RowAction.skip:
          break;
      }
    }
    return SyncSummary(
      toRight: toRight,
      toLeft: toLeft,
      toDelete: toDelete,
      bytes: bytes,
      overwrites: overwrites,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SyncSummary &&
      other.toRight == toRight &&
      other.toLeft == toLeft &&
      other.toDelete == toDelete &&
      other.bytes == bytes &&
      other.overwrites == overwrites;

  @override
  int get hashCode => Object.hash(toRight, toLeft, toDelete, bytes, overwrites);
}
