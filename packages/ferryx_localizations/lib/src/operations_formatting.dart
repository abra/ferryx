import 'package:domain_models/domain_models.dart';

import 'generated/ferryx_localizations.dart';

/// Words for the Operations stream: steps of the undo journal and why one
/// cannot be walked back, checksum outcomes.
extension OperationsFormatting on FerryxLocalizations {
  /// A step as menus and notices name it: "Move of 3 items", "Rename of
  /// “a.txt”".
  String stepLabel(StepSummary step) {
    final what = step.items <= 1 && step.firstName.isNotEmpty
        ? journalWhatOne(step.firstName)
        : journalWhatMany(step.items);
    return switch (step.kind) {
      StepKind.copy => journalStepCopy(what),
      StepKind.move => journalStepMove(what),
      StepKind.trash => journalStepTrash(what),
      StepKind.rename => journalStepRename(what),
      StepKind.createFolder => journalStepCreateFolder(what),
      StepKind.createFile => journalStepCreateFile(what),
      StepKind.createLink => journalStepCreateLink(what),
      StepKind.duplicate => journalStepDuplicate(what),
      StepKind.compress => journalStepCompress(what),
      StepKind.extract => journalStepExtract(what),
      StepKind.synchronize => journalStepSynchronize(what),
    };
  }

  /// Why a change of a step cannot be walked back as it was.
  String undoIssueLabel(UndoIssueKind kind) => switch (kind) {
    UndoIssueKind.missing => undoIssueMissing,
    UndoIssueKind.occupied => undoIssueOccupied,
    UndoIssueKind.changed => undoIssueChanged,
    UndoIssueKind.lost => undoIssueLost,
    UndoIssueKind.notInTrash => undoIssueNotInTrash,
    UndoIssueKind.unsupported => undoIssueUnsupported,
    UndoIssueKind.truncated => undoIssueTruncated,
  };

  String checksumStatusLabel(ChecksumStatus status) => switch (status) {
    ChecksumStatus.ok => checksumStatusOk,
    ChecksumStatus.mismatch => checksumStatusMismatch,
    ChecksumStatus.missing => checksumStatusMissing,
    ChecksumStatus.error => checksumStatusError,
  };
}
