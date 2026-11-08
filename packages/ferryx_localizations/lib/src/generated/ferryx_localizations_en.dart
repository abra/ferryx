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
  String get hintsHelp => 'Shortcuts';

  @override
  String get commandsButton => 'Commands';

  @override
  String get menuHelp => 'Help';

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
  String get panelsArrangement => 'Panel arrangement';

  @override
  String get panelsArrangementByWindowShape => 'By the window’s shape';

  @override
  String get panelsArrangementSideBySide => 'Side by side';

  @override
  String get panelsArrangementStacked => 'One above the other';

  @override
  String get panelsArrangementHint =>
      'By the window’s shape: one above the other in a window taller than it is wide, as on a monitor turned upright';

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
  String get layoutShort => 'Short';

  @override
  String get layoutMedium => 'Medium';

  @override
  String get layoutFull => 'Full';

  @override
  String get layoutWide => 'Wide';

  @override
  String get layoutDetails => 'Details';

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
  String get cmdTogglePanelsStacked => 'Panels One Above the Other';

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
  String get cmdVimLeft => 'Column Left or Out of the Folder';

  @override
  String get cmdVimRight => 'Column Right or Into the Item';

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
  String get shelfRemove => 'Remove from the shelf';

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
  String get shelfHintReveal => 'Show in the panel';

  @override
  String get shelfHintRemove => 'Remove';

  @override
  String namesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Rename $count items',
      one: 'Rename 1 item',
    );
    return '$_temp0';
  }

  @override
  String namesHint(String apply, String newline) {
    return 'One name per line, in the order shown. $apply renames, $newline starts a new line.';
  }

  @override
  String namesToRename(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count to rename',
      one: '1 to rename',
      zero: 'Nothing renamed yet',
    );
    return '$_temp0';
  }

  @override
  String namesErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count errors',
      one: '1 error',
    );
    return '$_temp0';
  }

  @override
  String namesLineCount(int names, int lines) {
    return 'The names need $names lines; there are $lines';
  }

  @override
  String namesProblemEmpty(int line) {
    return 'Line $line: the name is empty';
  }

  @override
  String namesProblemSeparator(int line) {
    return 'Line $line: a name cannot hold “/”';
  }

  @override
  String namesProblemInvalid(int line) {
    return 'Line $line: no file can have this name';
  }

  @override
  String namesProblemDuplicate(int line, int other) {
    return 'Line $line: the same name as line $other';
  }

  @override
  String namesProblemExists(int line, String name) {
    return 'Line $line: “$name” is in this folder already';
  }

  @override
  String namesProblemExtra(int line) {
    return 'Line $line: there is no item for this line';
  }

  @override
  String namesProblemMissing(int line) {
    return 'Line $line: this item has no line';
  }

  @override
  String get namesShortEmpty => 'empty';

  @override
  String get namesShortSeparator => 'has /';

  @override
  String get namesShortInvalid => 'not a name';

  @override
  String get namesShortDuplicate => 'repeated';

  @override
  String get namesShortExists => 'taken';

  @override
  String get namesShortExtra => 'extra';

  @override
  String get namesShortMissing => 'no line';

  @override
  String get namesDiscardTitle => 'Discard the new names?';

  @override
  String get namesDiscardMessage =>
      'The names you typed are lost; nothing is renamed.';

  @override
  String get namesDiscard => 'Discard';

  @override
  String get namesKeepEditing => 'Keep Editing';

  @override
  String get cmdQuickLook => 'Quick Look';

  @override
  String get cmdShare => 'Share…';

  @override
  String get nativeUnavailable => 'Not available on this desktop';

  @override
  String get quickLookNothing => 'Nothing here to look at';

  @override
  String quickLookTooLarge(String name) {
    return '“$name” is too large to look at from an archive';
  }

  @override
  String get dropIntoItself => 'A folder cannot go into itself';

  @override
  String get dropNoFiles => 'Only files and folders can be dropped here';

  @override
  String get cmdToggleTerminal => 'Terminal Over the Whole Window';

  @override
  String get cmdShowTerminal => 'Show Terminal';

  @override
  String get cmdHideTerminal => 'Hide Terminal';

  @override
  String get cmdTogglePanelsOverTerminal => 'Hide or Show the Panels';

  @override
  String get cmdTerminalCopy => 'Copy';

  @override
  String get cmdTerminalPaste => 'Paste';

  @override
  String get cmdTerminalSelectAll => 'Select All';

  @override
  String get cmdTerminalClear => 'Clear';

  @override
  String get cmdTerminalScrollPageUp => 'Scroll a Page Up';

  @override
  String get cmdTerminalScrollPageDown => 'Scroll a Page Down';

  @override
  String get scopeTerminal => 'Terminal';

  @override
  String get settingsTerminal => 'Terminal';

  @override
  String get terminalShellLabel => 'Shell';

  @override
  String terminalShellDefault(String shell) {
    return 'Default: $shell';
  }

  @override
  String get terminalShellNote =>
      'A path or a name on PATH, run as a login shell; the next shell started takes it';

  @override
  String get terminalFontSizeLabel => 'Font size';

  @override
  String get terminalFontLabel => 'Font';

  @override
  String get terminalFontSystem => 'System';

  @override
  String get terminalFontPreview => 'Preview';

  @override
  String get terminalFontSample => 'Aa Бб 0O 1lI\n0123456789 {} [] →';

  @override
  String get terminalFontsLoading => 'Loading fonts…';

  @override
  String get terminalFontsLoadFailed => 'Could not load installed fonts.';

  @override
  String get terminalFontUnavailable => 'Not installed; using the system font.';

  @override
  String get terminalScrollbackLabel => 'Lines kept to scroll back';

  @override
  String terminalLineCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString lines',
      one: '$countString line',
    );
    return '$_temp0';
  }

  @override
  String get terminalHeightTitle => 'Terminal height';

  @override
  String get terminalHeightHintArrows => 'Line by line';

  @override
  String get terminalHeightHintZero => 'Default height';

  @override
  String get terminalExited => 'The shell has ended';

  @override
  String terminalExitedWithCode(int code) {
    return 'The shell has ended with code $code';
  }

  @override
  String get terminalStartFailed => 'The shell could not start';

  @override
  String get terminalRestart => 'New Shell';

  @override
  String terminalRestartHint(String key) {
    return '$key starts a new shell';
  }

  @override
  String get terminalTitle => 'Terminal';

  @override
  String get terminalBusy =>
      'A program runs in the terminal, or a line is half typed';

  @override
  String get terminalScrollbackNote => 'A new shell keeps this many';

  @override
  String get paletteSectionTerminal => 'Terminal';

  @override
  String get cmdCompareFolders => 'Compare Folders';

  @override
  String get cmdSynchronizeFolders => 'Synchronize Folders…';

  @override
  String get cmdUndo => 'Undo';

  @override
  String get cmdRedo => 'Redo';

  @override
  String get cmdChecksums => 'Checksums…';

  @override
  String get cmdFindDuplicates => 'Find Duplicates…';

  @override
  String opSynchronizeTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Synchronizing $count items',
      one: 'Synchronizing 1 item',
    );
    return '$_temp0';
  }

  @override
  String opCompareContentsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Comparing $count pairs of files',
      one: 'Comparing 1 pair of files',
    );
    return '$_temp0';
  }

  @override
  String opUndoTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Undoing $count changes',
      one: 'Undoing 1 change',
    );
    return '$_temp0';
  }

  @override
  String opRedoTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Redoing $count changes',
      one: 'Redoing 1 change',
    );
    return '$_temp0';
  }

  @override
  String compareSelected(String left, String right) {
    return 'Selected $left on the left, $right on the right';
  }

  @override
  String get compareSame => 'The folders hold the same files';

  @override
  String get compareNeedsFolders => 'Both panels need to show a folder';

  @override
  String get compareSameFolder => 'Both panels show the same folder';

  @override
  String compareContentsStarted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Comparing the contents of $count pairs of files…',
      one: 'Comparing the contents of 1 pair of files…',
    );
    return '$_temp0';
  }

  @override
  String get compareContentsNotHere =>
      'Contents are compared for folders on disk only; compared by size and date';

  @override
  String get compareGroupLabel => 'Compare Folders';

  @override
  String get compareContentsSetting =>
      'Compare the contents of files of the same size';

  @override
  String journalWhatOne(String name) {
    return '“$name”';
  }

  @override
  String journalWhatMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String journalStepCopy(String what) {
    return 'Copy of $what';
  }

  @override
  String journalStepMove(String what) {
    return 'Move of $what';
  }

  @override
  String journalStepTrash(String what) {
    return 'Move to Trash of $what';
  }

  @override
  String journalStepRename(String what) {
    return 'Rename of $what';
  }

  @override
  String journalStepCreateFolder(String what) {
    return 'New Folder $what';
  }

  @override
  String journalStepCreateFile(String what) {
    return 'New File $what';
  }

  @override
  String journalStepCreateLink(String what) {
    return 'New Link $what';
  }

  @override
  String journalStepDuplicate(String what) {
    return 'Duplicate of $what';
  }

  @override
  String journalStepCompress(String what) {
    return 'Compress of $what';
  }

  @override
  String journalStepExtract(String what) {
    return 'Extract of $what';
  }

  @override
  String journalStepSynchronize(String what) {
    return 'Synchronize of $what';
  }

  @override
  String undoMenu(String step) {
    return 'Undo $step';
  }

  @override
  String redoMenu(String step) {
    return 'Redo $step';
  }

  @override
  String undoCardTitle(String step) {
    return 'Undo $step';
  }

  @override
  String redoCardTitle(String step) {
    return 'Redo $step';
  }

  @override
  String get undoNothing => 'Nothing to undo';

  @override
  String get redoNothing => 'Nothing to redo';

  @override
  String get undoMoved => 'Something else changed the files first; try again';

  @override
  String undoDialogTitle(String step) {
    return 'Undo $step?';
  }

  @override
  String redoDialogTitle(String step) {
    return 'Redo $step?';
  }

  @override
  String undoPartly(int doable, int total) {
    return '$doable of $total changes can be undone. These cannot:';
  }

  @override
  String redoPartly(int doable, int total) {
    return '$doable of $total changes can be redone. These cannot:';
  }

  @override
  String get undoNone => 'None of its changes can be undone any more:';

  @override
  String get redoNone => 'None of its changes can be redone any more:';

  @override
  String get undoWarnings => 'It can be undone, but note:';

  @override
  String get redoWarnings => 'It can be redone, but note:';

  @override
  String get undoIssueMissing => 'No longer there';

  @override
  String get undoIssueOccupied => 'Its place is taken';

  @override
  String get undoIssueChanged =>
      'Changed since; it goes to the Trash all the same';

  @override
  String get undoIssueLost =>
      'Overwritten: its earlier contents are gone, it stays as it is';

  @override
  String get undoIssueNotInTrash => 'No longer in the Trash';

  @override
  String get undoIssueUnsupported =>
      'Items cannot be put back from the Trash here';

  @override
  String get undoIssueTruncated => 'Too many items changed to undo';

  @override
  String undoMoreIssues(int count) {
    return '…and $count more';
  }

  @override
  String get undoAction => 'Undo';

  @override
  String get redoAction => 'Redo';

  @override
  String get undoForget => 'Forget Step';

  @override
  String get undoForgotten => 'The step is forgotten';

  @override
  String get syncTitle => 'Synchronize folders';

  @override
  String get syncLeft => 'Left folder';

  @override
  String get syncRight => 'Right folder';

  @override
  String get syncSwap => 'Swap the folders';

  @override
  String get syncSubfolders => 'Include subfolders';

  @override
  String get syncByContent => 'Compare contents';

  @override
  String get syncFatTime => 'Ignore time differences up to 2 s';

  @override
  String get syncHidden => 'Hidden files';

  @override
  String get syncMask => 'Files';

  @override
  String get syncMaskHint => 'All files, or a mask: *.jpg;*.png';

  @override
  String get syncDirection => 'Direction';

  @override
  String get syncBothWays => 'Both ways';

  @override
  String get syncLeftToRight => 'Left to right';

  @override
  String get syncRightToLeft => 'Right to left';

  @override
  String get syncDelete => 'Delete what the source lacks';

  @override
  String get syncShow => 'Show';

  @override
  String get syncFilterLeftOnly => 'Left only';

  @override
  String get syncFilterRightOnly => 'Right only';

  @override
  String get syncFilterNewer => 'Newer';

  @override
  String get syncFilterDifferent => 'Different';

  @override
  String get syncFilterIdentical => 'Identical';

  @override
  String get syncColumnLeft => 'Left';

  @override
  String get syncColumnRight => 'Right';

  @override
  String syncItemsCompared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items compared',
      one: '1 item compared',
    );
    return '$_temp0';
  }

  @override
  String syncToRight(String count) {
    return 'To the right: $count';
  }

  @override
  String syncToLeft(String count) {
    return 'To the left: $count';
  }

  @override
  String syncToDelete(String count) {
    return 'To delete: $count';
  }

  @override
  String syncBytes(String size) {
    return '$size to copy';
  }

  @override
  String get syncNothingToDo => 'Nothing to synchronize';

  @override
  String get syncIdentical => 'The folders are identical';

  @override
  String syncUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count folders could not be read',
      one: '1 folder could not be read',
    );
    return '$_temp0';
  }

  @override
  String syncError(String message) {
    return 'Could not compare: $message';
  }

  @override
  String get syncSameFolder => 'The left and right folders are the same';

  @override
  String get syncStartHint => 'Choose the folders and press Compare';

  @override
  String get syncNoRows => 'Nothing to show with these filters';

  @override
  String get syncCompare => 'Compare';

  @override
  String get syncSynchronize => 'Synchronize…';

  @override
  String get syncActionCopyRight => 'Copy to the Right';

  @override
  String get syncActionCopyLeft => 'Copy to the Left';

  @override
  String get syncActionDeleteLeft => 'Delete on the Left';

  @override
  String get syncActionDeleteRight => 'Delete on the Right';

  @override
  String get syncActionSkip => 'Leave as Is';

  @override
  String get syncActionDefault => 'Suggested Action';

  @override
  String get syncStateEqual => 'Identical';

  @override
  String get syncStateDifferent => 'Different, neither is newer';

  @override
  String get syncStateConflict => 'A file on one side, a folder on the other';

  @override
  String get syncStateSkipped => 'Left as is';

  @override
  String get syncConfirmTitle => 'Synchronize the folders?';

  @override
  String syncConfirmDelete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items go to the Trash.',
      one: '1 item goes to the Trash.',
    );
    return '$_temp0';
  }

  @override
  String syncConfirmOverwrite(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files are replaced; their earlier versions are lost.',
      one: '1 file is replaced; its earlier version is lost.',
    );
    return '$_temp0';
  }

  @override
  String syncConfirmUndo(String key) {
    return '$key undoes it: the copies go to the Trash.';
  }

  @override
  String get syncSynchronizeNow => 'Synchronize';

  @override
  String syncKeysHint(String space, String right, String left) {
    return '$space changes the action, $right and $left choose a side';
  }

  @override
  String get checksumTitle => 'Checksums';

  @override
  String checksumVerifyTitle(String name) {
    return 'Check $name';
  }

  @override
  String get checksumAlgorithm => 'Algorithm';

  @override
  String get checksumModeCalculate => 'Calculate';

  @override
  String get checksumModeVerify => 'Verify';

  @override
  String get checksumSubfolders => 'Include subfolders';

  @override
  String get checksumExpected => 'Expected hash';

  @override
  String get checksumExpectedHint => 'Paste a hash to look for it';

  @override
  String checksumMatch(String name) {
    return 'Matches $name';
  }

  @override
  String checksumMatchMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Matches $count files',
      one: 'Matches 1 file',
    );
    return '$_temp0';
  }

  @override
  String get checksumNoMatch => 'No file has this hash';

  @override
  String get checksumColumnHash => 'Hash';

  @override
  String get checksumColumnStatus => 'Status';

  @override
  String get checksumStatusOk => 'OK';

  @override
  String get checksumStatusMismatch => 'Mismatch';

  @override
  String get checksumStatusMissing => 'Missing';

  @override
  String get checksumStatusError => 'Unreadable';

  @override
  String get checksumPending => 'Waiting';

  @override
  String checksumFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
      zero: 'No files',
    );
    return '$_temp0';
  }

  @override
  String checksumVerifySummary(String ok, String mismatch, String missing) {
    return '$ok OK, $mismatch mismatched, $missing missing';
  }

  @override
  String checksumBadLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines were not understood',
      one: '1 line was not understood',
    );
    return '$_temp0';
  }

  @override
  String checksumError(String message) {
    return 'Could not check: $message';
  }

  @override
  String get checksumCopyHash => 'Copy Hash';

  @override
  String get checksumCopyLine => 'Copy Line';

  @override
  String get checksumCopyAll => 'Copy All';

  @override
  String get checksumSave => 'Save Checksum File…';

  @override
  String get checksumSaveTitle => 'Save checksum file';

  @override
  String checksumSaveExists(String name) {
    return '“$name” already exists. Replace it?';
  }

  @override
  String get checksumReplace => 'Replace';

  @override
  String checksumSaved(String name) {
    return 'Saved $name';
  }

  @override
  String checksumCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hashes copied',
      one: 'Hash copied',
    );
    return '$_temp0';
  }

  @override
  String get checksumNoFiles => 'No files to hash';

  @override
  String get dupesTitle => 'Find duplicates';

  @override
  String get dupesIn => 'Look in';

  @override
  String dupesAlsoIn(String path) {
    return 'Also in $path';
  }

  @override
  String get dupesMinSize => 'At least';

  @override
  String get dupesNames => 'Names';

  @override
  String dupesScanning(String count) {
    return 'Looking through files: $count';
  }

  @override
  String dupesComparing(String done, String total) {
    return 'Comparing files: $done of $total';
  }

  @override
  String dupesRead(String size) {
    return '$size read';
  }

  @override
  String dupesGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count groups of duplicates',
      one: '1 group of duplicates',
      zero: 'No duplicates',
    );
    return '$_temp0';
  }

  @override
  String dupesWasted(String size) {
    return '$size can be freed';
  }

  @override
  String dupesGroupHeader(String size, int count) {
    return '$size × $count';
  }

  @override
  String get dupesMark => 'Mark';

  @override
  String get dupesMarkAllButNewest => 'All but the Newest in Each Group';

  @override
  String get dupesMarkAllButOldest => 'All but the Oldest in Each Group';

  @override
  String get dupesMarkAllButShortest =>
      'All but the Shortest Path in Each Group';

  @override
  String get dupesUnmarkAll => 'Unmark All';

  @override
  String dupesMarked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files marked',
      one: '1 file marked',
    );
    return '$_temp0';
  }

  @override
  String get dupesReveal => 'Show in Panel';

  @override
  String get dupesCopyPaths => 'Copy Paths';

  @override
  String dupesTrashTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Move $count files to the Trash?',
      one: 'Move 1 file to the Trash?',
    );
    return '$_temp0';
  }

  @override
  String dupesTrashBody(String size, String key) {
    return '$size is freed once the Trash is emptied; Undo ($key) puts the files back.';
  }

  @override
  String dupesTrashAllCopies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'In $count groups every copy is marked: none of them stays.',
      one: 'In 1 group every copy is marked: none of them stays.',
    );
    return '$_temp0';
  }

  @override
  String get dupesNone => 'No duplicates found';

  @override
  String get dupesStartHint => 'Choose where to look and press Find';

  @override
  String dupesError(String message) {
    return 'Could not search: $message';
  }

  @override
  String dupesKeysHint(String space) {
    return '$space marks a file';
  }

  @override
  String get dupesMarkColumn => 'Mark';

  @override
  String get dupesUnmark => 'Unmark';

  @override
  String get cmdExtractTo => 'Extract To…';

  @override
  String get cmdToggleFlatView => 'Flat View';

  @override
  String get cmdEditTags => 'Tags…';

  @override
  String get archivePasswordRequired => 'A password is needed';

  @override
  String get archiveWrongPassword => 'Wrong password';

  @override
  String archiveExtractOneTitle(String name) {
    return 'Extract “$name” to';
  }

  @override
  String archiveExtractManyTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Extract $count archives to',
      one: 'Extract $count archive to',
    );
    return '$_temp0';
  }

  @override
  String archiveExtractMembersTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Extract $count items to',
      one: 'Extract $count item to',
    );
    return '$_temp0';
  }

  @override
  String get archiveIntoFolders => 'Into a folder named after each archive';

  @override
  String archiveIntoFolder(String name) {
    return 'Into a folder named “$name”';
  }

  @override
  String get archivePasswordLabel => 'Password';

  @override
  String archiveWrongPasswordFor(String name) {
    return 'This password does not open “$name”';
  }

  @override
  String get archiveExtractAction => 'Extract';

  @override
  String get archiveNoArchives => 'None of the items is an archive';

  @override
  String archivePasswordTitle(String name) {
    return '“$name” is encrypted';
  }

  @override
  String get archivePasswordMessage =>
      'Enter the password to open the archive.';

  @override
  String get archivePasswordOpen => 'Open';

  @override
  String get archiveEnterPassword => 'Enter Password…';

  @override
  String archiveDestinationHint(String key) {
    return '$key completes a folder’s name';
  }

  @override
  String get flatCapsule => 'Flat';

  @override
  String get flatLeave => 'Back to the folder';

  @override
  String get flatWalking => 'Reading the folder’s tree';

  @override
  String flatFileCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString files',
      one: '$countString file',
      zero: 'no files',
    );
    return '$_temp0';
  }

  @override
  String flatCappedCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'the first $countString files',
      one: 'the first $countString file',
    );
    return '$_temp0';
  }

  @override
  String flatRowLabel(String name, String folder) {
    return '$name, in $folder';
  }

  @override
  String get tagsMenuTitle => 'Tags';

  @override
  String get tagColorRed => 'Red';

  @override
  String get tagColorOrange => 'Orange';

  @override
  String get tagColorYellow => 'Yellow';

  @override
  String get tagColorGreen => 'Green';

  @override
  String get tagColorBlue => 'Blue';

  @override
  String get tagColorPurple => 'Purple';

  @override
  String get tagColorGray => 'Gray';

  @override
  String get tagsNew => 'New Tag…';

  @override
  String get tagsNewTitle => 'New tag';

  @override
  String get tagsNameLabel => 'Name';

  @override
  String get tagsColorLabel => 'Color';

  @override
  String get tagsColorNone => 'None';

  @override
  String get tagsAdd => 'Add';

  @override
  String tagsList(String first, String second) {
    return '$first, $second';
  }

  @override
  String tagsRowLabel(String label, String tags) {
    return '$label, tags: $tags';
  }

  @override
  String tagsFailed(int count, String reason) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'The tags of $count items could not be changed: $reason',
      one: 'The tags of $count item could not be changed: $reason',
    );
    return '$_temp0';
  }

  @override
  String get findSpotlight => 'Use the Spotlight index';

  @override
  String get findSpotlightNote =>
      'Faster, but Spotlight skips system folders, hidden folders and the folders excluded in System Settings.';

  @override
  String get findSpotlightFailed =>
      'Spotlight could not search here: the folders were searched instead.';

  @override
  String get noticeNotInFlat =>
      'This works on one folder’s items; leave the flat view first';

  @override
  String get cmdConnectToServer => 'Connect to Server…';

  @override
  String get cmdDisconnectServer => 'Disconnect';

  @override
  String get errorAuthFailed => 'The server refused the login';

  @override
  String get errorHostUnreachable => 'The server cannot be reached';

  @override
  String get errorTimedOut => 'The server did not answer in time';

  @override
  String get errorHostKeyUnknown => 'The server’s key was not trusted';

  @override
  String get errorHostKeyChanged => 'The server’s key has changed';

  @override
  String get errorConnectionLost => 'The connection to the server dropped';

  @override
  String get errorNotConnected => 'Not connected to the server';

  @override
  String get errorCertificateInvalid =>
      'The server’s certificate is not trusted';

  @override
  String get networkConnectTitle => 'Connect to server';

  @override
  String get networkAddressLabel => 'Address';

  @override
  String get networkAddressHint => 'sftp://user@host/folder';

  @override
  String get networkAddressNote =>
      'SFTP, FTP, FTPS (ftps://), WebDAV (dav:// or davs://, http://, https://).';

  @override
  String get networkSavedServers => 'Saved Servers';

  @override
  String get networkNoServers =>
      'No saved servers yet. Type an address above, or add a server.';

  @override
  String get networkAddServer => 'Add Server…';

  @override
  String get networkEditServer => 'Edit…';

  @override
  String get networkRemoveServer => 'Remove';

  @override
  String networkRemoveServerTitle(String name) {
    return 'Remove “$name”?';
  }

  @override
  String get networkRemoveServerMessage =>
      'Its saved password stays in the keychain until you forget it in its settings.';

  @override
  String get networkConnect => 'Connect';

  @override
  String networkConnecting(String server) {
    return 'Connecting to $server…';
  }

  @override
  String get networkInsecure =>
      'Not encrypted: names, passwords and files cross the network in the clear.';

  @override
  String get networkServerNew => 'New Server';

  @override
  String get networkServerEdit => 'Server Settings';

  @override
  String get networkFieldName => 'Name';

  @override
  String get networkFieldNameHint => 'The host when empty';

  @override
  String get networkFieldProtocol => 'Protocol';

  @override
  String get networkFieldHost => 'Host';

  @override
  String get networkFieldPort => 'Port';

  @override
  String get networkFieldUser => 'User';

  @override
  String get networkFieldUserHint => 'Anonymous when empty';

  @override
  String get networkFieldFolder => 'Folder';

  @override
  String get networkFieldFolderHint => 'The server’s start folder';

  @override
  String get networkFieldAuth => 'Log in with';

  @override
  String get networkFieldKey => 'Key file';

  @override
  String get networkFieldKeyHint => '~/.ssh/id_ed25519';

  @override
  String get networkAuthAutomatic => 'Keys or password';

  @override
  String get networkAuthPassword => 'Password';

  @override
  String get networkAuthKey => 'Key file';

  @override
  String get networkAuthAgent => 'SSH agent';

  @override
  String get networkProtocolSftp => 'SFTP (SSH)';

  @override
  String get networkProtocolFtp => 'FTP';

  @override
  String get networkProtocolFtps => 'FTPS (FTP with TLS)';

  @override
  String get networkProtocolDav => 'WebDAV (HTTP)';

  @override
  String get networkProtocolDavs => 'WebDAV (HTTPS)';

  @override
  String get networkHostRequired => 'Enter the server’s host name or address';

  @override
  String get networkPortInvalid => 'A port is a number from 1 to 65535';

  @override
  String get networkForgetPassword => 'Forget Saved Password';

  @override
  String networkPasswordForgotten(String server) {
    return 'The saved password for $server is forgotten';
  }

  @override
  String networkPasswordTitle(String server) {
    return 'Log in to $server';
  }

  @override
  String networkPasswordMessage(String user) {
    return 'Enter the password for the user “$user”.';
  }

  @override
  String get networkPasswordWrong =>
      'The password was not accepted. Try again.';

  @override
  String get networkPasswordLabel => 'Password';

  @override
  String get networkRememberPassword => 'Remember in the system keychain';

  @override
  String get networkPassphraseTitle => 'Unlock the key';

  @override
  String networkPassphraseMessage(String key) {
    return 'The key $key is protected by a passphrase.';
  }

  @override
  String get networkPassphraseWrong =>
      'The passphrase did not unlock the key. Try again.';

  @override
  String get networkPassphraseLabel => 'Passphrase';

  @override
  String networkPromptsTitle(String server) {
    return 'Log in to $server';
  }

  @override
  String get networkContinue => 'Continue';

  @override
  String get networkHostKeyTitle => 'Unknown server';

  @override
  String networkHostKeyMessage(String host, String algorithm) {
    return 'Ferryx has not connected to $host before. Its $algorithm key has this fingerprint:';
  }

  @override
  String get networkHostKeyAdvice =>
      'Trust it only when the fingerprint is the one the server’s administrator gave you.';

  @override
  String get networkHostKeyRemember => 'Remember this key';

  @override
  String get networkHostKeyTrust => 'Trust';

  @override
  String get networkHostKeyChangedTitle =>
      'Warning: the server’s key has changed';

  @override
  String networkHostKeyChangedMessage(String host) {
    return 'The key that $host presented is not the one on record. Someone may be intercepting the connection — or the server was reinstalled. Ferryx will not connect.';
  }

  @override
  String get networkHostKeyChangedAdvice =>
      'If the server’s administrator confirms the new key, remove the old one from the known_hosts file named below, then connect again.';

  @override
  String networkStateConnected(String server) {
    return 'Connected to $server';
  }

  @override
  String networkStateLost(String server) {
    return 'The connection to $server dropped; the next action tries again';
  }

  @override
  String networkStateClosed(String server) {
    return 'Not connected to $server';
  }

  @override
  String networkStateInsecure(String state) {
    return '$state (not encrypted)';
  }

  @override
  String get networkReconnect => 'Reconnect';

  @override
  String networkDisconnected(String server) {
    return 'Disconnected from $server';
  }

  @override
  String get networkNotOnServer =>
      'This works with files on this computer only';

  @override
  String get networkNoTrash => 'A server has no Trash to put them in.';

  @override
  String networkOpenedCopy(String name) {
    return 'Opened a copy of “$name”: changes to it are not sent back to the server';
  }

  @override
  String networkNotAnAddress(String text) {
    return 'Not a server address: $text';
  }

  @override
  String get networkGoToServers => 'Servers';

  @override
  String get networkNotRemote => 'The panel is not on a server';

  @override
  String get networkRecent => 'Recent';

  @override
  String get networkCapsuleLost => 'Connection lost';

  @override
  String get networkCapsuleClosed => 'Not connected';

  @override
  String syncConfirmUndoDeleted(String key) {
    return '$key undoes it: the copies go to the Trash and what went there comes back.';
  }
}
