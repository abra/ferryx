/// Translation of the Operations stream's bridge types (the undo journal,
/// folder comparison and synchronization, checksums, duplicates) into
/// `domain_models`.
library;

import 'package:domain_models/domain_models.dart' as d;

import 'mapping.dart';
import 'rust/api/checksum.dart' as rust;
import 'rust/api/duplicates.dart' as rust;
import 'rust/api/journal.dart' as rust;
import 'rust/api/sync.dart' as rust;

// ─── The journal ───

d.StepKind stepKindFromView(rust.StepKindView kind) => switch (kind) {
  rust.StepKindView.copy => d.StepKind.copy,
  rust.StepKindView.move => d.StepKind.move,
  rust.StepKindView.trash => d.StepKind.trash,
  rust.StepKindView.rename => d.StepKind.rename,
  rust.StepKindView.createFolder => d.StepKind.createFolder,
  rust.StepKindView.createFile => d.StepKind.createFile,
  rust.StepKindView.createLink => d.StepKind.createLink,
  rust.StepKindView.duplicate => d.StepKind.duplicate,
  rust.StepKindView.compress => d.StepKind.compress,
  rust.StepKindView.extract => d.StepKind.extract,
  rust.StepKindView.synchronize => d.StepKind.synchronize,
};

d.StepSummary stepSummaryFromView(rust.StepSummaryView view) => d.StepSummary(
  id: view.id,
  kind: stepKindFromView(view.kind),
  items: view.items,
  firstName: view.firstName,
  partial: view.partial,
  at: dateTimeFromMs(view.atMs),
);

d.JournalSummary journalSummaryFromView(rust.JournalSummaryView view) =>
    d.JournalSummary(
      undo: view.undo == null ? null : stepSummaryFromView(view.undo!),
      redo: view.redo == null ? null : stepSummaryFromView(view.redo!),
    );

d.UndoIssueKind undoIssueKindFromView(rust.UndoIssueKindView kind) =>
    switch (kind) {
      rust.UndoIssueKindView.missing => d.UndoIssueKind.missing,
      rust.UndoIssueKindView.occupied => d.UndoIssueKind.occupied,
      rust.UndoIssueKindView.changed => d.UndoIssueKind.changed,
      rust.UndoIssueKindView.lost => d.UndoIssueKind.lost,
      rust.UndoIssueKindView.notInTrash => d.UndoIssueKind.notInTrash,
      rust.UndoIssueKindView.unsupported => d.UndoIssueKind.unsupported,
      rust.UndoIssueKindView.truncated => d.UndoIssueKind.truncated,
    };

d.UndoCheck undoCheckFromView(rust.UndoCheckView view) => d.UndoCheck(
  step: stepSummaryFromView(view.step),
  issues: [
    for (final issue in view.issues)
      d.UndoIssue(
        kind: undoIssueKindFromView(issue.kind),
        path: issue.path,
        blocks: issue.blocks,
      ),
  ],
  issuesTotal: view.issuesTotal,
  doable: view.doable,
  total: view.total,
);

// ─── Comparing and synchronizing folders ───

rust.FolderCompareRequestView folderCompareRequestToView(
  d.FolderCompareRequest request,
) => rust.FolderCompareRequestView(
  left: request.left,
  right: request.right,
  recursive: request.recursive,
  compareContent: request.compareContent,
  timeToleranceMs: request.timeTolerance.inMilliseconds,
  nameMask: request.nameMask,
  includeHidden: request.includeHidden,
  caseSensitive: request.caseSensitive,
);

d.SideInfo sideInfoFromView(rust.SideInfoView view) => d.SideInfo(
  size: view.size,
  modifiedMs: view.modifiedMs,
  isDir: view.isDir,
  isSymlink: view.isSymlink,
);

rust.SideInfoView sideInfoToView(d.SideInfo side) => rust.SideInfoView(
  size: side.size,
  modifiedMs: side.modifiedMs,
  isDir: side.isDir,
  isSymlink: side.isSymlink,
);

d.CompareState compareStateFromView(rust.CompareStateView state) =>
    switch (state) {
      rust.CompareStateView.leftOnly => d.CompareState.leftOnly,
      rust.CompareStateView.rightOnly => d.CompareState.rightOnly,
      rust.CompareStateView.leftNewer => d.CompareState.leftNewer,
      rust.CompareStateView.rightNewer => d.CompareState.rightNewer,
      rust.CompareStateView.equal => d.CompareState.equal,
      rust.CompareStateView.different => d.CompareState.different,
      rust.CompareStateView.conflict => d.CompareState.conflict,
    };

d.CompareRow compareRowFromView(rust.CompareRowView view) => d.CompareRow(
  leftRel: view.leftRel,
  rightRel: view.rightRel ?? view.leftRel,
  isDir: view.isDir,
  left: view.left == null ? null : sideInfoFromView(view.left!),
  right: view.right == null ? null : sideInfoFromView(view.right!),
  state: compareStateFromView(view.state),
);

d.CompareUpdate compareUpdateFromView(rust.CompareUpdateView view) =>
    d.CompareUpdate(
      taskId: view.taskId,
      rows: view.rows.map(compareRowFromView).toList(growable: false),
      folders: view.folders,
      files: view.files,
      bytesCompared: view.bytesCompared,
      current: view.current,
      errors: [
        for (final e in view.errors)
          d.CompareError(path: e.path, message: e.message),
      ],
      done: view.done,
      error: view.error,
    );

rust.SyncActionView syncActionToView(d.SyncAction action) => switch (action) {
  d.SyncAction.copyToRight => rust.SyncActionView.copyToRight,
  d.SyncAction.copyToLeft => rust.SyncActionView.copyToLeft,
  d.SyncAction.deleteLeft => rust.SyncActionView.deleteLeft,
  d.SyncAction.deleteRight => rust.SyncActionView.deleteRight,
};

rust.SyncPlanView syncPlanToView(d.SyncPlan plan) => rust.SyncPlanView(
  left: plan.left,
  right: plan.right,
  recursive: plan.recursive,
  preserveAttributes: plan.preserveAttributes,
  verify: plan.verify,
  items: [
    for (final item in plan.items)
      rust.SyncItemView(
        leftRel: item.row.leftRel,
        rightRel: item.row.rightRel == item.row.leftRel
            ? null
            : item.row.rightRel,
        isDir: item.row.isDir,
        action: syncActionToView(item.action),
        left: item.row.left == null ? null : sideInfoToView(item.row.left!),
        right: item.row.right == null ? null : sideInfoToView(item.row.right!),
      ),
  ],
);

// ─── Checksums ───

rust.ChecksumAlgorithmView checksumAlgorithmToView(
  d.ChecksumAlgorithm algorithm,
) => switch (algorithm) {
  d.ChecksumAlgorithm.sha256 => rust.ChecksumAlgorithmView.sha256,
  d.ChecksumAlgorithm.sha1 => rust.ChecksumAlgorithmView.sha1,
  d.ChecksumAlgorithm.md5 => rust.ChecksumAlgorithmView.md5,
  d.ChecksumAlgorithm.blake3 => rust.ChecksumAlgorithmView.blake3,
};

d.ChecksumAlgorithm checksumAlgorithmFromView(
  rust.ChecksumAlgorithmView algorithm,
) => switch (algorithm) {
  rust.ChecksumAlgorithmView.sha256 => d.ChecksumAlgorithm.sha256,
  rust.ChecksumAlgorithmView.sha1 => d.ChecksumAlgorithm.sha1,
  rust.ChecksumAlgorithmView.md5 => d.ChecksumAlgorithm.md5,
  rust.ChecksumAlgorithmView.blake3 => d.ChecksumAlgorithm.blake3,
};

rust.ChecksumRequestView checksumRequestToView(d.ChecksumRequest request) =>
    rust.ChecksumRequestView(
      paths: request.paths,
      base: request.base,
      algorithm: checksumAlgorithmToView(request.algorithm),
      recursive: request.recursive,
      includeHidden: request.includeHidden,
    );

d.ChecksumStatus checksumStatusFromView(rust.ChecksumStatusView status) =>
    switch (status) {
      rust.ChecksumStatusView.ok => d.ChecksumStatus.ok,
      rust.ChecksumStatusView.mismatch => d.ChecksumStatus.mismatch,
      rust.ChecksumStatusView.missing => d.ChecksumStatus.missing,
      rust.ChecksumStatusView.error => d.ChecksumStatus.error,
    };

d.ChecksumUpdate checksumUpdateFromView(rust.ChecksumUpdateView view) =>
    d.ChecksumUpdate(
      taskId: view.taskId,
      algorithm: view.algorithm == null
          ? null
          : checksumAlgorithmFromView(view.algorithm!),
      files: [
        for (final f in view.files)
          d.ChecksumFile(
            index: f.index,
            name: f.name,
            path: f.path,
            size: f.size,
            expected: f.expected,
          ),
      ],
      outcomes: [
        for (final o in view.outcomes)
          d.ChecksumOutcome(
            index: o.index,
            status: checksumStatusFromView(o.status),
            hash: o.hash,
            error: switch (o.error) {
              final e? => d.FerryxException(
                errorKindFromView(e.kind),
                e.message,
                path: e.path,
              ),
              null => null,
            },
          ),
      ],
      filesDone: view.filesDone,
      filesTotal: view.filesTotal,
      bytesDone: view.bytesDone,
      bytesTotal: view.bytesTotal,
      current: view.current,
      badLines: view.badLines,
      done: view.done,
      error: view.error,
    );

// ─── Duplicates ───

rust.DuplicatesRequestView duplicatesRequestToView(
  d.DuplicatesRequest request,
) => rust.DuplicatesRequestView(
  roots: request.roots,
  minSize: request.minSize,
  nameMask: request.nameMask,
  includeHidden: request.includeHidden,
);

d.DuplicatesPhase duplicatesPhaseFromView(rust.DuplicatesPhaseView phase) =>
    switch (phase) {
      rust.DuplicatesPhaseView.scanning => d.DuplicatesPhase.scanning,
      rust.DuplicatesPhaseView.comparing => d.DuplicatesPhase.comparing,
      rust.DuplicatesPhaseView.hashing => d.DuplicatesPhase.hashing,
    };

d.DuplicatesUpdate duplicatesUpdateFromView(rust.DuplicatesUpdateView view) =>
    d.DuplicatesUpdate(
      taskId: view.taskId,
      phase: view.phase == null ? null : duplicatesPhaseFromView(view.phase!),
      filesScanned: view.filesScanned,
      candidates: view.candidates,
      filesHashed: view.filesHashed,
      bytesDone: view.bytesDone,
      current: view.current,
      groups: [
        for (final g in view.groups)
          d.DuplicateGroup(
            size: g.size,
            files: [
              for (final f in g.files)
                d.DuplicateFile(
                  path: f.path,
                  modified: dateTimeFromMs(f.modifiedMs),
                ),
            ],
          ),
      ],
      done: view.done,
      error: view.error,
    );
