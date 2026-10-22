import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:sync_feature/sync_feature.dart';

const _left = SideInfo(size: 10, modifiedMs: 2000);
const _right = SideInfo(size: 20, modifiedMs: 1000);

CompareRow row(CompareState state, {bool left = true, bool right = true}) =>
    CompareRow(
      leftRel: 'a.txt',
      rightRel: 'a.txt',
      state: state,
      left: left ? _left : null,
      right: right ? _right : null,
    );

void main() {
  group('defaultAction', () {
    test('both ways: what is alone or newer crosses over', () {
      RowAction both(CompareRow r) =>
          defaultAction(r, SyncDirection.bothWays, deleteMissing: true);
      expect(
        both(row(CompareState.leftOnly, right: false)),
        RowAction.copyToRight,
      );
      expect(
        both(row(CompareState.rightOnly, left: false)),
        RowAction.copyToLeft,
      );
      expect(both(row(CompareState.leftNewer)), RowAction.copyToRight);
      expect(both(row(CompareState.rightNewer)), RowAction.copyToLeft);
      expect(both(row(CompareState.equal)), RowAction.skip);
      expect(both(row(CompareState.different)), RowAction.skip);
      expect(both(row(CompareState.conflict)), RowAction.skip);
    });

    test('one way: the source wins; deletions only when asked', () {
      RowAction mirror(CompareRow r, {bool delete = false}) =>
          defaultAction(r, SyncDirection.leftToRight, deleteMissing: delete);
      expect(
        mirror(row(CompareState.leftOnly, right: false)),
        RowAction.copyToRight,
      );
      expect(mirror(row(CompareState.different)), RowAction.copyToRight);
      // A newer file on the target side is the user's to decide.
      expect(mirror(row(CompareState.rightNewer)), RowAction.skip);
      final rightOnly = row(CompareState.rightOnly, left: false);
      expect(mirror(rightOnly), RowAction.skip);
      expect(mirror(rightOnly, delete: true), RowAction.deleteRight);

      RowAction back(CompareRow r) =>
          defaultAction(r, SyncDirection.rightToLeft, deleteMissing: true);
      expect(
        back(row(CompareState.leftOnly, right: false)),
        RowAction.deleteLeft,
      );
      expect(back(row(CompareState.rightNewer)), RowAction.copyToLeft);
      expect(back(row(CompareState.leftNewer)), RowAction.skip);
    });
  });

  group('allowedActions and nextAction', () {
    test('deleting is on offer only with the option', () {
      final leftOnly = row(CompareState.leftOnly, right: false);
      expect(allowedActions(leftOnly, deletions: false), [
        RowAction.copyToRight,
        RowAction.skip,
      ]);
      expect(allowedActions(leftOnly, deletions: true), [
        RowAction.copyToRight,
        RowAction.deleteLeft,
        RowAction.skip,
      ]);
      expect(allowedActions(row(CompareState.leftNewer), deletions: true), [
        RowAction.copyToRight,
        RowAction.copyToLeft,
        RowAction.skip,
      ]);
      expect(allowedActions(row(CompareState.conflict), deletions: true), [
        RowAction.skip,
      ]);
    });

    test('Space walks round', () {
      final both = row(CompareState.different);
      var action = RowAction.skip;
      final seen = <RowAction>[];
      for (var i = 0; i < 4; i++) {
        action = nextAction(both, action, deletions: false);
        seen.add(action);
      }
      expect(seen, [
        RowAction.copyToRight,
        RowAction.copyToLeft,
        RowAction.skip,
        RowAction.copyToRight,
      ]);
      // An action the row cannot take (a deletion after the option went
      // off) walks on from the start.
      expect(
        nextAction(both, RowAction.deleteLeft, deletions: false),
        RowAction.copyToRight,
      );
    });
  });

  test('rowShown follows the filters, groupOf counts them', () {
    const options = CompareOptions();
    expect(rowShown(row(CompareState.equal), options), isFalse);
    expect(
      rowShown(row(CompareState.equal), options.copyWith(showIdentical: true)),
      isTrue,
    );
    expect(
      rowShown(
        row(CompareState.conflict),
        options.copyWith(showDifferent: false),
      ),
      isFalse,
    );
    expect(groupOf(row(CompareState.rightNewer)), RowGroup.newer);
    expect(groupOf(row(CompareState.conflict)), RowGroup.different);
  });

  test('SyncSummary counts the copies, bytes, overwrites and deletions', () {
    final rows = [
      row(CompareState.leftOnly, right: false),
      row(CompareState.leftNewer),
      row(CompareState.rightOnly, left: false),
      row(CompareState.equal),
    ];
    final actions = [
      RowAction.copyToRight,
      RowAction.copyToRight,
      RowAction.deleteRight,
      RowAction.skip,
    ];
    final summary = SyncSummary.of(rows, [0, 1, 2, 3], (i) => actions[i]);
    expect(summary.toRight, 2);
    expect(summary.toLeft, 0);
    expect(summary.toDelete, 1);
    expect(summary.bytes, 20);
    expect(summary.overwrites, 1);
    expect(summary.isEmpty, isFalse);
    // Only the rows shown count.
    expect(SyncSummary.of(rows, [3], (i) => actions[i]).isEmpty, isTrue);
  });
}
