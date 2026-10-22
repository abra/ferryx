// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'ferryx_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class FerryxLocalizationsEn extends FerryxLocalizations {
  FerryxLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Ferryx';

  @override
  String aboutVersion(String version) {
    return 'Version $version · macOS, Windows, Linux';
  }

  @override
  String get aboutDescription =>
      'A dual-pane file manager built for the keyboard: two panels, tabs, background operations, archives, a viewer and a find.';

  @override
  String get aboutLicense => 'Free and open source.';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionOk => 'OK';

  @override
  String get actionClose => 'Close';

  @override
  String get actionSave => 'Save';

  @override
  String get actionApply => 'Apply';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionCopy => 'Copy';

  @override
  String get actionMove => 'Move';

  @override
  String get actionRename => 'Rename';

  @override
  String get actionCreate => 'Create';

  @override
  String get actionOpen => 'Open';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionSkip => 'Skip';

  @override
  String get actionOverwrite => 'Overwrite';

  @override
  String get actionKeepBoth => 'Keep both';

  @override
  String get actionMerge => 'Merge';

  @override
  String get actionStop => 'Stop';

  @override
  String get actionPause => 'Pause';

  @override
  String get actionResume => 'Resume';

  @override
  String get actionSearch => 'Search';

  @override
  String get actionAdd => 'Add';

  @override
  String get actionRemove => 'Remove';

  @override
  String get actionReset => 'Reset';

  @override
  String get actionGo => 'Go';

  @override
  String get actionCompress => 'Compress';

  @override
  String get actionSelect => 'Select';

  @override
  String get actionDeselect => 'Deselect';

  @override
  String get actionView => 'View';

  @override
  String get actionEject => 'Eject';

  @override
  String get actionClear => 'Clear';

  @override
  String get actionDone => 'Done';

  @override
  String joinedDetails(String first, String second) {
    return '$first · $second';
  }

  @override
  String get answerOverwriteAll => 'Overwrite all';

  @override
  String get answerOverwriteOlderAll => 'Overwrite older';

  @override
  String get answerSkipAll => 'Skip all';

  @override
  String get answerKeepBothAll => 'Keep both for all';

  @override
  String get answerMergeAll => 'Merge all';

  @override
  String get errorNotFound => 'Not found';

  @override
  String get errorPermissionDenied => 'Permission denied';

  @override
  String get errorAlreadyExists => 'Already exists';

  @override
  String get errorNotADirectory => 'Not a folder';

  @override
  String get errorIsADirectory => 'Is a folder';

  @override
  String get errorNotEmpty => 'The folder is not empty';

  @override
  String get errorUnsupported => 'Not supported here';

  @override
  String get errorCancelled => 'Cancelled';

  @override
  String get errorInvalidName => 'Not a valid name';

  @override
  String get errorInvalidPattern => 'Not a valid pattern';

  @override
  String get errorIo => 'Could not complete';

  @override
  String get errorTitle => 'Something went wrong';

  @override
  String sizeBytes(int bytes) {
    return '$bytes B';
  }

  @override
  String sizeKilobytes(String value) {
    return '$value KB';
  }

  @override
  String sizeMegabytes(String value) {
    return '$value MB';
  }

  @override
  String sizeGigabytes(String value) {
    return '$value GB';
  }

  @override
  String sizeTerabytes(String value) {
    return '$value TB';
  }

  @override
  String relativeToday(String time) {
    return 'Today, $time';
  }

  @override
  String relativeYesterday(String time) {
    return 'Yesterday, $time';
  }

  @override
  String get columnName => 'Name';

  @override
  String get columnExtension => 'Extension';

  @override
  String get columnSize => 'Size';

  @override
  String get columnModified => 'Modified';

  @override
  String get columnCreated => 'Created';

  @override
  String get columnAdded => 'Added';

  @override
  String get columnAccessed => 'Accessed';

  @override
  String get columnPermissions => 'Permissions';

  @override
  String get columnOwner => 'Owner';

  @override
  String get columnGroup => 'Group';

  @override
  String get collationNatural => 'Natural';

  @override
  String get collationCaseInsensitive => 'Case-insensitive';

  @override
  String get collationCaseSensitive => 'Case-sensitive';

  @override
  String get panelParentFolder => 'Up to the enclosing folder';

  @override
  String get panelEmptyFolder => 'This folder is empty';

  @override
  String get panelLoading => 'Reading…';

  @override
  String get panelFolderSize => 'Folder';

  @override
  String panelItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: 'no items',
    );
    return '$_temp0';
  }

  @override
  String panelSelectedSummary(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      one: '1 selected',
    );
    return '$_temp0, $size';
  }

  @override
  String panelFreeSpace(String free) {
    return '$free free';
  }

  @override
  String panelQuickSearch(String query) {
    return 'Quick search: $query';
  }

  @override
  String panelSymlinkTo(String target) {
    return '→ $target';
  }

  @override
  String panelSortTooltip(String field) {
    return 'Sorted by $field';
  }

  @override
  String panelSortSummary(String field, String direction) {
    return 'Sorted by $field, $direction';
  }

  @override
  String get panelLayoutTooltip => 'View mode';

  @override
  String get panelMenuTooltip => 'Panel menu';

  @override
  String get panelArchiveBadge => 'Archive';

  @override
  String get panelErrorTitle => 'Cannot open this folder';

  @override
  String get panelGoHomeInstead => 'Go to the home folder';

  @override
  String get vimModeNormal => 'NORMAL';

  @override
  String get vimModeVisual => 'VISUAL';

  @override
  String get vimModeSearch => 'SEARCH';

  @override
  String get vimModeCommand => 'COMMAND';

  @override
  String vimRegisterCut(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cut',
      one: '1 cut',
    );
    return '$_temp0';
  }

  @override
  String vimRegisterYank(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count yanked',
      one: '1 yanked',
    );
    return '$_temp0';
  }

  @override
  String get vimCommandHint =>
      'cd, mkdir, touch, rename, cp, mv, trash, delete, sort, set hidden, tabnew, tabclose, q, find, marks, help, or a row number';

  @override
  String vimUnknownCommand(String name) {
    return 'Not a command: $name';
  }

  @override
  String vimMarkSet(String letter) {
    return 'Mark $letter set';
  }

  @override
  String vimNoMark(String letter) {
    return 'No mark $letter';
  }

  @override
  String get vimMarksTitle => 'Marks';

  @override
  String get vimNoMarks => 'No marks yet; set one with m and a letter';

  @override
  String get panelsVimMode => 'Vim keys';

  @override
  String get panelsVimModeHint =>
      'h j k l, counts, / to search, v to select, yy dd p, marks and a : command line; see the cheat sheet';

  @override
  String get panelHiddenShown => 'Hidden items shown';

  @override
  String get tabNew => 'New tab';

  @override
  String get tabClose => 'Close tab';

  @override
  String get tabList => 'All tabs';

  @override
  String get tabRecentlyClosed => 'Recently closed';

  @override
  String get sortMenuTitle => 'Sort by';

  @override
  String get sortAscending => 'Ascending';

  @override
  String get sortDescending => 'Descending';

  @override
  String get layoutMenuTitle => 'View mode';

  @override
  String get menuOpen => 'Open';

  @override
  String get menuOpenWith => 'Open with';

  @override
  String get menuOpenWithOther => 'Other application…';

  @override
  String get menuShowInFinder => 'Show in Finder';

  @override
  String get menuShowInExplorer => 'Show in Explorer';

  @override
  String get menuShowInFiles => 'Show in Files';

  @override
  String get menuCopyPath => 'Copy path';

  @override
  String get menuCopyName => 'Copy name';

  @override
  String get menuNewFolder => 'New folder';

  @override
  String get menuNewFile => 'New file';

  @override
  String get menuSelectAll => 'Select all';

  @override
  String get menuEnterArchive => 'Open as folder';

  @override
  String get menuExtractHere => 'Extract here';

  @override
  String get menuExtractToOpposite => 'Extract to the other panel';

  @override
  String copyDialogTitle(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Copy $count items to',
      one: 'Copy “$name” to',
    );
    return '$_temp0';
  }

  @override
  String moveDialogTitle(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Move $count items to',
      one: 'Move “$name” to',
    );
    return '$_temp0';
  }

  @override
  String copyAsTitle(String name) {
    return 'Copy “$name” as';
  }

  @override
  String moveAsTitle(String name) {
    return 'Move or rename “$name” as';
  }

  @override
  String get destinationLabel => 'Destination';

  @override
  String get newNameLabel => 'New name';

  @override
  String get optionPreserveAttributes => 'Preserve permissions and dates';

  @override
  String get optionVerify => 'Verify the copy';

  @override
  String get conflictsLabel => 'If an item already exists';

  @override
  String get conflictAsk => 'Ask';

  @override
  String get conflictOverwrite => 'Overwrite';

  @override
  String get conflictOverwriteOlder => 'Overwrite when older';

  @override
  String get conflictSkip => 'Skip';

  @override
  String get conflictKeepBoth => 'Keep both';

  @override
  String get createDirectoryTitle => 'New folder';

  @override
  String get createDirectoryInOppositeTitle => 'New folder in the other panel';

  @override
  String get createDirectoryHint => 'Name, or a nested path like Notes/2026';

  @override
  String get createFileTitle => 'New file';

  @override
  String get newFolderDefaultName => 'untitled folder';

  @override
  String get newFileDefaultName => 'untitled.txt';

  @override
  String deleteTitle(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count items?',
      one: 'Delete “$name”?',
    );
    return '$_temp0';
  }

  @override
  String get deleteMessageTrash => 'The items go to the Trash.';

  @override
  String get deleteMessagePermanent =>
      'The items are deleted for good and cannot be brought back.';

  @override
  String get deleteToTrash => 'Move to Trash';

  @override
  String get deletePermanently => 'Delete permanently';

  @override
  String get deleteNothingSelected => 'Nothing to delete';

  @override
  String compressTitle(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Compress $count items',
      one: 'Compress “$name”',
    );
    return '$_temp0';
  }

  @override
  String get archiveNameLabel => 'Archive name';

  @override
  String get passwordLabel => 'Password (AES-256, optional)';

  @override
  String get compressHere => 'In this folder';

  @override
  String get compressToOpposite => 'In the other panel';

  @override
  String get selectMaskTitle => 'Select with mask';

  @override
  String get deselectMaskTitle => 'Deselect with mask';

  @override
  String get maskLabel => 'Mask or expression';

  @override
  String get maskHint => '*.jpg; *.png';

  @override
  String get maskRegex => 'Regular expression';

  @override
  String get goToFolderTitle => 'Go to folder';

  @override
  String get goToFolderHint => '/path/to/folder or ~/Documents';

  @override
  String get goToPopupTitle => 'Go to';

  @override
  String get goToFilterHint => 'Type to filter';

  @override
  String get sectionFavorites => 'Favorites';

  @override
  String get sectionVolumes => 'Volumes';

  @override
  String get sectionOtherPanel => 'Other panel';

  @override
  String get sectionHistory => 'History';

  @override
  String get sectionParents => 'Enclosing folders';

  @override
  String get quickListEmpty => 'Nothing here yet';

  @override
  String volumeFree(String free, String total) {
    return '$free of $total free';
  }

  @override
  String ejectVolume(String name) {
    return 'Eject $name';
  }

  @override
  String get favoritesTitle => 'Favorites';

  @override
  String get favoritesAddCurrent => 'Add the current folder';

  @override
  String get favoritesEmpty =>
      'No favorites yet. Add the current folder from the panel menu.';

  @override
  String get favoritesRenameTitle => 'Rename favorite';

  @override
  String favoriteAdded(String name) {
    return 'Added to favorites: $name';
  }

  @override
  String favoriteRemoved(String name) {
    return 'Removed from favorites: $name';
  }

  @override
  String attributesTitle(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Attributes of $count items',
      one: 'Attributes of “$name”',
    );
    return '$_temp0';
  }

  @override
  String get permissionsLabel => 'Permissions';

  @override
  String get permOwner => 'Owner';

  @override
  String get permGroup => 'Group';

  @override
  String get permOthers => 'Others';

  @override
  String get permRead => 'Read';

  @override
  String get permWrite => 'Write';

  @override
  String get permExecute => 'Execute';

  @override
  String get permSetUid => 'Set user ID';

  @override
  String get permSetGid => 'Set group ID';

  @override
  String get permSticky => 'Sticky';

  @override
  String get flagsLabel => 'Flags';

  @override
  String get flagHidden => 'Hidden';

  @override
  String get flagLocked => 'Locked';

  @override
  String get flagAppendOnly => 'Append only';

  @override
  String get flagNoDump => 'No dump';

  @override
  String get flagArchived => 'Archived';

  @override
  String get ownerLabel => 'Owner';

  @override
  String get groupLabel => 'Group';

  @override
  String get timesLabel => 'Dates';

  @override
  String get modifiedLabel => 'Modified';

  @override
  String get accessedLabel => 'Accessed';

  @override
  String get createdLabel => 'Created';

  @override
  String get dateFieldHint => 'yyyy-mm-dd hh:mm';

  @override
  String get attributesInvalidDate => 'Not a valid date and time';

  @override
  String get applyRecursively => 'Apply to everything inside the folders';

  @override
  String attributesUnknownUser(String name) {
    return 'No user named “$name”';
  }

  @override
  String attributesUnknownGroup(String name) {
    return 'No group named “$name”';
  }

  @override
  String attributesFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items could not be changed',
      one: '1 item could not be changed',
    );
    return '$_temp0';
  }

  @override
  String batchRenameTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Rename $count items',
      one: 'Rename 1 item',
    );
    return '$_temp0';
  }

  @override
  String get renamePatternLabel => 'New name';

  @override
  String get renamePatternHint =>
      '[N].[E]  ·  [N] name, [E] extension, [C] counter, [d] date';

  @override
  String get renameSearchLabel => 'Search';

  @override
  String get renameReplaceLabel => 'Replace with';

  @override
  String get renameRegex => 'Regular expression';

  @override
  String get renameCaseSensitive => 'Match case';

  @override
  String get renameOnce => 'First occurrence only';

  @override
  String get renameCaseLabel => 'Case';

  @override
  String get caseUnchanged => 'As is';

  @override
  String get caseLower => 'lowercase';

  @override
  String get caseUpper => 'UPPERCASE';

  @override
  String get caseCapitalize => 'Capitalize Words';

  @override
  String get partWhole => 'Whole name';

  @override
  String get partName => 'Name only';

  @override
  String get partExtension => 'Extension only';

  @override
  String get renameCounterLabel => 'Counter';

  @override
  String get renameCounterStart => 'Start';

  @override
  String get renameCounterStep => 'Step';

  @override
  String get renameCounterWidth => 'Digits';

  @override
  String get renamePreviewOld => 'Current name';

  @override
  String get renamePreviewNew => 'New name';

  @override
  String get renameProblemEmpty => 'Empty name';

  @override
  String get renameProblemInvalid => 'Not a valid name';

  @override
  String get renameProblemDuplicate => 'Same name as another item';

  @override
  String get renameNoChanges => 'No names change';

  @override
  String renameFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items could not be renamed',
      one: '1 item could not be renamed',
    );
    return '$_temp0';
  }

  @override
  String get renamePlaceholdersHelp => 'Placeholders';

  @override
  String get renameSearchPartLabel => 'Search in';

  @override
  String get renameCasePartLabel => 'Apply to';

  @override
  String get renamePlaceholdersText =>
      '[N] name · [E] extension · [A] whole name · [P] parent folder · [G] grandparent · [N2-4] characters 2 to 4 · [N-3,2] two from the third-last · [C] counter, [C5+2:3] from 5 by 2, three digits · [d] date · [Y] [M] [D] year, month, day · [t] time · [h] [m] [s] · [U] [L] [F] upper, lower, capitalized text after · [n] as is · [[ and ]] brackets';

  @override
  String get symlinkTitle => 'New symbolic link';

  @override
  String get hardlinkTitle => 'New hard link';

  @override
  String get editSymlinkTitle => 'Edit symbolic link';

  @override
  String get linkTargetLabel => 'Points to';

  @override
  String get linkNameLabel => 'Link name';

  @override
  String get linkNotSymlink => 'The item is not a symbolic link';

  @override
  String get conflictTitle => 'Already exists';

  @override
  String get conflictSourceLabel => 'Copying';

  @override
  String get conflictExistingLabel => 'Existing';

  @override
  String get conflictFolderLabel => 'Folder';

  @override
  String get questionApplyToAll => 'Apply to all';

  @override
  String get questionErrorTitle => 'Could not continue';

  @override
  String conflictMessage(String name) {
    return '“$name” already exists in the destination.';
  }

  @override
  String questionErrorMessage(String name) {
    return 'Could not continue with “$name”.';
  }

  @override
  String opCopyTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Copying $count items',
      one: 'Copying 1 item',
    );
    return '$_temp0';
  }

  @override
  String opMoveTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Moving $count items',
      one: 'Moving 1 item',
    );
    return '$_temp0';
  }

  @override
  String opDeleteTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Deleting $count items',
      one: 'Deleting 1 item',
    );
    return '$_temp0';
  }

  @override
  String opTrashTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Moving $count items to the Trash',
      one: 'Moving 1 item to the Trash',
    );
    return '$_temp0';
  }

  @override
  String opDuplicateTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Duplicating $count items',
      one: 'Duplicating 1 item',
    );
    return '$_temp0';
  }

  @override
  String opCompressTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Compressing $count items',
      one: 'Compressing 1 item',
    );
    return '$_temp0';
  }

  @override
  String opExtractTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Extracting $count items',
      one: 'Extracting 1 item',
    );
    return '$_temp0';
  }

  @override
  String opCalcSizesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Calculating the sizes of $count folders',
      one: 'Calculating the size of 1 folder',
    );
    return '$_temp0';
  }

  @override
  String get opStateScanning => 'Counting…';

  @override
  String get opStateRunning => 'In progress';

  @override
  String get opStatePaused => 'Paused';

  @override
  String get opStateWaiting => 'Waiting for an answer';

  @override
  String get opStateDone => 'Done';

  @override
  String get opStateDoneWithErrors => 'Done with errors';

  @override
  String get opStateCancelled => 'Cancelled';

  @override
  String get opStateFailed => 'Failed';

  @override
  String opProgressBytes(String done, String total) {
    return '$done of $total';
  }

  @override
  String opProgressItems(int done, int total) {
    return '$done of $total items';
  }

  @override
  String opSpeed(String speed) {
    return '$speed/s';
  }

  @override
  String opRemaining(String duration) {
    return '$duration left';
  }

  @override
  String opErrorsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count errors',
      one: '1 error',
    );
    return '$_temp0';
  }

  @override
  String get opErrorsTitle => 'Errors';

  @override
  String opTitleTo(String title, String destination) {
    return '$title to $destination';
  }

  @override
  String opFirstError(String name, String message) {
    return '$name: $message';
  }

  @override
  String get operationsTitle => 'Operations';

  @override
  String get operationsEmpty => 'No operations';

  @override
  String get operationsClearFinished => 'Clear finished';

  @override
  String noticePathsCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count paths copied',
      one: 'Path copied',
    );
    return '$_temp0';
  }

  @override
  String get noticeNameCopied => 'Name copied';

  @override
  String get noticeNothingSelected => 'Nothing is selected';

  @override
  String get noticeNotInArchive => 'Not available inside an archive';

  @override
  String get noticeClipboardEmpty => 'The clipboard holds no paths';

  @override
  String noticeEjected(String name) {
    return 'Ejected $name';
  }

  @override
  String get noticeNoEditor =>
      'No editor is set up for this file; see Settings → Editors';

  @override
  String get noticeNoVolume => 'Nothing to eject here';

  @override
  String get noticeOpenFailed => 'Could not open the item';

  @override
  String get viewerTitle => 'Viewer';

  @override
  String get viewerModeText => 'Text';

  @override
  String get viewerModeHex => 'Hex';

  @override
  String get viewerModePreview => 'Preview';

  @override
  String get viewerGoToTitle => 'Go to';

  @override
  String get viewerGoToHint => 'Offset in bytes, or a percentage like 50%';

  @override
  String get viewerNoPreview => 'No preview for this kind of file';

  @override
  String get viewerFindHint => 'Find in file';

  @override
  String viewerPosition(String offset, String size) {
    return '$offset of $size';
  }

  @override
  String get viewerEncoding => 'UTF-8';

  @override
  String get viewerWrap => 'Wrap lines';

  @override
  String get viewerLoading => 'Reading…';

  @override
  String viewerWindow(String shown, String size) {
    return 'Showing $shown of $size; use Go to for the rest';
  }

  @override
  String get viewerNoMatch => 'Not found';

  @override
  String get viewerEmptyFile => 'The file is empty';

  @override
  String get viewerBinaryHint => 'Binary data: switch to Hex';

  @override
  String viewerLine(int line) {
    return 'Line $line';
  }

  @override
  String viewerMatches(int current, int total) {
    return '$current of $total';
  }

  @override
  String get viewerLoadNext => 'Next part';

  @override
  String get viewerLoadPrevious => 'Previous part';

  @override
  String get findTitle => 'Find files';

  @override
  String get findIn => 'In folder';

  @override
  String get findName => 'Name';

  @override
  String get findNameHint => '*.txt; report*';

  @override
  String get findRegex => 'Regular expression';

  @override
  String get findContent => 'Containing text';

  @override
  String get findCaseSensitive => 'Match case';

  @override
  String get findWholePhrase => 'Whole phrase';

  @override
  String get findNotContaining => 'Not containing';

  @override
  String get findSize => 'Size';

  @override
  String get findSizeAny => 'Any';

  @override
  String get findSizeLess => 'Less than';

  @override
  String get findSizeEqual => 'Equal to';

  @override
  String get findSizeGreater => 'Greater than';

  @override
  String get findIncludeHidden => 'Include hidden items';

  @override
  String get findStart => 'Find';

  @override
  String get findStop => 'Stop';

  @override
  String findResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items found',
      one: '1 item found',
      zero: 'No items found',
    );
    return '$_temp0';
  }

  @override
  String findScanning(String path) {
    return 'Looking in $path';
  }

  @override
  String get findGoTo => 'Go to';

  @override
  String get findView => 'View';

  @override
  String get findNoResults => 'Nothing matched';

  @override
  String findError(String message) {
    return 'The search could not run: $message';
  }

  @override
  String get findColumnFolder => 'Folder';

  @override
  String get findUnitBytes => 'B';

  @override
  String get findUnitKilobytes => 'KB';

  @override
  String get findUnitMegabytes => 'MB';

  @override
  String get findUnitGigabytes => 'GB';

  @override
  String findResultsCapped(int count) {
    return 'Showing the first $count items; narrow the search for the rest';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsGeneral => 'General';

  @override
  String get settingsPanels => 'Panels';

  @override
  String get settingsViewer => 'Viewer';

  @override
  String get settingsHotkeys => 'Hotkeys';

  @override
  String get settingsEditors => 'Editors';

  @override
  String get settingsTools => 'Tools';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsSearchHint => 'Search settings';

  @override
  String get themeLabel => 'Appearance';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get languageLabel => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageRussian => 'Русский';

  @override
  String get textSizeLabel => 'Text size';

  @override
  String textSizePercent(int percent) {
    return '$percent%';
  }

  @override
  String get confirmationsLabel => 'Confirmations';

  @override
  String get confirmTrashLabel => 'Ask before moving to the Trash';

  @override
  String get confirmDeleteLabel => 'Ask before deleting permanently';

  @override
  String get generalKeyHintsLabel => 'Key hints under the panels';

  @override
  String get generalKeyHintsNote =>
      'One line with the keys for what is under the cursor or selected';

  @override
  String get hintsHide => 'Hide the hints';

  @override
  String get hintsHidden =>
      'Hints are off; Settings, General turns them back on';

  @override
  String get hintBack => 'Back';

  @override
  String get hintKeepMatches => 'Keep the matches';

  @override
  String get copyDefaultsLabel => 'Copying';

  @override
  String get panelsShowHidden => 'Show hidden items';

  @override
  String get panelsParentEntry => 'Show the “..” row';

  @override
  String get panelsFoldersFirst => 'Folders before files';

  @override
  String get panelsExtensionlessFolders =>
      'Folders have no extension when sorting';

  @override
  String get panelsCollation => 'Compare names';

  @override
  String get panelsTabBarAlways => 'Always show the tab bar';

  @override
  String get quickSearchTitle => 'Quick search';

  @override
  String get quickSearchWhere => 'Where to search';

  @override
  String get quickSearchFuzzy => 'Fuzzy';

  @override
  String get quickSearchAnywhere => 'Anywhere';

  @override
  String get quickSearchBeginning => 'Beginning';

  @override
  String get quickSearchEnding => 'Ending';

  @override
  String get quickSearchBeginningOrEnding => 'Beginning or ending';

  @override
  String get quickSearchModifier => 'Key modifier';

  @override
  String get modifierNone => 'No modifier';

  @override
  String get modifierAlt => 'Option';

  @override
  String get modifierControlAlt => 'Control + Option';

  @override
  String get modifierShiftAlt => 'Shift + Option';

  @override
  String get modifierDisabled => 'Disabled';

  @override
  String get quickSearchOnlyMatching => 'Show only matching items';

  @override
  String get layoutsTitle => 'View modes';

  @override
  String get layoutName => 'Name';

  @override
  String get layoutMode => 'Mode';

  @override
  String get modeBrief => 'Brief';

  @override
  String get modeList => 'List';

  @override
  String get briefColumnsLabel => 'Columns';

  @override
  String get briefColumnsFixed => 'Three equal columns';

  @override
  String get briefColumnsDynamic => 'As wide as the names';

  @override
  String get columnsLabel => 'Columns';

  @override
  String get layoutsReset => 'Restore the default modes';

  @override
  String get viewerWrapLabel => 'Wrap long lines';

  @override
  String get viewerFontSizeLabel => 'Font size';

  @override
  String get hotkeysReset => 'Restore defaults';

  @override
  String get hotkeysResetOne => 'Restore default';

  @override
  String get hotkeysRecord => 'Press the new key…';

  @override
  String hotkeysRecordTitle(String command) {
    return 'Set a key for “$command”';
  }

  @override
  String hotkeysConflict(String command) {
    return 'Already used by “$command”';
  }

  @override
  String get hotkeysReassign => 'Reassign';

  @override
  String get hotkeysChanged => 'Changed from the default';

  @override
  String lengthPoints(int value) {
    return '$value pt';
  }

  @override
  String lengthPixels(int value) {
    return '$value px';
  }

  @override
  String get hotkeysUnbound => 'None';

  @override
  String get hotkeysSearchHint => 'Search commands';

  @override
  String get hotkeysChange => 'Change';

  @override
  String get hotkeysClear => 'Remove key';

  @override
  String get editorsIntro =>
      'F4 opens the focused file with the first editor whose mask matches its name.';

  @override
  String get editorName => 'Name';

  @override
  String get editorPath => 'Application';

  @override
  String get editorMask => 'File masks';

  @override
  String get editorInTerminal => 'Run in a terminal';

  @override
  String get editorsEmpty => 'No editors yet';

  @override
  String get editorsAdd => 'Add editor';

  @override
  String get editorAddTitle => 'New editor';

  @override
  String get editorEditTitle => 'Editor';

  @override
  String get toolsIntro =>
      'Tools run a program with the panels’ items as arguments: %p the focused path, %f its name, %r the panel’s folder, %P every selected path, %-… the other panel’s.';

  @override
  String get toolTitle => 'Title';

  @override
  String get toolPath => 'Program';

  @override
  String get toolParameters => 'Arguments';

  @override
  String get toolInTerminal => 'Run in a terminal';

  @override
  String get toolsEmpty => 'No tools yet';

  @override
  String get toolsAdd => 'Add tool';

  @override
  String get toolAddTitle => 'New tool';

  @override
  String get toolEditTitle => 'Tool';

  @override
  String get toolRun => 'Run';

  @override
  String get toolAskValueTitle => 'Value for the tool';

  @override
  String get choosePath => 'Choose…';

  @override
  String get cheatSheetTitle => 'Keyboard shortcuts';

  @override
  String get cheatSheetHint =>
      'Every key the window answers; change them in Settings → Hotkeys.';

  @override
  String get scopeGlobal => 'Everywhere';

  @override
  String get scopePanel => 'File panel';

  @override
  String get scopeViewer => 'Viewer';

  @override
  String get scopeLists => 'Lists';

  @override
  String get scopeDialogs => 'Dialogs';

  @override
  String get windowClose => 'Close';

  @override
  String get windowMinimize => 'Minimize';

  @override
  String get windowMaximize => 'Maximize';

  @override
  String get hintModeHint => 'Type a label to click it; Esc to leave';

  @override
  String get splitterTitle => 'Panel sizes';

  @override
  String get splitterHintArrows => 'Move the edge';

  @override
  String get splitterHintZero => 'Equal panels';

  @override
  String get splitterHintEnter => 'Keep';

  @override
  String get splitterHintEscape => 'Put back';

  @override
  String get singlePaneTooltip => 'Single panel';

  @override
  String get dualPaneTooltip => 'Two panels';

  @override
  String get panelLeft => 'Left panel';

  @override
  String get panelRight => 'Right panel';

  @override
  String get cmdNewFolder => 'New Folder';

  @override
  String get cmdNewFolderWithSelection => 'New Folder with Selection';

  @override
  String get cmdNewFile => 'New File';

  @override
  String get cmdNewTab => 'New Tab';

  @override
  String get cmdCloseTab => 'Close Tab';

  @override
  String get cmdCloseOtherTabs => 'Close Other Tabs';

  @override
  String get cmdReopenClosedTab => 'Reopen Closed Tab';

  @override
  String get cmdNextTab => 'Next Tab';

  @override
  String get cmdPreviousTab => 'Previous Tab';

  @override
  String get cmdToggleTabBar => 'Show Tab Bar';

  @override
  String get cmdOpenItem => 'Open';

  @override
  String get cmdRevealInOppositePanel => 'Reveal in Opposite Panel';

  @override
  String get cmdRevealInOppositeTab => 'Reveal in Opposite Panel Tab';

  @override
  String get cmdCalcFolderSizes => 'Calculate Folder Sizes';

  @override
  String get cmdCalcAllFolderSizes => 'Calculate All Folder Sizes';

  @override
  String get cmdDuplicate => 'Duplicate';

  @override
  String get cmdAddToFavorites => 'Add to Favorites';

  @override
  String get cmdManageFavorites => 'Manage Favorites…';

  @override
  String get cmdFindFiles => 'Find Files…';

  @override
  String get cmdCopyPaths => 'Copy';

  @override
  String get cmdPasteItems => 'Paste';

  @override
  String get cmdMoveItemsHere => 'Move Items Here';

  @override
  String get cmdSelectAll => 'Select All';

  @override
  String get cmdDeselectAll => 'Deselect All';

  @override
  String get cmdInvertSelection => 'Invert Selection';

  @override
  String get cmdSelectWithMask => 'Select with Mask…';

  @override
  String get cmdDeselectWithMask => 'Deselect with Mask…';

  @override
  String get cmdSelectWithExtension => 'Select with Extension';

  @override
  String get cmdDeselectWithExtension => 'Deselect with Extension';

  @override
  String get cmdToggleSinglePane => 'Toggle Single-Panel Mode';

  @override
  String get cmdSwapPanels => 'Swap Panels';

  @override
  String get cmdSyncPanels => 'Sync Panels';

  @override
  String cmdViewMode(int number) {
    return 'View Mode $number';
  }

  @override
  String get cmdSortByName => 'Sort by Name';

  @override
  String get cmdSortByExtension => 'Sort by Extension';

  @override
  String get cmdSortByModified => 'Sort by Modified Time';

  @override
  String get cmdSortBySize => 'Sort by Size';

  @override
  String get cmdSortByCreated => 'Sort by Creation Time';

  @override
  String get cmdSortByAdded => 'Sort by Added Time';

  @override
  String get cmdSortByAccessed => 'Sort by Accessed Time';

  @override
  String get cmdToggleFoldersFirst => 'Separate Folders from Files';

  @override
  String get cmdToggleExtensionlessFolders => 'Extensionless Folders';

  @override
  String get cmdCollationNatural => 'Natural Comparison';

  @override
  String get cmdCollationCaseInsensitive => 'Case-Insensitive Comparison';

  @override
  String get cmdCollationCaseSensitive => 'Case-Sensitive Comparison';

  @override
  String get cmdToggleHiddenFiles => 'Show Hidden Items';

  @override
  String get cmdPanelsMoveLeft => 'Move the Split Left';

  @override
  String get cmdPanelsMoveRight => 'Move the Split Right';

  @override
  String get cmdResizePanels => 'Resize Panels with the Keys';

  @override
  String get cmdRefresh => 'Refresh';

  @override
  String get cmdToggleOperations => 'Show Operations';

  @override
  String get cmdGoToLeftPanel => 'Go to… (Left Panel)';

  @override
  String get cmdGoToRightPanel => 'Go to… (Right Panel)';

  @override
  String get cmdGoBack => 'Back';

  @override
  String get cmdGoForward => 'Forward';

  @override
  String get cmdGoEnclosingFolder => 'Enclosing Folder';

  @override
  String get cmdGoInto => 'Enter';

  @override
  String get cmdFollowSymlink => 'Follow Symbolic Link';

  @override
  String get cmdGoDocuments => 'Documents';

  @override
  String get cmdGoDesktop => 'Desktop';

  @override
  String get cmdGoDownloads => 'Downloads';

  @override
  String get cmdGoHome => 'Home';

  @override
  String get cmdGoLibrary => 'Library';

  @override
  String get cmdGoApplications => 'Applications';

  @override
  String get cmdGoUtilities => 'Utilities';

  @override
  String get cmdGoRoot => 'Root';

  @override
  String get cmdQuickListParents => 'Enclosing Folders';

  @override
  String get cmdQuickListHistory => 'History';

  @override
  String get cmdQuickListFavorites => 'Favorites';

  @override
  String get cmdQuickListVolumes => 'Volumes';

  @override
  String get cmdGoToFolder => 'Go to Folder…';

  @override
  String get cmdFileAttributes => 'File Attributes…';

  @override
  String get cmdCopyItemName => 'Copy Item Name';

  @override
  String get cmdCopyItemPath => 'Copy Item Path';

  @override
  String get cmdCopyItemDirectory => 'Copy Item Folder';

  @override
  String get cmdPreview => 'Preview';

  @override
  String get cmdInternalViewer => 'Internal Viewer';

  @override
  String get cmdExternalEditor => 'External Editor';

  @override
  String get cmdEjectVolume => 'Eject Volume';

  @override
  String get cmdBatchRename => 'Batch Rename…';

  @override
  String get cmdCopyTo => 'Copy To…';

  @override
  String get cmdCopyAs => 'Copy As…';

  @override
  String get cmdMoveTo => 'Move To…';

  @override
  String get cmdMoveAs => 'Move As…';

  @override
  String get cmdRenameInPlace => 'Rename in Place';

  @override
  String get cmdCreateDirectory => 'Create Folder…';

  @override
  String get cmdCreateDirectoryInOppositePanel =>
      'Create Folder in Opposite Panel…';

  @override
  String get cmdMoveToTrash => 'Move to Trash';

  @override
  String get cmdDeleteItems => 'Delete…';

  @override
  String get cmdDeletePermanently => 'Delete Permanently…';

  @override
  String get cmdCompress => 'Compress…';

  @override
  String get cmdCompressTo => 'Compress To…';

  @override
  String get cmdCreateSymlink => 'Create Symbolic Link…';

  @override
  String get cmdCreateHardlink => 'Create Hard Link…';

  @override
  String get cmdEditSymlink => 'Edit Symbolic Link…';

  @override
  String get cmdRevealInFileManager => 'Show in File Manager';

  @override
  String get cmdOpenWith => 'Open With…';

  @override
  String get cmdFocusLeftPanel => 'Focus Left Panel';

  @override
  String get cmdFocusRightPanel => 'Focus Right Panel';

  @override
  String get cmdOpenSettings => 'Settings…';

  @override
  String get cmdHintMode => 'Click Hints';

  @override
  String get cmdCheatSheet => 'Keyboard Shortcuts';

  @override
  String get cmdContextMenu => 'Show Context Menu';

  @override
  String get cmdMoveUp => 'Move Up';

  @override
  String get cmdMoveDown => 'Move Down';

  @override
  String get cmdMoveLeft => 'Move Left';

  @override
  String get cmdMoveRight => 'Move Right';

  @override
  String get cmdMoveFirst => 'Move to the First Item';

  @override
  String get cmdMoveLast => 'Move to the Last Item';

  @override
  String get cmdScrollFirst => 'Scroll to the First Item';

  @override
  String get cmdScrollLast => 'Scroll to the Last Item';

  @override
  String get cmdMovePageUp => 'Move to the Previous Page';

  @override
  String get cmdMovePageDown => 'Move to the Next Page';

  @override
  String get cmdScrollPageUp => 'Scroll to the Previous Page';

  @override
  String get cmdScrollPageDown => 'Scroll to the Next Page';

  @override
  String get cmdSelectMoveUp => 'Select and Move Up';

  @override
  String get cmdSelectMoveDown => 'Select and Move Down';

  @override
  String get cmdSelectMoveLeft => 'Select and Move Left';

  @override
  String get cmdSelectMoveRight => 'Select and Move Right';

  @override
  String get cmdSelectMoveFirst => 'Select to the First Item';

  @override
  String get cmdSelectMoveLast => 'Select to the Last Item';

  @override
  String get cmdSelectMovePageUp => 'Select to the Previous Page';

  @override
  String get cmdSelectMovePageDown => 'Select to the Next Page';

  @override
  String get cmdToggleSelection => 'Toggle Selection';

  @override
  String get cmdToggleSelectionMoveDown => 'Toggle Selection and Move Down';

  @override
  String get cmdEnterItem => 'Enter';

  @override
  String get cmdGoParent => 'Go to the Enclosing Folder';

  @override
  String get cmdSwitchPanel => 'Change Active Panel';

  @override
  String get cmdShowPreview => 'Show Preview';

  @override
  String get cmdClearQuickSearch => 'Clear Quick Search';

  @override
  String cmdShowTab(int number) {
    return 'Show Tab $number';
  }

  @override
  String get cmdViewerText => 'Text';

  @override
  String get cmdViewerHex => 'Hex';

  @override
  String get cmdViewerPreview => 'Preview';

  @override
  String get cmdViewerGoTo => 'Go to Offset…';

  @override
  String get cmdViewerFind => 'Find…';

  @override
  String get cmdViewerFindNext => 'Find Next';

  @override
  String get cmdViewerFindPrevious => 'Find Previous';

  @override
  String get cmdViewerToggleWrap => 'Wrap Lines';

  @override
  String get cmdRenameItem => 'Rename';

  @override
  String get cmdDeleteItem => 'Delete';

  @override
  String get cmdFilterList => 'Filter';

  @override
  String get cmdMoveItemUp => 'Move Up';

  @override
  String get cmdVimVisual => 'Visual Selection';

  @override
  String get cmdVimSearch => 'Search in Panel';

  @override
  String get cmdVimSearchNext => 'Next Match';

  @override
  String get cmdVimSearchPrevious => 'Previous Match';

  @override
  String get cmdVimCommandLine => 'Command Line';

  @override
  String get cmdVimCut => 'Cut (Take to Move)';

  @override
  String get cmdVimYank => 'Yank (Take to Copy)';

  @override
  String get cmdVimPaste => 'Put Here';

  @override
  String get cmdVimCancelRegister => 'Let the Taken Rows Go';

  @override
  String get cmdVimFindChar => 'Jump to a Name by Its First Letter';

  @override
  String get cmdVimFindCharBack => 'Jump Back to a Name by Its First Letter';

  @override
  String get cmdVimRepeatFind => 'Repeat the Jump';

  @override
  String get cmdVimRepeatFindBack => 'Repeat the Jump Backwards';

  @override
  String get cmdVimSetMark => 'Set a Mark';

  @override
  String get cmdVimGoMark => 'Go to a Mark';

  @override
  String get cmdVimScreenTop => 'Top of the Screen';

  @override
  String get cmdVimScreenMiddle => 'Middle of the Screen';

  @override
  String get cmdVimScreenBottom => 'Bottom of the Screen';

  @override
  String get cmdVimScrollCenter => 'Scroll the Cursor to the Middle';

  @override
  String get cmdVimScrollTop => 'Scroll the Cursor to the Top';

  @override
  String get cmdVimScrollBottom => 'Scroll the Cursor to the Bottom';

  @override
  String get cmdVimHalfPageDown => 'Half a Page Down';

  @override
  String get cmdVimHalfPageUp => 'Half a Page Up';

  @override
  String get cmdVimColumnNext => 'Next Column';

  @override
  String get cmdVimColumnPrevious => 'Previous Column';

  @override
  String get cmdVimRenameAppend => 'Rename at the End of the Name';

  @override
  String get cmdVimRenamePrepend => 'Rename at the Start of the Name';

  @override
  String get cmdVimSortReverse => 'Reverse the Sort Order';

  @override
  String get cmdVimReselect => 'Reselect the Last Selection';

  @override
  String get cmdMoveItemDown => 'Move Down';

  @override
  String get cmdConfirm => 'Confirm';

  @override
  String get cmdDismiss => 'Dismiss';

  @override
  String get cmdCommandPalette => 'Command Palette';

  @override
  String get cmdJumpToFolder => 'Jump to a Frequent Folder';

  @override
  String get cmdAddToShelf => 'Add to the Shelf';

  @override
  String get cmdToggleShelf => 'Show or Hide the Shelf';

  @override
  String get cmdRenameInEditor => 'Rename in an Editor';

  @override
  String get paletteHint => 'Type a command';

  @override
  String get paletteNoResults => 'No command matches';

  @override
  String get paletteRecent => 'Recently used';

  @override
  String get paletteKeySelect => 'select';

  @override
  String get paletteKeyRun => 'run';

  @override
  String get paletteKeyClose => 'close';

  @override
  String get paletteSectionFile => 'File';

  @override
  String get paletteSectionEdit => 'Edit';

  @override
  String get paletteSectionView => 'View';

  @override
  String get paletteSectionGo => 'Go';

  @override
  String get paletteSectionCommand => 'Command';

  @override
  String get paletteSectionWindow => 'Window';

  @override
  String get paletteSectionPanel => 'File panel';

  @override
  String get paletteSectionVim => 'Vim';

  @override
  String get paletteSectionViewer => 'Viewer';

  @override
  String get paletteSectionLists => 'Lists';

  @override
  String get paletteSectionDialogs => 'Dialogs';

  @override
  String get jumpTitle => 'Jump to a frequent folder';

  @override
  String get jumpHint => 'Type parts of the folder’s path';

  @override
  String get jumpEmpty => 'The folders you open show here, the most used first';

  @override
  String get jumpNoResults => 'No folder you visited matches';

  @override
  String get jumpKeyOpen => 'open';

  @override
  String get jumpKeyNewTab => 'in a new tab';

  @override
  String get jumpKeyOtherPanel => 'in the other panel';

  @override
  String jumpGone(String path) {
    return '$path is gone; it is off the list now';
  }

  @override
  String jumpNoMatch(String query) {
    return 'No folder you visited matches “$query”';
  }

  @override
  String get shelfTitle => 'Shelf';

  @override
  String shelfNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count on the shelf',
      one: '1 on the shelf',
    );
    return '$_temp0';
  }

  @override
  String shelfAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items put on the shelf',
      one: '1 item put on the shelf',
    );
    return '$_temp0';
  }

  @override
  String shelfEmpty(String key) {
    return 'Gather files from any folder with $key, then copy or move them here together';
  }

  @override
  String get shelfClear => 'Clear';

  @override
  String get shelfCopyHere => 'Copy Here';

  @override
  String get shelfMoveHere => 'Move Here';

  @override
  String shelfInto(String folder) {
    return 'Into $folder';
  }

  @override
  String get shelfRemove => 'Take off the shelf';

  @override
  String get shelfMissing => 'no longer there';

  @override
  String shelfMissingTooltip(String path) {
    return '$path is no longer on disk';
  }

  @override
  String get shelfCutTooltip => 'Moved, not copied, when put';

  @override
  String get shelfAlreadyHere => 'The shelf’s items are in this folder already';

  @override
  String get shelfNothingToPut =>
      'None of the shelf’s items is on disk any more';

  @override
  String get shelfHintReveal => 'show in the panel';

  @override
  String get shelfHintRemove => 'take off';
}
