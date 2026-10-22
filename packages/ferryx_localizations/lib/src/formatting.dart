import 'package:domain_models/domain_models.dart';
import 'package:intl/intl.dart';

import 'generated/ferryx_localizations.dart';

/// Human formatting of sizes, dates, durations and error kinds.
extension FerryxFormatting on FerryxLocalizations {
  /// `3.4 MB`, `12 KB`, `512 B`, in the locale's digits.
  String fileSize(int bytes) {
    const units = 1024;
    if (bytes < units) return sizeBytes(bytes);
    final kb = bytes / units;
    if (kb < units) return sizeKilobytes(_short(kb));
    final mb = kb / units;
    if (mb < units) return sizeMegabytes(_short(mb));
    final gb = mb / units;
    if (gb < units) return sizeGigabytes(_short(gb));
    return sizeTerabytes(_short(gb / units));
  }

  /// A size as a panel column shows it: whole kilobytes and up.
  String fileSizeCompact(int bytes) => fileSize(bytes);

  String _short(double value) {
    final format = NumberFormat(value < 10 ? '0.0' : '0', localeName);
    return format.format(value);
  }

  /// `1 284`, with the locale's grouping.
  String count(int value) =>
      NumberFormat.decimalPattern(localeName).format(value);

  /// `14 Oct 2026, 13:58` or, for today, `Today, 13:58`.
  String dateTime(DateTime time, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final day = DateTime(time.year, time.month, time.day);
    final clock = DateFormat.Hm(localeName).format(time);
    if (day == today) return relativeToday(clock);
    if (day == today.subtract(const Duration(days: 1))) {
      return relativeYesterday(clock);
    }
    final date = time.year == reference.year
        ? DateFormat.MMMd(localeName).format(time)
        : DateFormat.yMMMd(localeName).format(time);
    return '$date, $clock';
  }

  /// `2026-10-14 13:58`, for fields that are edited.
  String dateTimeField(DateTime time) =>
      DateFormat('yyyy-MM-dd HH:mm', localeName).format(time);

  /// `1:02:03`, `2:03`, `0:07`.
  String duration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:${two(minutes)}:${two(seconds)}'
        : '$minutes:${two(seconds)}';
  }

  /// The title of an error, by kind.
  String errorTitle(FerryxErrorKind kind) => switch (kind) {
    FerryxErrorKind.notFound => errorNotFound,
    FerryxErrorKind.permissionDenied => errorPermissionDenied,
    FerryxErrorKind.alreadyExists => errorAlreadyExists,
    FerryxErrorKind.notADirectory => errorNotADirectory,
    FerryxErrorKind.isADirectory => errorIsADirectory,
    FerryxErrorKind.notEmpty => errorNotEmpty,
    FerryxErrorKind.unsupported => errorUnsupported,
    FerryxErrorKind.cancelled => errorCancelled,
    FerryxErrorKind.invalidName => errorInvalidName,
    FerryxErrorKind.invalidPattern => errorInvalidPattern,
    FerryxErrorKind.io => errorIo,
  };

  /// The error's title with the core's own words after it.
  String errorMessage(FerryxException error) => error.message.isEmpty
      ? errorTitle(error.kind)
      : '${errorTitle(error.kind)}: ${error.message}';

  /// The name of an operation with its count, for the strip.
  String operationTitle(OperationProgress progress) {
    final count = progress.sources.length;
    return switch (progress.kind) {
      OpKind.copy => opCopyTitle(count),
      OpKind.move => opMoveTitle(count),
      OpKind.delete => opDeleteTitle(count),
      OpKind.trash => opTrashTitle(count),
      OpKind.duplicate => opDuplicateTitle(count),
      OpKind.compress => opCompressTitle(count),
      OpKind.extract => opExtractTitle(count),
      OpKind.calcSizes => opCalcSizesTitle(count),
      OpKind.synchronize => opSynchronizeTitle(progress.itemsTotal),
      OpKind.compareContents => opCompareContentsTitle(count),
      OpKind.undo => opUndoTitle(progress.itemsTotal),
      OpKind.redo => opRedoTitle(progress.itemsTotal),
    };
  }

  String operationState(OpState state) => switch (state) {
    OpState.scanning => opStateScanning,
    OpState.running => opStateRunning,
    OpState.paused => opStatePaused,
    OpState.waiting => opStateWaiting,
    OpState.done => opStateDone,
    OpState.doneWithErrors => opStateDoneWithErrors,
    OpState.cancelled => opStateCancelled,
    OpState.failed => opStateFailed,
  };

  String answerLabel(Answer answer) => switch (answer) {
    Answer.overwrite => actionOverwrite,
    Answer.overwriteAll => answerOverwriteAll,
    Answer.overwriteOlderAll => answerOverwriteOlderAll,
    Answer.skip => actionSkip,
    Answer.skipAll => answerSkipAll,
    Answer.keepBoth => actionKeepBoth,
    Answer.keepBothAll => answerKeepBothAll,
    Answer.merge => actionMerge,
    Answer.mergeAll => answerMergeAll,
    Answer.retry => actionRetry,
    Answer.abort => actionStop,
  };

  String sortFieldLabel(SortField field) => switch (field) {
    SortField.name => columnName,
    SortField.extension => columnExtension,
    SortField.size => columnSize,
    SortField.modified => columnModified,
    SortField.created => columnCreated,
    SortField.added => columnAdded,
    SortField.accessed => columnAccessed,
  };

  String columnLabel(ListColumn column) => switch (column) {
    ListColumn.name => columnName,
    ListColumn.extension => columnExtension,
    ListColumn.size => columnSize,
    ListColumn.modified => columnModified,
    ListColumn.created => columnCreated,
    ListColumn.added => columnAdded,
    ListColumn.accessed => columnAccessed,
    ListColumn.permissions => columnPermissions,
    ListColumn.owner => columnOwner,
    ListColumn.group => columnGroup,
  };

  String collationLabel(Collation collation) => switch (collation) {
    Collation.natural => collationNatural,
    Collation.caseInsensitive => collationCaseInsensitive,
    Collation.caseSensitive => collationCaseSensitive,
  };
}
