import 'package:domain_models/domain_models.dart';
import 'package:test/test.dart';

void main() {
  group('ChecksumAlgorithm', () {
    test('a checksum file is known by its name, as the core reads it', () {
      expect(
        ChecksumAlgorithm.ofSumsFile('disk.iso.sha256'),
        ChecksumAlgorithm.sha256,
      );
      expect(
        ChecksumAlgorithm.ofSumsFile('SHA256SUMS'),
        ChecksumAlgorithm.sha256,
      );
      expect(
        ChecksumAlgorithm.ofSumsFile('sha1sums.txt'),
        ChecksumAlgorithm.sha1,
      );
      expect(ChecksumAlgorithm.ofSumsFile('MD5SUMS'), ChecksumAlgorithm.md5);
      expect(ChecksumAlgorithm.ofSumsFile('x.md5sum'), ChecksumAlgorithm.md5);
      expect(ChecksumAlgorithm.ofSumsFile('x.b3'), ChecksumAlgorithm.blake3);
      expect(ChecksumAlgorithm.ofSumsFile('B3SUMS'), ChecksumAlgorithm.blake3);
      expect(ChecksumAlgorithm.ofSumsFile('notes.txt'), isNull);
      expect(ChecksumAlgorithm.ofSumsFile('sha256'), isNull);
      expect(ChecksumAlgorithm.ofSumsFile(''), isNull);
    });

    test('a `:checksum` argument names one', () {
      expect(ChecksumAlgorithm.parse('SHA-256'), ChecksumAlgorithm.sha256);
      expect(ChecksumAlgorithm.parse('sha1'), ChecksumAlgorithm.sha1);
      expect(ChecksumAlgorithm.parse(' md5 '), ChecksumAlgorithm.md5);
      expect(ChecksumAlgorithm.parse('b3'), ChecksumAlgorithm.blake3);
      expect(ChecksumAlgorithm.parse('blake3'), ChecksumAlgorithm.blake3);
      expect(ChecksumAlgorithm.parse('crc32'), isNull);
      expect(ChecksumAlgorithm.sha1.hexLength, 40);
    });
  });

  group('the journal', () {
    const step = StepSummary(
      id: 1,
      kind: StepKind.copy,
      items: 2,
      firstName: 'a',
    );

    test('a check counts its issues unless told the total', () {
      const check = UndoCheck(
        step: step,
        issues: [
          UndoIssue(kind: UndoIssueKind.lost, path: '/a', blocks: false),
        ],
        doable: 2,
        total: 2,
      );
      expect(check.issuesTotal, 1);
      expect(check.clean, isFalse);
      expect(check.nothingDoable, isFalse);
      const blocked = UndoCheck(
        step: step,
        issues: [
          UndoIssue(kind: UndoIssueKind.missing, path: '/a', blocks: true),
        ],
        issuesTotal: 40,
        doable: 0,
        total: 1,
      );
      expect(blocked.issuesTotal, 40);
      expect(blocked.nothingDoable, isTrue);
    });
  });

  group('folder comparison', () {
    test('a row shows its left path, the right one when only there', () {
      const left = CompareRow(
        leftRel: 'Docs/a',
        rightRel: 'docs/a',
        state: CompareState.equal,
        left: SideInfo(size: 1),
        right: SideInfo(size: 1),
      );
      const right = CompareRow(
        leftRel: 'x',
        rightRel: 'X',
        state: CompareState.rightOnly,
        right: SideInfo(size: 1, modifiedMs: 0),
      );
      expect(left.path, 'Docs/a');
      expect(right.path, 'X');
      expect(right.right!.modified, DateTime.fromMillisecondsSinceEpoch(0));
      expect(SyncAction.deleteLeft.deletes, isTrue);
      expect(SyncAction.copyToRight.deletes, isFalse);
    });
  });

  test('a duplicate group frees all copies but one', () {
    const group = DuplicateGroup(
      size: 100,
      files: [
        DuplicateFile(path: '/a/x.bin'),
        DuplicateFile(path: '/b/x.bin'),
        DuplicateFile(path: 'x.bin'),
      ],
    );
    expect(group.wasted, 200);
    expect(group.files.first.name, 'x.bin');
    expect(group.files.first.parentPath, '/a');
    expect(group.files.last.parentPath, '/');
  });
}
