/// Translation between generated bridge types and `domain_models`.
///
/// Kept in one place so every repository agrees on timestamps and enums.
library;

import 'package:domain_models/domain_models.dart' as d;

import 'rust/api/archives.dart' as rust;
import 'rust/api/capabilities.dart' as rust;
import 'rust/api/flat.dart' as rust;
import 'rust/api/tags.dart' as rust;
import 'rust/api/types.dart' as rust;

DateTime? dateTimeFromMs(int? ms) => ms == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();

int? msFromDateTime(DateTime? time) => time?.toUtc().millisecondsSinceEpoch;

d.FerryxErrorKind errorKindFromView(
  rust.FerryxErrorKind kind,
) => switch (kind) {
  rust.FerryxErrorKind.notFound => d.FerryxErrorKind.notFound,
  rust.FerryxErrorKind.permissionDenied => d.FerryxErrorKind.permissionDenied,
  rust.FerryxErrorKind.alreadyExists => d.FerryxErrorKind.alreadyExists,
  rust.FerryxErrorKind.notADirectory => d.FerryxErrorKind.notADirectory,
  rust.FerryxErrorKind.isADirectory => d.FerryxErrorKind.isADirectory,
  rust.FerryxErrorKind.notEmpty => d.FerryxErrorKind.notEmpty,
  rust.FerryxErrorKind.unsupported => d.FerryxErrorKind.unsupported,
  rust.FerryxErrorKind.cancelled => d.FerryxErrorKind.cancelled,
  rust.FerryxErrorKind.invalidName => d.FerryxErrorKind.invalidName,
  rust.FerryxErrorKind.invalidPattern => d.FerryxErrorKind.invalidPattern,
  rust.FerryxErrorKind.io => d.FerryxErrorKind.io,
  rust.FerryxErrorKind.passwordRequired => d.FerryxErrorKind.passwordRequired,
  rust.FerryxErrorKind.wrongPassword => d.FerryxErrorKind.wrongPassword,
};

// ─── Locations and entries ───

rust.LocationView locationToView(d.Location location) => rust.LocationView(
  kind: switch (location.kind) {
    d.LocationKind.native => rust.LocationKind.native,
    d.LocationKind.archive => rust.LocationKind.archive,
  },
  path: location.path,
  archive: location.archive,
);

d.Location locationFromView(rust.LocationView view) => switch (view.kind) {
  rust.LocationKind.native => d.Location.native(view.path),
  rust.LocationKind.archive => d.Location.inArchive(
    archive: view.archive ?? '',
    path: view.path,
  ),
};

d.EntryKind entryKindFromView(rust.EntryKindView kind) => switch (kind) {
  rust.EntryKindView.file => d.EntryKind.file,
  rust.EntryKindView.directory => d.EntryKind.directory,
  rust.EntryKindView.symlink => d.EntryKind.symlink,
  rust.EntryKindView.other => d.EntryKind.other,
};

/// [folder] is a flat view's folder of the entry, relative to its root.
d.FileEntry entryFromView(rust.EntryView view, {String folder = ''}) =>
    d.FileEntry(
      name: view.name,
      path: view.path,
      kind: entryKindFromView(view.kind),
      isDir: view.isDir,
      isParent: view.isParent,
      symlinkTarget: view.symlinkTarget,
      size: view.size,
      modified: dateTimeFromMs(view.modifiedMs),
      created: dateTimeFromMs(view.createdMs),
      accessed: dateTimeFromMs(view.accessedMs),
      added: dateTimeFromMs(view.addedMs),
      mode: view.mode,
      uid: view.uid,
      gid: view.gid,
      owner: view.owner,
      group: view.group,
      flags: view.flags,
      isHidden: view.isHidden,
      extension: view.extension_,
      tags: view.tags.isEmpty
          ? const []
          : view.tags.map(tagFromView).toList(growable: false),
      folder: folder,
    );

d.Listing listingFromView(rust.ListingView view) => d.Listing(
  location: locationFromView(view.location),
  entries: view.entries.map(entryFromView).toList(growable: false),
  freeBytes: view.freeBytes,
  totalBytes: view.totalBytes,
  volumeName: view.volumeName,
  watched: view.watched,
);

// ─── Sorting ───

rust.SortFieldView sortFieldToView(d.SortField field) => switch (field) {
  d.SortField.name => rust.SortFieldView.name,
  d.SortField.extension => rust.SortFieldView.extension_,
  d.SortField.size => rust.SortFieldView.size,
  d.SortField.modified => rust.SortFieldView.modified,
  d.SortField.created => rust.SortFieldView.created,
  d.SortField.added => rust.SortFieldView.added,
  d.SortField.accessed => rust.SortFieldView.accessed,
};

rust.CollationView collationToView(d.Collation collation) =>
    switch (collation) {
      d.Collation.natural => rust.CollationView.natural,
      d.Collation.caseInsensitive => rust.CollationView.caseInsensitive,
      d.Collation.caseSensitive => rust.CollationView.caseSensitive,
    };

rust.SortOptionsView sortOptionsToView(d.SortOptions sort) =>
    rust.SortOptionsView(
      field: sortFieldToView(sort.field),
      descending: sort.descending,
      foldersFirst: sort.foldersFirst,
      extensionlessFolders: sort.extensionlessFolders,
      collation: collationToView(sort.collation),
    );

rust.ListingOptionsView listingOptionsToView(d.ListingOptions options) =>
    rust.ListingOptionsView(
      showHidden: options.showHidden,
      showParent: options.showParent,
      sort: sortOptionsToView(options.sort),
    );

// ─── Volumes ───

d.Volume volumeFromView(rust.VolumeView view) => d.Volume(
  name: view.name,
  mountPoint: view.mountPoint,
  totalBytes: view.totalBytes,
  availableBytes: view.availableBytes,
  fileSystem: view.fileSystem,
  removable: view.removable,
  isRoot: view.isRoot,
);

d.StandardFolders standardFoldersFromView(rust.StandardFoldersView view) =>
    d.StandardFolders(
      home: view.home,
      desktop: view.desktop,
      documents: view.documents,
      downloads: view.downloads,
      applications: view.applications,
      utilities: view.utilities,
      library: view.library_,
      root: view.root,
      temporary: view.temporary,
      userName: view.userName,
    );

// ─── Operations ───

rust.OpKindView opKindToView(d.OpKind kind) => switch (kind) {
  d.OpKind.copy => rust.OpKindView.copy,
  d.OpKind.move => rust.OpKindView.move,
  d.OpKind.delete => rust.OpKindView.delete,
  d.OpKind.trash => rust.OpKindView.trash,
  d.OpKind.duplicate => rust.OpKindView.duplicate,
  d.OpKind.compress => rust.OpKindView.compress,
  d.OpKind.extract => rust.OpKindView.extract,
  d.OpKind.calcSizes => rust.OpKindView.calcSizes,
};

d.OpKind opKindFromView(rust.OpKindView kind) => switch (kind) {
  rust.OpKindView.copy => d.OpKind.copy,
  rust.OpKindView.move => d.OpKind.move,
  rust.OpKindView.delete => d.OpKind.delete,
  rust.OpKindView.trash => d.OpKind.trash,
  rust.OpKindView.duplicate => d.OpKind.duplicate,
  rust.OpKindView.compress => d.OpKind.compress,
  rust.OpKindView.extract => d.OpKind.extract,
  rust.OpKindView.calcSizes => d.OpKind.calcSizes,
};

rust.ConflictPolicyView conflictPolicyToView(d.ConflictPolicy policy) =>
    switch (policy) {
      d.ConflictPolicy.ask => rust.ConflictPolicyView.ask,
      d.ConflictPolicy.overwrite => rust.ConflictPolicyView.overwrite,
      d.ConflictPolicy.overwriteOlder => rust.ConflictPolicyView.overwriteOlder,
      d.ConflictPolicy.skip => rust.ConflictPolicyView.skip,
      d.ConflictPolicy.keepBoth => rust.ConflictPolicyView.keepBoth,
    };

rust.OpRequestView operationRequestToView(d.OperationRequest request) =>
    rust.OpRequestView(
      kind: opKindToView(request.kind),
      sources: request.sources,
      archive: request.archive,
      destination: request.destination,
      newName: request.newName,
      conflicts: conflictPolicyToView(request.conflicts),
      preserveAttributes: request.preserveAttributes,
      verify: request.verify,
      password: request.password,
      intoFolders: request.intoFolders,
    );

d.OpState opStateFromView(rust.OpStateView state) => switch (state) {
  rust.OpStateView.scanning => d.OpState.scanning,
  rust.OpStateView.running => d.OpState.running,
  rust.OpStateView.paused => d.OpState.paused,
  rust.OpStateView.waiting => d.OpState.waiting,
  rust.OpStateView.done => d.OpState.done,
  rust.OpStateView.doneWithErrors => d.OpState.doneWithErrors,
  rust.OpStateView.cancelled => d.OpState.cancelled,
  rust.OpStateView.failed => d.OpState.failed,
};

d.Answer answerFromView(rust.AnswerView answer) => switch (answer) {
  rust.AnswerView.overwrite => d.Answer.overwrite,
  rust.AnswerView.overwriteAll => d.Answer.overwriteAll,
  rust.AnswerView.overwriteOlderAll => d.Answer.overwriteOlderAll,
  rust.AnswerView.skip => d.Answer.skip,
  rust.AnswerView.skipAll => d.Answer.skipAll,
  rust.AnswerView.keepBoth => d.Answer.keepBoth,
  rust.AnswerView.keepBothAll => d.Answer.keepBothAll,
  rust.AnswerView.merge => d.Answer.merge,
  rust.AnswerView.mergeAll => d.Answer.mergeAll,
  rust.AnswerView.retry => d.Answer.retry,
  rust.AnswerView.abort => d.Answer.abort,
};

rust.AnswerView answerToView(d.Answer answer) => switch (answer) {
  d.Answer.overwrite => rust.AnswerView.overwrite,
  d.Answer.overwriteAll => rust.AnswerView.overwriteAll,
  d.Answer.overwriteOlderAll => rust.AnswerView.overwriteOlderAll,
  d.Answer.skip => rust.AnswerView.skip,
  d.Answer.skipAll => rust.AnswerView.skipAll,
  d.Answer.keepBoth => rust.AnswerView.keepBoth,
  d.Answer.keepBothAll => rust.AnswerView.keepBothAll,
  d.Answer.merge => rust.AnswerView.merge,
  d.Answer.mergeAll => rust.AnswerView.mergeAll,
  d.Answer.retry => rust.AnswerView.retry,
  d.Answer.abort => rust.AnswerView.abort,
};

d.ConflictSide conflictSideFromView(rust.ConflictSideView view) =>
    d.ConflictSide(
      path: view.path,
      size: view.size,
      modified: dateTimeFromMs(view.modifiedMs),
      isDir: view.isDir,
    );

d.OperationQuestion questionFromView(rust.QuestionView view) =>
    d.OperationQuestion(
      id: view.id,
      kind: switch (view.kind) {
        rust.QuestionKindView.conflict => d.QuestionKind.conflict,
        rust.QuestionKindView.error => d.QuestionKind.error,
      },
      message: view.message,
      answers: view.answers.map(answerFromView).toList(growable: false),
      source: view.source == null ? null : conflictSideFromView(view.source!),
      existing: view.existing == null
          ? null
          : conflictSideFromView(view.existing!),
    );

d.OperationProgress progressFromView(rust.ProgressView view) =>
    d.OperationProgress(
      id: view.id,
      kind: opKindFromView(view.kind),
      state: opStateFromView(view.state),
      bytesDone: view.bytesDone,
      bytesTotal: view.bytesTotal,
      itemsDone: view.itemsDone,
      itemsTotal: view.itemsTotal,
      current: view.current,
      started: dateTimeFromMs(view.startedMs),
      elapsed: Duration(milliseconds: view.elapsedMs),
      bytesPerSecond: view.bytesPerSecond,
      errors: [
        for (final e in view.errors)
          d.OperationError(path: e.path, message: e.message),
      ],
      question: view.question == null ? null : questionFromView(view.question!),
      sizes: [
        for (final s in view.sizes) d.FolderSize(path: s.path, bytes: s.bytes),
      ],
      resultPath: view.resultPath,
      sources: view.sources,
      destination: view.destination,
    );

// ─── Find ───

rust.FindRequestView findRequestToView(d.FindRequest request) =>
    rust.FindRequestView(
      root: request.root,
      name: request.name,
      nameIsRegex: request.nameIsRegex,
      contentText: request.content?.text,
      contentCaseSensitive: request.content?.caseSensitive ?? false,
      contentWholePhrase: request.content?.wholePhrase ?? true,
      contentNotContaining: request.content?.notContaining ?? false,
      sizeOp: switch (request.size?.op) {
        null => null,
        d.SizeOp.less => rust.SizeOpView.less,
        d.SizeOp.equal => rust.SizeOpView.equal,
        d.SizeOp.greater => rust.SizeOpView.greater,
      },
      sizeBytes: request.size?.bytes ?? 0,
      includeHidden: request.includeHidden,
      includeFolders: request.includeFolders,
    );

d.FindHit findHitFromView(rust.FindHitView view) => d.FindHit(
  path: view.path,
  isDir: view.isDir,
  size: view.size,
  modified: dateTimeFromMs(view.modifiedMs),
);

// ─── Batch rename ───

rust.NamePartView namePartToView(d.NamePart part) => switch (part) {
  d.NamePart.whole => rust.NamePartView.whole,
  d.NamePart.name => rust.NamePartView.name,
  d.NamePart.extension => rust.NamePartView.extension_,
};

rust.RenameOptionsView renameOptionsToView(d.RenameOptions options) =>
    rust.RenameOptionsView(
      pattern: options.pattern,
      search: options.search,
      replace: options.replace,
      searchRegex: options.searchRegex,
      searchCaseSensitive: options.searchCaseSensitive,
      searchOnce: options.searchOnce,
      searchPart: namePartToView(options.searchPart),
      case_: switch (options.caseTransform) {
        d.CaseTransform.unchanged => rust.CaseTransformView.unchanged,
        d.CaseTransform.lower => rust.CaseTransformView.lower,
        d.CaseTransform.upper => rust.CaseTransformView.upper,
        d.CaseTransform.capitalize => rust.CaseTransformView.capitalize,
      },
      casePart: namePartToView(options.casePart),
      counterStart: options.counterStart,
      counterStep: options.counterStep,
      counterWidth: options.counterWidth,
    );

d.RenameOutcome renameOutcomeFromView(rust.RenameOutcomeView view) =>
    d.RenameOutcome(
      path: view.path,
      oldName: view.oldName,
      newName: view.newName,
      problem: switch (view.problem) {
        rust.RenameProblemView.none => null,
        rust.RenameProblemView.empty => d.RenameProblem.empty,
        rust.RenameProblemView.invalid => d.RenameProblem.invalid,
        rust.RenameProblemView.duplicate => d.RenameProblem.duplicate,
      },
    );

d.RenameFailure renameFailureFromView(rust.RenameFailureView view) =>
    d.RenameFailure(path: view.path, message: view.message);

// ─── Attributes ───

d.FileAttributes attributesFromView(rust.AttributesView view) =>
    d.FileAttributes(
      path: view.path,
      permissions: view.permissions,
      uid: view.uid,
      gid: view.gid,
      owner: view.owner,
      group: view.group,
      flags: view.flags,
      supportsFlags: view.supportsFlags,
      isDir: view.isDir,
      modified: dateTimeFromMs(view.modifiedMs),
      accessed: dateTimeFromMs(view.accessedMs),
      created: dateTimeFromMs(view.createdMs),
    );

rust.AttributeChangesView attributeChangesToView(d.AttributeChanges changes) =>
    rust.AttributeChangesView(
      permissionsSet: changes.permissionsSet,
      permissionsClear: changes.permissionsClear,
      uid: changes.uid,
      gid: changes.gid,
      flagsSet: changes.flagsSet,
      flagsClear: changes.flagsClear,
      modifiedMs: msFromDateTime(changes.modified),
      accessedMs: msFromDateTime(changes.accessed),
    );

// ─── Archives ───

d.ArchiveInfo archiveInfoFromView(rust.ArchiveInfoView view) => d.ArchiveInfo(
  format: view.format,
  topLevelCount: view.topLevelCount,
  singleTopLevel: view.singleTopLevel,
  fileCount: view.fileCount,
  unpackedBytes: view.unpackedBytes,
  encrypted: view.encrypted,
  needsPassword: view.needsPassword,
  hasPassword: view.hasPassword,
);

// ─── Flat views ───

d.FlatBatch flatBatchFromView(rust.FlatBatchView view) => d.FlatBatch(
  generation: view.generation,
  entries: [
    for (var i = 0; i < view.entries.length; i++)
      entryFromView(view.entries[i], folder: view.folders[i]),
  ],
  done: view.done,
  count: view.count,
  capped: view.capped,
);

// ─── Tags and capabilities ───

d.FileTag tagFromView(rust.TagView view) =>
    d.FileTag(view.name, color: view.color);

rust.TagView tagToView(d.FileTag tag) =>
    rust.TagView(name: tag.name, color: tag.color);

d.TagOutcome tagOutcomeFromView(rust.TagOutcomeView view) => d.TagOutcome(
  path: view.path,
  tags: view.tags.map(tagFromView).toList(growable: false),
  failure: view.failure == null
      ? null
      : d.FerryxException(
          errorKindFromView(view.failure!),
          view.message,
          path: view.path,
        ),
);

d.Capabilities capabilitiesFromView(rust.CapabilitiesView view) =>
    d.Capabilities(finderTags: view.finderTags, spotlight: view.spotlight);
