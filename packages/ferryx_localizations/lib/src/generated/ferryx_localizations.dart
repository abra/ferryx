import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'ferryx_localizations_en.dart';
import 'ferryx_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of FerryxLocalizations
/// returned by `FerryxLocalizations.of(context)`.
///
/// Applications need to include `FerryxLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/ferryx_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: FerryxLocalizations.localizationsDelegates,
///   supportedLocales: FerryxLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the FerryxLocalizations.supportedLocales
/// property.
abstract class FerryxLocalizations {
  FerryxLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static FerryxLocalizations of(BuildContext context) {
    return Localizations.of<FerryxLocalizations>(context, FerryxLocalizations)!;
  }

  static const LocalizationsDelegate<FerryxLocalizations> delegate =
      _FerryxLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Ferryx'**
  String get appTitle;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version} · macOS, Windows, Linux'**
  String aboutVersion(String version);

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'A dual-pane file manager built for the keyboard: two panels, tabs, background operations, archives, a viewer and a find.'**
  String get aboutDescription;

  /// No description provided for @aboutLicense.
  ///
  /// In en, this message translates to:
  /// **'Free and open source.'**
  String get aboutLicense;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get actionOk;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get actionApply;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// No description provided for @actionMove.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get actionMove;

  /// No description provided for @actionRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get actionRename;

  /// No description provided for @actionCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get actionCreate;

  /// No description provided for @actionOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get actionOpen;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// No description provided for @actionSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get actionSkip;

  /// No description provided for @actionOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get actionOverwrite;

  /// No description provided for @actionKeepBoth.
  ///
  /// In en, this message translates to:
  /// **'Keep both'**
  String get actionKeepBoth;

  /// No description provided for @actionMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get actionMerge;

  /// No description provided for @actionStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get actionStop;

  /// No description provided for @actionPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get actionPause;

  /// No description provided for @actionResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get actionResume;

  /// No description provided for @actionSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get actionSearch;

  /// No description provided for @actionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionAdd;

  /// No description provided for @actionRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get actionRemove;

  /// No description provided for @actionReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get actionReset;

  /// No description provided for @actionGo.
  ///
  /// In en, this message translates to:
  /// **'Go'**
  String get actionGo;

  /// No description provided for @actionCompress.
  ///
  /// In en, this message translates to:
  /// **'Compress'**
  String get actionCompress;

  /// No description provided for @actionSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get actionSelect;

  /// No description provided for @actionDeselect.
  ///
  /// In en, this message translates to:
  /// **'Deselect'**
  String get actionDeselect;

  /// No description provided for @actionView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get actionView;

  /// No description provided for @actionEject.
  ///
  /// In en, this message translates to:
  /// **'Eject'**
  String get actionEject;

  /// No description provided for @actionClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get actionClear;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// Two short facts side by side (a size and a date, a count and the free space).
  ///
  /// In en, this message translates to:
  /// **'{first} · {second}'**
  String joinedDetails(String first, String second);

  /// No description provided for @answerOverwriteAll.
  ///
  /// In en, this message translates to:
  /// **'Overwrite all'**
  String get answerOverwriteAll;

  /// No description provided for @answerOverwriteOlderAll.
  ///
  /// In en, this message translates to:
  /// **'Overwrite older'**
  String get answerOverwriteOlderAll;

  /// No description provided for @answerSkipAll.
  ///
  /// In en, this message translates to:
  /// **'Skip all'**
  String get answerSkipAll;

  /// No description provided for @answerKeepBothAll.
  ///
  /// In en, this message translates to:
  /// **'Keep both for all'**
  String get answerKeepBothAll;

  /// No description provided for @answerMergeAll.
  ///
  /// In en, this message translates to:
  /// **'Merge all'**
  String get answerMergeAll;

  /// No description provided for @errorNotFound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get errorNotFound;

  /// No description provided for @errorPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied'**
  String get errorPermissionDenied;

  /// No description provided for @errorAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Already exists'**
  String get errorAlreadyExists;

  /// No description provided for @errorNotADirectory.
  ///
  /// In en, this message translates to:
  /// **'Not a folder'**
  String get errorNotADirectory;

  /// No description provided for @errorIsADirectory.
  ///
  /// In en, this message translates to:
  /// **'Is a folder'**
  String get errorIsADirectory;

  /// No description provided for @errorNotEmpty.
  ///
  /// In en, this message translates to:
  /// **'The folder is not empty'**
  String get errorNotEmpty;

  /// No description provided for @errorUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Not supported here'**
  String get errorUnsupported;

  /// No description provided for @errorCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get errorCancelled;

  /// No description provided for @errorInvalidName.
  ///
  /// In en, this message translates to:
  /// **'Not a valid name'**
  String get errorInvalidName;

  /// No description provided for @errorInvalidPattern.
  ///
  /// In en, this message translates to:
  /// **'Not a valid pattern'**
  String get errorInvalidPattern;

  /// No description provided for @errorIo.
  ///
  /// In en, this message translates to:
  /// **'Could not complete'**
  String get errorIo;

  /// No description provided for @errorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorTitle;

  /// No description provided for @sizeBytes.
  ///
  /// In en, this message translates to:
  /// **'{bytes} B'**
  String sizeBytes(int bytes);

  /// No description provided for @sizeKilobytes.
  ///
  /// In en, this message translates to:
  /// **'{value} KB'**
  String sizeKilobytes(String value);

  /// No description provided for @sizeMegabytes.
  ///
  /// In en, this message translates to:
  /// **'{value} MB'**
  String sizeMegabytes(String value);

  /// No description provided for @sizeGigabytes.
  ///
  /// In en, this message translates to:
  /// **'{value} GB'**
  String sizeGigabytes(String value);

  /// No description provided for @sizeTerabytes.
  ///
  /// In en, this message translates to:
  /// **'{value} TB'**
  String sizeTerabytes(String value);

  /// No description provided for @relativeToday.
  ///
  /// In en, this message translates to:
  /// **'Today, {time}'**
  String relativeToday(String time);

  /// No description provided for @relativeYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday, {time}'**
  String relativeYesterday(String time);

  /// No description provided for @columnName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get columnName;

  /// No description provided for @columnExtension.
  ///
  /// In en, this message translates to:
  /// **'Extension'**
  String get columnExtension;

  /// No description provided for @columnSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get columnSize;

  /// No description provided for @columnModified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get columnModified;

  /// No description provided for @columnCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get columnCreated;

  /// No description provided for @columnAdded.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get columnAdded;

  /// No description provided for @columnAccessed.
  ///
  /// In en, this message translates to:
  /// **'Accessed'**
  String get columnAccessed;

  /// No description provided for @columnPermissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get columnPermissions;

  /// No description provided for @columnOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get columnOwner;

  /// No description provided for @columnGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get columnGroup;

  /// No description provided for @collationNatural.
  ///
  /// In en, this message translates to:
  /// **'Natural'**
  String get collationNatural;

  /// No description provided for @collationCaseInsensitive.
  ///
  /// In en, this message translates to:
  /// **'Case-insensitive'**
  String get collationCaseInsensitive;

  /// No description provided for @collationCaseSensitive.
  ///
  /// In en, this message translates to:
  /// **'Case-sensitive'**
  String get collationCaseSensitive;

  /// No description provided for @panelParentFolder.
  ///
  /// In en, this message translates to:
  /// **'Up to the enclosing folder'**
  String get panelParentFolder;

  /// No description provided for @panelEmptyFolder.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty'**
  String get panelEmptyFolder;

  /// No description provided for @panelLoading.
  ///
  /// In en, this message translates to:
  /// **'Reading…'**
  String get panelLoading;

  /// No description provided for @panelFolderSize.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get panelFolderSize;

  /// No description provided for @panelItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no items} =1{1 item} other{{count} items}}'**
  String panelItemsCount(int count);

  /// No description provided for @panelSelectedSummary.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 selected} other{{count} selected}}, {size}'**
  String panelSelectedSummary(int count, String size);

  /// No description provided for @panelFreeSpace.
  ///
  /// In en, this message translates to:
  /// **'{free} free'**
  String panelFreeSpace(String free);

  /// No description provided for @panelQuickSearch.
  ///
  /// In en, this message translates to:
  /// **'Quick search: {query}'**
  String panelQuickSearch(String query);

  /// No description provided for @panelSymlinkTo.
  ///
  /// In en, this message translates to:
  /// **'→ {target}'**
  String panelSymlinkTo(String target);

  /// No description provided for @panelSortTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sorted by {field}'**
  String panelSortTooltip(String field);

  /// No description provided for @panelSortSummary.
  ///
  /// In en, this message translates to:
  /// **'Sorted by {field}, {direction}'**
  String panelSortSummary(String field, String direction);

  /// No description provided for @panelLayoutTooltip.
  ///
  /// In en, this message translates to:
  /// **'View mode'**
  String get panelLayoutTooltip;

  /// No description provided for @panelMenuTooltip.
  ///
  /// In en, this message translates to:
  /// **'Panel menu'**
  String get panelMenuTooltip;

  /// No description provided for @panelArchiveBadge.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get panelArchiveBadge;

  /// No description provided for @panelErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Cannot open this folder'**
  String get panelErrorTitle;

  /// No description provided for @panelGoHomeInstead.
  ///
  /// In en, this message translates to:
  /// **'Go to the home folder'**
  String get panelGoHomeInstead;

  /// No description provided for @vimModeNormal.
  ///
  /// In en, this message translates to:
  /// **'NORMAL'**
  String get vimModeNormal;

  /// No description provided for @vimModeVisual.
  ///
  /// In en, this message translates to:
  /// **'VISUAL'**
  String get vimModeVisual;

  /// No description provided for @vimModeSearch.
  ///
  /// In en, this message translates to:
  /// **'SEARCH'**
  String get vimModeSearch;

  /// No description provided for @vimModeCommand.
  ///
  /// In en, this message translates to:
  /// **'COMMAND'**
  String get vimModeCommand;

  /// No description provided for @vimRegisterCut.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 cut} other{{count} cut}}'**
  String vimRegisterCut(int count);

  /// No description provided for @vimRegisterYank.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 yanked} other{{count} yanked}}'**
  String vimRegisterYank(int count);

  /// No description provided for @vimCommandHint.
  ///
  /// In en, this message translates to:
  /// **'cd, mkdir, touch, rename, cp, mv, trash, delete, sort, set hidden, tabnew, tabclose, q, find, marks, help, or a row number'**
  String get vimCommandHint;

  /// No description provided for @vimUnknownCommand.
  ///
  /// In en, this message translates to:
  /// **'Not a command: {name}'**
  String vimUnknownCommand(String name);

  /// No description provided for @vimMarkSet.
  ///
  /// In en, this message translates to:
  /// **'Mark {letter} set'**
  String vimMarkSet(String letter);

  /// No description provided for @vimNoMark.
  ///
  /// In en, this message translates to:
  /// **'No mark {letter}'**
  String vimNoMark(String letter);

  /// No description provided for @vimMarksTitle.
  ///
  /// In en, this message translates to:
  /// **'Marks'**
  String get vimMarksTitle;

  /// No description provided for @vimNoMarks.
  ///
  /// In en, this message translates to:
  /// **'No marks yet; set one with m and a letter'**
  String get vimNoMarks;

  /// No description provided for @panelsVimMode.
  ///
  /// In en, this message translates to:
  /// **'Vim keys'**
  String get panelsVimMode;

  /// No description provided for @panelsVimModeHint.
  ///
  /// In en, this message translates to:
  /// **'h j k l, counts, / to search, v to select, yy dd p, marks and a : command line; see the cheat sheet'**
  String get panelsVimModeHint;

  /// No description provided for @panelHiddenShown.
  ///
  /// In en, this message translates to:
  /// **'Hidden items shown'**
  String get panelHiddenShown;

  /// No description provided for @tabNew.
  ///
  /// In en, this message translates to:
  /// **'New tab'**
  String get tabNew;

  /// No description provided for @tabClose.
  ///
  /// In en, this message translates to:
  /// **'Close tab'**
  String get tabClose;

  /// No description provided for @tabList.
  ///
  /// In en, this message translates to:
  /// **'All tabs'**
  String get tabList;

  /// No description provided for @tabRecentlyClosed.
  ///
  /// In en, this message translates to:
  /// **'Recently closed'**
  String get tabRecentlyClosed;

  /// No description provided for @sortMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sortMenuTitle;

  /// No description provided for @sortAscending.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get sortAscending;

  /// No description provided for @sortDescending.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get sortDescending;

  /// No description provided for @layoutMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'View mode'**
  String get layoutMenuTitle;

  /// No description provided for @menuOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get menuOpen;

  /// No description provided for @menuOpenWith.
  ///
  /// In en, this message translates to:
  /// **'Open with'**
  String get menuOpenWith;

  /// No description provided for @menuOpenWithOther.
  ///
  /// In en, this message translates to:
  /// **'Other application…'**
  String get menuOpenWithOther;

  /// No description provided for @menuShowInFinder.
  ///
  /// In en, this message translates to:
  /// **'Show in Finder'**
  String get menuShowInFinder;

  /// No description provided for @menuShowInExplorer.
  ///
  /// In en, this message translates to:
  /// **'Show in Explorer'**
  String get menuShowInExplorer;

  /// No description provided for @menuShowInFiles.
  ///
  /// In en, this message translates to:
  /// **'Show in Files'**
  String get menuShowInFiles;

  /// No description provided for @menuCopyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get menuCopyPath;

  /// No description provided for @menuCopyName.
  ///
  /// In en, this message translates to:
  /// **'Copy name'**
  String get menuCopyName;

  /// No description provided for @menuNewFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get menuNewFolder;

  /// No description provided for @menuNewFile.
  ///
  /// In en, this message translates to:
  /// **'New file'**
  String get menuNewFile;

  /// No description provided for @menuSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get menuSelectAll;

  /// No description provided for @menuEnterArchive.
  ///
  /// In en, this message translates to:
  /// **'Open as folder'**
  String get menuEnterArchive;

  /// No description provided for @menuExtractHere.
  ///
  /// In en, this message translates to:
  /// **'Extract here'**
  String get menuExtractHere;

  /// No description provided for @menuExtractToOpposite.
  ///
  /// In en, this message translates to:
  /// **'Extract to the other panel'**
  String get menuExtractToOpposite;

  /// No description provided for @copyDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Copy “{name}” to} other{Copy {count} items to}}'**
  String copyDialogTitle(int count, String name);

  /// No description provided for @moveDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Move “{name}” to} other{Move {count} items to}}'**
  String moveDialogTitle(int count, String name);

  /// No description provided for @copyAsTitle.
  ///
  /// In en, this message translates to:
  /// **'Copy “{name}” as'**
  String copyAsTitle(String name);

  /// No description provided for @moveAsTitle.
  ///
  /// In en, this message translates to:
  /// **'Move or rename “{name}” as'**
  String moveAsTitle(String name);

  /// No description provided for @destinationLabel.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get destinationLabel;

  /// No description provided for @newNameLabel.
  ///
  /// In en, this message translates to:
  /// **'New name'**
  String get newNameLabel;

  /// No description provided for @optionPreserveAttributes.
  ///
  /// In en, this message translates to:
  /// **'Preserve permissions and dates'**
  String get optionPreserveAttributes;

  /// No description provided for @optionVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify the copy'**
  String get optionVerify;

  /// No description provided for @conflictsLabel.
  ///
  /// In en, this message translates to:
  /// **'If an item already exists'**
  String get conflictsLabel;

  /// No description provided for @conflictAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask'**
  String get conflictAsk;

  /// No description provided for @conflictOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get conflictOverwrite;

  /// No description provided for @conflictOverwriteOlder.
  ///
  /// In en, this message translates to:
  /// **'Overwrite when older'**
  String get conflictOverwriteOlder;

  /// No description provided for @conflictSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get conflictSkip;

  /// No description provided for @conflictKeepBoth.
  ///
  /// In en, this message translates to:
  /// **'Keep both'**
  String get conflictKeepBoth;

  /// No description provided for @createDirectoryTitle.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get createDirectoryTitle;

  /// No description provided for @createDirectoryInOppositeTitle.
  ///
  /// In en, this message translates to:
  /// **'New folder in the other panel'**
  String get createDirectoryInOppositeTitle;

  /// No description provided for @createDirectoryHint.
  ///
  /// In en, this message translates to:
  /// **'Name, or a nested path like Notes/2026'**
  String get createDirectoryHint;

  /// No description provided for @createFileTitle.
  ///
  /// In en, this message translates to:
  /// **'New file'**
  String get createFileTitle;

  /// No description provided for @newFolderDefaultName.
  ///
  /// In en, this message translates to:
  /// **'untitled folder'**
  String get newFolderDefaultName;

  /// No description provided for @newFileDefaultName.
  ///
  /// In en, this message translates to:
  /// **'untitled.txt'**
  String get newFileDefaultName;

  /// No description provided for @deleteTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete “{name}”?} other{Delete {count} items?}}'**
  String deleteTitle(int count, String name);

  /// No description provided for @deleteMessageTrash.
  ///
  /// In en, this message translates to:
  /// **'The items go to the Trash.'**
  String get deleteMessageTrash;

  /// No description provided for @deleteMessagePermanent.
  ///
  /// In en, this message translates to:
  /// **'The items are deleted for good and cannot be brought back.'**
  String get deleteMessagePermanent;

  /// No description provided for @deleteToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get deleteToTrash;

  /// No description provided for @deletePermanently.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get deletePermanently;

  /// No description provided for @deleteNothingSelected.
  ///
  /// In en, this message translates to:
  /// **'Nothing to delete'**
  String get deleteNothingSelected;

  /// No description provided for @compressTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Compress “{name}”} other{Compress {count} items}}'**
  String compressTitle(int count, String name);

  /// No description provided for @archiveNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Archive name'**
  String get archiveNameLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password (AES-256, optional)'**
  String get passwordLabel;

  /// No description provided for @compressHere.
  ///
  /// In en, this message translates to:
  /// **'In this folder'**
  String get compressHere;

  /// No description provided for @compressToOpposite.
  ///
  /// In en, this message translates to:
  /// **'In the other panel'**
  String get compressToOpposite;

  /// No description provided for @selectMaskTitle.
  ///
  /// In en, this message translates to:
  /// **'Select with mask'**
  String get selectMaskTitle;

  /// No description provided for @deselectMaskTitle.
  ///
  /// In en, this message translates to:
  /// **'Deselect with mask'**
  String get deselectMaskTitle;

  /// No description provided for @maskLabel.
  ///
  /// In en, this message translates to:
  /// **'Mask or expression'**
  String get maskLabel;

  /// No description provided for @maskHint.
  ///
  /// In en, this message translates to:
  /// **'*.jpg; *.png'**
  String get maskHint;

  /// No description provided for @maskRegex.
  ///
  /// In en, this message translates to:
  /// **'Regular expression'**
  String get maskRegex;

  /// No description provided for @goToFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Go to folder'**
  String get goToFolderTitle;

  /// No description provided for @goToFolderHint.
  ///
  /// In en, this message translates to:
  /// **'/path/to/folder or ~/Documents'**
  String get goToFolderHint;

  /// No description provided for @goToPopupTitle.
  ///
  /// In en, this message translates to:
  /// **'Go to'**
  String get goToPopupTitle;

  /// No description provided for @goToFilterHint.
  ///
  /// In en, this message translates to:
  /// **'Type to filter'**
  String get goToFilterHint;

  /// No description provided for @sectionFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get sectionFavorites;

  /// No description provided for @sectionVolumes.
  ///
  /// In en, this message translates to:
  /// **'Volumes'**
  String get sectionVolumes;

  /// No description provided for @sectionOtherPanel.
  ///
  /// In en, this message translates to:
  /// **'Other panel'**
  String get sectionOtherPanel;

  /// No description provided for @sectionHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get sectionHistory;

  /// No description provided for @sectionParents.
  ///
  /// In en, this message translates to:
  /// **'Enclosing folders'**
  String get sectionParents;

  /// No description provided for @quickListEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get quickListEmpty;

  /// No description provided for @volumeFree.
  ///
  /// In en, this message translates to:
  /// **'{free} of {total} free'**
  String volumeFree(String free, String total);

  /// No description provided for @ejectVolume.
  ///
  /// In en, this message translates to:
  /// **'Eject {name}'**
  String ejectVolume(String name);

  /// No description provided for @favoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favoritesTitle;

  /// No description provided for @favoritesAddCurrent.
  ///
  /// In en, this message translates to:
  /// **'Add the current folder'**
  String get favoritesAddCurrent;

  /// No description provided for @favoritesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet. Add the current folder from the panel menu.'**
  String get favoritesEmpty;

  /// No description provided for @favoritesRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename favorite'**
  String get favoritesRenameTitle;

  /// No description provided for @favoriteAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to favorites: {name}'**
  String favoriteAdded(String name);

  /// No description provided for @favoriteRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed from favorites: {name}'**
  String favoriteRemoved(String name);

  /// No description provided for @attributesTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Attributes of “{name}”} other{Attributes of {count} items}}'**
  String attributesTitle(int count, String name);

  /// No description provided for @permissionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissionsLabel;

  /// No description provided for @permOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get permOwner;

  /// No description provided for @permGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get permGroup;

  /// No description provided for @permOthers.
  ///
  /// In en, this message translates to:
  /// **'Others'**
  String get permOthers;

  /// No description provided for @permRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get permRead;

  /// No description provided for @permWrite.
  ///
  /// In en, this message translates to:
  /// **'Write'**
  String get permWrite;

  /// No description provided for @permExecute.
  ///
  /// In en, this message translates to:
  /// **'Execute'**
  String get permExecute;

  /// No description provided for @permSetUid.
  ///
  /// In en, this message translates to:
  /// **'Set user ID'**
  String get permSetUid;

  /// No description provided for @permSetGid.
  ///
  /// In en, this message translates to:
  /// **'Set group ID'**
  String get permSetGid;

  /// No description provided for @permSticky.
  ///
  /// In en, this message translates to:
  /// **'Sticky'**
  String get permSticky;

  /// No description provided for @flagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Flags'**
  String get flagsLabel;

  /// No description provided for @flagHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get flagHidden;

  /// No description provided for @flagLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get flagLocked;

  /// No description provided for @flagAppendOnly.
  ///
  /// In en, this message translates to:
  /// **'Append only'**
  String get flagAppendOnly;

  /// No description provided for @flagNoDump.
  ///
  /// In en, this message translates to:
  /// **'No dump'**
  String get flagNoDump;

  /// No description provided for @flagArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get flagArchived;

  /// No description provided for @ownerLabel.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get ownerLabel;

  /// No description provided for @groupLabel.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get groupLabel;

  /// No description provided for @timesLabel.
  ///
  /// In en, this message translates to:
  /// **'Dates'**
  String get timesLabel;

  /// No description provided for @modifiedLabel.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get modifiedLabel;

  /// No description provided for @accessedLabel.
  ///
  /// In en, this message translates to:
  /// **'Accessed'**
  String get accessedLabel;

  /// No description provided for @createdLabel.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get createdLabel;

  /// No description provided for @dateFieldHint.
  ///
  /// In en, this message translates to:
  /// **'yyyy-mm-dd hh:mm'**
  String get dateFieldHint;

  /// No description provided for @attributesInvalidDate.
  ///
  /// In en, this message translates to:
  /// **'Not a valid date and time'**
  String get attributesInvalidDate;

  /// No description provided for @applyRecursively.
  ///
  /// In en, this message translates to:
  /// **'Apply to everything inside the folders'**
  String get applyRecursively;

  /// No description provided for @attributesUnknownUser.
  ///
  /// In en, this message translates to:
  /// **'No user named “{name}”'**
  String attributesUnknownUser(String name);

  /// No description provided for @attributesUnknownGroup.
  ///
  /// In en, this message translates to:
  /// **'No group named “{name}”'**
  String attributesUnknownGroup(String name);

  /// No description provided for @attributesFailed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item could not be changed} other{{count} items could not be changed}}'**
  String attributesFailed(int count);

  /// No description provided for @batchRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Rename 1 item} other{Rename {count} items}}'**
  String batchRenameTitle(int count);

  /// No description provided for @renamePatternLabel.
  ///
  /// In en, this message translates to:
  /// **'New name'**
  String get renamePatternLabel;

  /// No description provided for @renamePatternHint.
  ///
  /// In en, this message translates to:
  /// **'[N].[E]  ·  [N] name, [E] extension, [C] counter, [d] date'**
  String get renamePatternHint;

  /// No description provided for @renameSearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get renameSearchLabel;

  /// No description provided for @renameReplaceLabel.
  ///
  /// In en, this message translates to:
  /// **'Replace with'**
  String get renameReplaceLabel;

  /// No description provided for @renameRegex.
  ///
  /// In en, this message translates to:
  /// **'Regular expression'**
  String get renameRegex;

  /// No description provided for @renameCaseSensitive.
  ///
  /// In en, this message translates to:
  /// **'Match case'**
  String get renameCaseSensitive;

  /// No description provided for @renameOnce.
  ///
  /// In en, this message translates to:
  /// **'First occurrence only'**
  String get renameOnce;

  /// No description provided for @renameCaseLabel.
  ///
  /// In en, this message translates to:
  /// **'Case'**
  String get renameCaseLabel;

  /// No description provided for @caseUnchanged.
  ///
  /// In en, this message translates to:
  /// **'As is'**
  String get caseUnchanged;

  /// No description provided for @caseLower.
  ///
  /// In en, this message translates to:
  /// **'lowercase'**
  String get caseLower;

  /// No description provided for @caseUpper.
  ///
  /// In en, this message translates to:
  /// **'UPPERCASE'**
  String get caseUpper;

  /// No description provided for @caseCapitalize.
  ///
  /// In en, this message translates to:
  /// **'Capitalize Words'**
  String get caseCapitalize;

  /// No description provided for @partWhole.
  ///
  /// In en, this message translates to:
  /// **'Whole name'**
  String get partWhole;

  /// No description provided for @partName.
  ///
  /// In en, this message translates to:
  /// **'Name only'**
  String get partName;

  /// No description provided for @partExtension.
  ///
  /// In en, this message translates to:
  /// **'Extension only'**
  String get partExtension;

  /// No description provided for @renameCounterLabel.
  ///
  /// In en, this message translates to:
  /// **'Counter'**
  String get renameCounterLabel;

  /// No description provided for @renameCounterStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get renameCounterStart;

  /// No description provided for @renameCounterStep.
  ///
  /// In en, this message translates to:
  /// **'Step'**
  String get renameCounterStep;

  /// No description provided for @renameCounterWidth.
  ///
  /// In en, this message translates to:
  /// **'Digits'**
  String get renameCounterWidth;

  /// No description provided for @renamePreviewOld.
  ///
  /// In en, this message translates to:
  /// **'Current name'**
  String get renamePreviewOld;

  /// No description provided for @renamePreviewNew.
  ///
  /// In en, this message translates to:
  /// **'New name'**
  String get renamePreviewNew;

  /// No description provided for @renameProblemEmpty.
  ///
  /// In en, this message translates to:
  /// **'Empty name'**
  String get renameProblemEmpty;

  /// No description provided for @renameProblemInvalid.
  ///
  /// In en, this message translates to:
  /// **'Not a valid name'**
  String get renameProblemInvalid;

  /// No description provided for @renameProblemDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Same name as another item'**
  String get renameProblemDuplicate;

  /// No description provided for @renameNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No names change'**
  String get renameNoChanges;

  /// No description provided for @renameFailed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item could not be renamed} other{{count} items could not be renamed}}'**
  String renameFailed(int count);

  /// No description provided for @renamePlaceholdersHelp.
  ///
  /// In en, this message translates to:
  /// **'Placeholders'**
  String get renamePlaceholdersHelp;

  /// No description provided for @renameSearchPartLabel.
  ///
  /// In en, this message translates to:
  /// **'Search in'**
  String get renameSearchPartLabel;

  /// No description provided for @renameCasePartLabel.
  ///
  /// In en, this message translates to:
  /// **'Apply to'**
  String get renameCasePartLabel;

  /// No description provided for @renamePlaceholdersText.
  ///
  /// In en, this message translates to:
  /// **'[N] name · [E] extension · [A] whole name · [P] parent folder · [G] grandparent · [N2-4] characters 2 to 4 · [N-3,2] two from the third-last · [C] counter, [C5+2:3] from 5 by 2, three digits · [d] date · [Y] [M] [D] year, month, day · [t] time · [h] [m] [s] · [U] [L] [F] upper, lower, capitalized text after · [n] as is · [[ and ]] brackets'**
  String get renamePlaceholdersText;

  /// No description provided for @symlinkTitle.
  ///
  /// In en, this message translates to:
  /// **'New symbolic link'**
  String get symlinkTitle;

  /// No description provided for @hardlinkTitle.
  ///
  /// In en, this message translates to:
  /// **'New hard link'**
  String get hardlinkTitle;

  /// No description provided for @editSymlinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit symbolic link'**
  String get editSymlinkTitle;

  /// No description provided for @linkTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'Points to'**
  String get linkTargetLabel;

  /// No description provided for @linkNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Link name'**
  String get linkNameLabel;

  /// No description provided for @linkNotSymlink.
  ///
  /// In en, this message translates to:
  /// **'The item is not a symbolic link'**
  String get linkNotSymlink;

  /// No description provided for @conflictTitle.
  ///
  /// In en, this message translates to:
  /// **'Already exists'**
  String get conflictTitle;

  /// No description provided for @conflictSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Copying'**
  String get conflictSourceLabel;

  /// No description provided for @conflictExistingLabel.
  ///
  /// In en, this message translates to:
  /// **'Existing'**
  String get conflictExistingLabel;

  /// No description provided for @conflictFolderLabel.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get conflictFolderLabel;

  /// No description provided for @questionApplyToAll.
  ///
  /// In en, this message translates to:
  /// **'Apply to all'**
  String get questionApplyToAll;

  /// No description provided for @questionErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not continue'**
  String get questionErrorTitle;

  /// No description provided for @conflictMessage.
  ///
  /// In en, this message translates to:
  /// **'“{name}” already exists in the destination.'**
  String conflictMessage(String name);

  /// No description provided for @questionErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not continue with “{name}”.'**
  String questionErrorMessage(String name);

  /// No description provided for @opCopyTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Copying 1 item} other{Copying {count} items}}'**
  String opCopyTitle(int count);

  /// No description provided for @opMoveTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Moving 1 item} other{Moving {count} items}}'**
  String opMoveTitle(int count);

  /// No description provided for @opDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Deleting 1 item} other{Deleting {count} items}}'**
  String opDeleteTitle(int count);

  /// No description provided for @opTrashTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Moving 1 item to the Trash} other{Moving {count} items to the Trash}}'**
  String opTrashTitle(int count);

  /// No description provided for @opDuplicateTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Duplicating 1 item} other{Duplicating {count} items}}'**
  String opDuplicateTitle(int count);

  /// No description provided for @opCompressTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Compressing 1 item} other{Compressing {count} items}}'**
  String opCompressTitle(int count);

  /// No description provided for @opExtractTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Extracting 1 item} other{Extracting {count} items}}'**
  String opExtractTitle(int count);

  /// No description provided for @opCalcSizesTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Calculating the size of 1 folder} other{Calculating the sizes of {count} folders}}'**
  String opCalcSizesTitle(int count);

  /// No description provided for @opStateScanning.
  ///
  /// In en, this message translates to:
  /// **'Counting…'**
  String get opStateScanning;

  /// No description provided for @opStateRunning.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get opStateRunning;

  /// No description provided for @opStatePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get opStatePaused;

  /// No description provided for @opStateWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for an answer'**
  String get opStateWaiting;

  /// No description provided for @opStateDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get opStateDone;

  /// No description provided for @opStateDoneWithErrors.
  ///
  /// In en, this message translates to:
  /// **'Done with errors'**
  String get opStateDoneWithErrors;

  /// No description provided for @opStateCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get opStateCancelled;

  /// No description provided for @opStateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get opStateFailed;

  /// No description provided for @opProgressBytes.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total}'**
  String opProgressBytes(String done, String total);

  /// No description provided for @opProgressItems.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} items'**
  String opProgressItems(int done, int total);

  /// No description provided for @opSpeed.
  ///
  /// In en, this message translates to:
  /// **'{speed}/s'**
  String opSpeed(String speed);

  /// No description provided for @opRemaining.
  ///
  /// In en, this message translates to:
  /// **'{duration} left'**
  String opRemaining(String duration);

  /// No description provided for @opErrorsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 error} other{{count} errors}}'**
  String opErrorsCount(int count);

  /// No description provided for @opErrorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get opErrorsTitle;

  /// No description provided for @opTitleTo.
  ///
  /// In en, this message translates to:
  /// **'{title} to {destination}'**
  String opTitleTo(String title, String destination);

  /// No description provided for @opFirstError.
  ///
  /// In en, this message translates to:
  /// **'{name}: {message}'**
  String opFirstError(String name, String message);

  /// No description provided for @operationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Operations'**
  String get operationsTitle;

  /// No description provided for @operationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No operations'**
  String get operationsEmpty;

  /// No description provided for @operationsClearFinished.
  ///
  /// In en, this message translates to:
  /// **'Clear finished'**
  String get operationsClearFinished;

  /// No description provided for @noticePathsCopied.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Path copied} other{{count} paths copied}}'**
  String noticePathsCopied(int count);

  /// No description provided for @noticeNameCopied.
  ///
  /// In en, this message translates to:
  /// **'Name copied'**
  String get noticeNameCopied;

  /// No description provided for @noticeNothingSelected.
  ///
  /// In en, this message translates to:
  /// **'Nothing is selected'**
  String get noticeNothingSelected;

  /// No description provided for @noticeNotInArchive.
  ///
  /// In en, this message translates to:
  /// **'Not available inside an archive'**
  String get noticeNotInArchive;

  /// No description provided for @noticeClipboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'The clipboard holds no paths'**
  String get noticeClipboardEmpty;

  /// No description provided for @noticeEjected.
  ///
  /// In en, this message translates to:
  /// **'Ejected {name}'**
  String noticeEjected(String name);

  /// No description provided for @noticeNoEditor.
  ///
  /// In en, this message translates to:
  /// **'No editor is set up for this file; see Settings → Editors'**
  String get noticeNoEditor;

  /// No description provided for @noticeNoVolume.
  ///
  /// In en, this message translates to:
  /// **'Nothing to eject here'**
  String get noticeNoVolume;

  /// No description provided for @noticeOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the item'**
  String get noticeOpenFailed;

  /// No description provided for @viewerTitle.
  ///
  /// In en, this message translates to:
  /// **'Viewer'**
  String get viewerTitle;

  /// No description provided for @viewerModeText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get viewerModeText;

  /// No description provided for @viewerModeHex.
  ///
  /// In en, this message translates to:
  /// **'Hex'**
  String get viewerModeHex;

  /// No description provided for @viewerModePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get viewerModePreview;

  /// No description provided for @viewerGoToTitle.
  ///
  /// In en, this message translates to:
  /// **'Go to'**
  String get viewerGoToTitle;

  /// No description provided for @viewerGoToHint.
  ///
  /// In en, this message translates to:
  /// **'Offset in bytes, or a percentage like 50%'**
  String get viewerGoToHint;

  /// No description provided for @viewerNoPreview.
  ///
  /// In en, this message translates to:
  /// **'No preview for this kind of file'**
  String get viewerNoPreview;

  /// No description provided for @viewerFindHint.
  ///
  /// In en, this message translates to:
  /// **'Find in file'**
  String get viewerFindHint;

  /// No description provided for @viewerPosition.
  ///
  /// In en, this message translates to:
  /// **'{offset} of {size}'**
  String viewerPosition(String offset, String size);

  /// No description provided for @viewerEncoding.
  ///
  /// In en, this message translates to:
  /// **'UTF-8'**
  String get viewerEncoding;

  /// No description provided for @viewerWrap.
  ///
  /// In en, this message translates to:
  /// **'Wrap lines'**
  String get viewerWrap;

  /// No description provided for @viewerLoading.
  ///
  /// In en, this message translates to:
  /// **'Reading…'**
  String get viewerLoading;

  /// No description provided for @viewerWindow.
  ///
  /// In en, this message translates to:
  /// **'Showing {shown} of {size}; use Go to for the rest'**
  String viewerWindow(String shown, String size);

  /// No description provided for @viewerNoMatch.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get viewerNoMatch;

  /// No description provided for @viewerEmptyFile.
  ///
  /// In en, this message translates to:
  /// **'The file is empty'**
  String get viewerEmptyFile;

  /// No description provided for @viewerBinaryHint.
  ///
  /// In en, this message translates to:
  /// **'Binary data: switch to Hex'**
  String get viewerBinaryHint;

  /// No description provided for @viewerLine.
  ///
  /// In en, this message translates to:
  /// **'Line {line}'**
  String viewerLine(int line);

  /// No description provided for @viewerMatches.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String viewerMatches(int current, int total);

  /// No description provided for @viewerLoadNext.
  ///
  /// In en, this message translates to:
  /// **'Next part'**
  String get viewerLoadNext;

  /// No description provided for @viewerLoadPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous part'**
  String get viewerLoadPrevious;

  /// No description provided for @findTitle.
  ///
  /// In en, this message translates to:
  /// **'Find files'**
  String get findTitle;

  /// No description provided for @findIn.
  ///
  /// In en, this message translates to:
  /// **'In folder'**
  String get findIn;

  /// No description provided for @findName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get findName;

  /// No description provided for @findNameHint.
  ///
  /// In en, this message translates to:
  /// **'*.txt; report*'**
  String get findNameHint;

  /// No description provided for @findRegex.
  ///
  /// In en, this message translates to:
  /// **'Regular expression'**
  String get findRegex;

  /// No description provided for @findContent.
  ///
  /// In en, this message translates to:
  /// **'Containing text'**
  String get findContent;

  /// No description provided for @findCaseSensitive.
  ///
  /// In en, this message translates to:
  /// **'Match case'**
  String get findCaseSensitive;

  /// No description provided for @findWholePhrase.
  ///
  /// In en, this message translates to:
  /// **'Whole phrase'**
  String get findWholePhrase;

  /// No description provided for @findNotContaining.
  ///
  /// In en, this message translates to:
  /// **'Not containing'**
  String get findNotContaining;

  /// No description provided for @findSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get findSize;

  /// No description provided for @findSizeAny.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get findSizeAny;

  /// No description provided for @findSizeLess.
  ///
  /// In en, this message translates to:
  /// **'Less than'**
  String get findSizeLess;

  /// No description provided for @findSizeEqual.
  ///
  /// In en, this message translates to:
  /// **'Equal to'**
  String get findSizeEqual;

  /// No description provided for @findSizeGreater.
  ///
  /// In en, this message translates to:
  /// **'Greater than'**
  String get findSizeGreater;

  /// No description provided for @findIncludeHidden.
  ///
  /// In en, this message translates to:
  /// **'Include hidden items'**
  String get findIncludeHidden;

  /// No description provided for @findStart.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get findStart;

  /// No description provided for @findStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get findStop;

  /// No description provided for @findResults.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No items found} =1{1 item found} other{{count} items found}}'**
  String findResults(int count);

  /// No description provided for @findScanning.
  ///
  /// In en, this message translates to:
  /// **'Looking in {path}'**
  String findScanning(String path);

  /// No description provided for @findGoTo.
  ///
  /// In en, this message translates to:
  /// **'Go to'**
  String get findGoTo;

  /// No description provided for @findView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get findView;

  /// No description provided for @findNoResults.
  ///
  /// In en, this message translates to:
  /// **'Nothing matched'**
  String get findNoResults;

  /// No description provided for @findError.
  ///
  /// In en, this message translates to:
  /// **'The search could not run: {message}'**
  String findError(String message);

  /// No description provided for @findColumnFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get findColumnFolder;

  /// No description provided for @findUnitBytes.
  ///
  /// In en, this message translates to:
  /// **'B'**
  String get findUnitBytes;

  /// No description provided for @findUnitKilobytes.
  ///
  /// In en, this message translates to:
  /// **'KB'**
  String get findUnitKilobytes;

  /// No description provided for @findUnitMegabytes.
  ///
  /// In en, this message translates to:
  /// **'MB'**
  String get findUnitMegabytes;

  /// No description provided for @findUnitGigabytes.
  ///
  /// In en, this message translates to:
  /// **'GB'**
  String get findUnitGigabytes;

  /// No description provided for @findResultsCapped.
  ///
  /// In en, this message translates to:
  /// **'Showing the first {count} items; narrow the search for the rest'**
  String findResultsCapped(int count);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneral;

  /// No description provided for @settingsPanels.
  ///
  /// In en, this message translates to:
  /// **'Panels'**
  String get settingsPanels;

  /// No description provided for @settingsViewer.
  ///
  /// In en, this message translates to:
  /// **'Viewer'**
  String get settingsViewer;

  /// No description provided for @settingsHotkeys.
  ///
  /// In en, this message translates to:
  /// **'Hotkeys'**
  String get settingsHotkeys;

  /// No description provided for @settingsEditors.
  ///
  /// In en, this message translates to:
  /// **'Editors'**
  String get settingsEditors;

  /// No description provided for @settingsTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get settingsTools;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search settings'**
  String get settingsSearchHint;

  /// No description provided for @themeLabel.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get themeLabel;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageRussian.
  ///
  /// In en, this message translates to:
  /// **'Русский'**
  String get languageRussian;

  /// No description provided for @textSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get textSizeLabel;

  /// No description provided for @textSizePercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String textSizePercent(int percent);

  /// No description provided for @confirmationsLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirmations'**
  String get confirmationsLabel;

  /// No description provided for @confirmTrashLabel.
  ///
  /// In en, this message translates to:
  /// **'Ask before moving to the Trash'**
  String get confirmTrashLabel;

  /// No description provided for @confirmDeleteLabel.
  ///
  /// In en, this message translates to:
  /// **'Ask before deleting permanently'**
  String get confirmDeleteLabel;

  /// No description provided for @generalKeyHintsLabel.
  ///
  /// In en, this message translates to:
  /// **'Key hints under the panels'**
  String get generalKeyHintsLabel;

  /// No description provided for @generalKeyHintsNote.
  ///
  /// In en, this message translates to:
  /// **'One line with the keys for what is under the cursor or selected'**
  String get generalKeyHintsNote;

  /// No description provided for @hintsHide.
  ///
  /// In en, this message translates to:
  /// **'Hide the hints'**
  String get hintsHide;

  /// No description provided for @hintsHidden.
  ///
  /// In en, this message translates to:
  /// **'Hints are off; Settings, General turns them back on'**
  String get hintsHidden;

  /// No description provided for @hintBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get hintBack;

  /// No description provided for @hintKeepMatches.
  ///
  /// In en, this message translates to:
  /// **'Keep the matches'**
  String get hintKeepMatches;

  /// No description provided for @copyDefaultsLabel.
  ///
  /// In en, this message translates to:
  /// **'Copying'**
  String get copyDefaultsLabel;

  /// No description provided for @panelsShowHidden.
  ///
  /// In en, this message translates to:
  /// **'Show hidden items'**
  String get panelsShowHidden;

  /// No description provided for @panelsParentEntry.
  ///
  /// In en, this message translates to:
  /// **'Show the “..” row'**
  String get panelsParentEntry;

  /// No description provided for @panelsFoldersFirst.
  ///
  /// In en, this message translates to:
  /// **'Folders before files'**
  String get panelsFoldersFirst;

  /// No description provided for @panelsExtensionlessFolders.
  ///
  /// In en, this message translates to:
  /// **'Folders have no extension when sorting'**
  String get panelsExtensionlessFolders;

  /// No description provided for @panelsCollation.
  ///
  /// In en, this message translates to:
  /// **'Compare names'**
  String get panelsCollation;

  /// No description provided for @panelsTabBarAlways.
  ///
  /// In en, this message translates to:
  /// **'Always show the tab bar'**
  String get panelsTabBarAlways;

  /// No description provided for @quickSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick search'**
  String get quickSearchTitle;

  /// No description provided for @quickSearchWhere.
  ///
  /// In en, this message translates to:
  /// **'Where to search'**
  String get quickSearchWhere;

  /// No description provided for @quickSearchFuzzy.
  ///
  /// In en, this message translates to:
  /// **'Fuzzy'**
  String get quickSearchFuzzy;

  /// No description provided for @quickSearchAnywhere.
  ///
  /// In en, this message translates to:
  /// **'Anywhere'**
  String get quickSearchAnywhere;

  /// No description provided for @quickSearchBeginning.
  ///
  /// In en, this message translates to:
  /// **'Beginning'**
  String get quickSearchBeginning;

  /// No description provided for @quickSearchEnding.
  ///
  /// In en, this message translates to:
  /// **'Ending'**
  String get quickSearchEnding;

  /// No description provided for @quickSearchBeginningOrEnding.
  ///
  /// In en, this message translates to:
  /// **'Beginning or ending'**
  String get quickSearchBeginningOrEnding;

  /// No description provided for @quickSearchModifier.
  ///
  /// In en, this message translates to:
  /// **'Key modifier'**
  String get quickSearchModifier;

  /// No description provided for @modifierNone.
  ///
  /// In en, this message translates to:
  /// **'No modifier'**
  String get modifierNone;

  /// No description provided for @modifierAlt.
  ///
  /// In en, this message translates to:
  /// **'Option'**
  String get modifierAlt;

  /// No description provided for @modifierControlAlt.
  ///
  /// In en, this message translates to:
  /// **'Control + Option'**
  String get modifierControlAlt;

  /// No description provided for @modifierShiftAlt.
  ///
  /// In en, this message translates to:
  /// **'Shift + Option'**
  String get modifierShiftAlt;

  /// No description provided for @modifierDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get modifierDisabled;

  /// No description provided for @quickSearchOnlyMatching.
  ///
  /// In en, this message translates to:
  /// **'Show only matching items'**
  String get quickSearchOnlyMatching;

  /// No description provided for @layoutsTitle.
  ///
  /// In en, this message translates to:
  /// **'View modes'**
  String get layoutsTitle;

  /// No description provided for @layoutName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get layoutName;

  /// No description provided for @layoutMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get layoutMode;

  /// No description provided for @modeBrief.
  ///
  /// In en, this message translates to:
  /// **'Brief'**
  String get modeBrief;

  /// No description provided for @modeList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get modeList;

  /// No description provided for @briefColumnsLabel.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get briefColumnsLabel;

  /// No description provided for @briefColumnsFixed.
  ///
  /// In en, this message translates to:
  /// **'Three equal columns'**
  String get briefColumnsFixed;

  /// No description provided for @briefColumnsDynamic.
  ///
  /// In en, this message translates to:
  /// **'As wide as the names'**
  String get briefColumnsDynamic;

  /// No description provided for @columnsLabel.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get columnsLabel;

  /// No description provided for @layoutsReset.
  ///
  /// In en, this message translates to:
  /// **'Restore the default modes'**
  String get layoutsReset;

  /// No description provided for @viewerWrapLabel.
  ///
  /// In en, this message translates to:
  /// **'Wrap long lines'**
  String get viewerWrapLabel;

  /// No description provided for @viewerFontSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get viewerFontSizeLabel;

  /// No description provided for @hotkeysReset.
  ///
  /// In en, this message translates to:
  /// **'Restore defaults'**
  String get hotkeysReset;

  /// No description provided for @hotkeysResetOne.
  ///
  /// In en, this message translates to:
  /// **'Restore default'**
  String get hotkeysResetOne;

  /// No description provided for @hotkeysRecord.
  ///
  /// In en, this message translates to:
  /// **'Press the new key…'**
  String get hotkeysRecord;

  /// No description provided for @hotkeysRecordTitle.
  ///
  /// In en, this message translates to:
  /// **'Set a key for “{command}”'**
  String hotkeysRecordTitle(String command);

  /// No description provided for @hotkeysConflict.
  ///
  /// In en, this message translates to:
  /// **'Already used by “{command}”'**
  String hotkeysConflict(String command);

  /// No description provided for @hotkeysReassign.
  ///
  /// In en, this message translates to:
  /// **'Reassign'**
  String get hotkeysReassign;

  /// No description provided for @hotkeysChanged.
  ///
  /// In en, this message translates to:
  /// **'Changed from the default'**
  String get hotkeysChanged;

  /// No description provided for @lengthPoints.
  ///
  /// In en, this message translates to:
  /// **'{value} pt'**
  String lengthPoints(int value);

  /// No description provided for @lengthPixels.
  ///
  /// In en, this message translates to:
  /// **'{value} px'**
  String lengthPixels(int value);

  /// No description provided for @hotkeysUnbound.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get hotkeysUnbound;

  /// No description provided for @hotkeysSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search commands'**
  String get hotkeysSearchHint;

  /// No description provided for @hotkeysChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get hotkeysChange;

  /// No description provided for @hotkeysClear.
  ///
  /// In en, this message translates to:
  /// **'Remove key'**
  String get hotkeysClear;

  /// No description provided for @editorsIntro.
  ///
  /// In en, this message translates to:
  /// **'F4 opens the focused file with the first editor whose mask matches its name.'**
  String get editorsIntro;

  /// No description provided for @editorName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get editorName;

  /// No description provided for @editorPath.
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get editorPath;

  /// No description provided for @editorMask.
  ///
  /// In en, this message translates to:
  /// **'File masks'**
  String get editorMask;

  /// No description provided for @editorInTerminal.
  ///
  /// In en, this message translates to:
  /// **'Run in a terminal'**
  String get editorInTerminal;

  /// No description provided for @editorsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No editors yet'**
  String get editorsEmpty;

  /// No description provided for @editorsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add editor'**
  String get editorsAdd;

  /// No description provided for @editorAddTitle.
  ///
  /// In en, this message translates to:
  /// **'New editor'**
  String get editorAddTitle;

  /// No description provided for @editorEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get editorEditTitle;

  /// No description provided for @toolsIntro.
  ///
  /// In en, this message translates to:
  /// **'Tools run a program with the panels’ items as arguments: %p the focused path, %f its name, %r the panel’s folder, %P every selected path, %-… the other panel’s.'**
  String get toolsIntro;

  /// No description provided for @toolTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get toolTitle;

  /// No description provided for @toolPath.
  ///
  /// In en, this message translates to:
  /// **'Program'**
  String get toolPath;

  /// No description provided for @toolParameters.
  ///
  /// In en, this message translates to:
  /// **'Arguments'**
  String get toolParameters;

  /// No description provided for @toolInTerminal.
  ///
  /// In en, this message translates to:
  /// **'Run in a terminal'**
  String get toolInTerminal;

  /// No description provided for @toolsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tools yet'**
  String get toolsEmpty;

  /// No description provided for @toolsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add tool'**
  String get toolsAdd;

  /// No description provided for @toolAddTitle.
  ///
  /// In en, this message translates to:
  /// **'New tool'**
  String get toolAddTitle;

  /// No description provided for @toolEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Tool'**
  String get toolEditTitle;

  /// No description provided for @toolRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get toolRun;

  /// No description provided for @toolAskValueTitle.
  ///
  /// In en, this message translates to:
  /// **'Value for the tool'**
  String get toolAskValueTitle;

  /// No description provided for @choosePath.
  ///
  /// In en, this message translates to:
  /// **'Choose…'**
  String get choosePath;

  /// No description provided for @cheatSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get cheatSheetTitle;

  /// No description provided for @cheatSheetHint.
  ///
  /// In en, this message translates to:
  /// **'Every key the window answers; change them in Settings → Hotkeys.'**
  String get cheatSheetHint;

  /// No description provided for @scopeGlobal.
  ///
  /// In en, this message translates to:
  /// **'Everywhere'**
  String get scopeGlobal;

  /// No description provided for @scopePanel.
  ///
  /// In en, this message translates to:
  /// **'File panel'**
  String get scopePanel;

  /// No description provided for @scopeViewer.
  ///
  /// In en, this message translates to:
  /// **'Viewer'**
  String get scopeViewer;

  /// No description provided for @scopeLists.
  ///
  /// In en, this message translates to:
  /// **'Lists'**
  String get scopeLists;

  /// No description provided for @scopeDialogs.
  ///
  /// In en, this message translates to:
  /// **'Dialogs'**
  String get scopeDialogs;

  /// No description provided for @windowClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get windowClose;

  /// No description provided for @windowMinimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get windowMinimize;

  /// No description provided for @windowMaximize.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get windowMaximize;

  /// No description provided for @hintModeHint.
  ///
  /// In en, this message translates to:
  /// **'Type a label to click it; Esc to leave'**
  String get hintModeHint;

  /// No description provided for @splitterTitle.
  ///
  /// In en, this message translates to:
  /// **'Panel sizes'**
  String get splitterTitle;

  /// No description provided for @splitterHintArrows.
  ///
  /// In en, this message translates to:
  /// **'Move the edge'**
  String get splitterHintArrows;

  /// No description provided for @splitterHintZero.
  ///
  /// In en, this message translates to:
  /// **'Equal panels'**
  String get splitterHintZero;

  /// No description provided for @splitterHintEnter.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get splitterHintEnter;

  /// No description provided for @splitterHintEscape.
  ///
  /// In en, this message translates to:
  /// **'Put back'**
  String get splitterHintEscape;

  /// No description provided for @singlePaneTooltip.
  ///
  /// In en, this message translates to:
  /// **'Single panel'**
  String get singlePaneTooltip;

  /// No description provided for @dualPaneTooltip.
  ///
  /// In en, this message translates to:
  /// **'Two panels'**
  String get dualPaneTooltip;

  /// No description provided for @panelLeft.
  ///
  /// In en, this message translates to:
  /// **'Left panel'**
  String get panelLeft;

  /// No description provided for @panelRight.
  ///
  /// In en, this message translates to:
  /// **'Right panel'**
  String get panelRight;

  /// No description provided for @cmdNewFolder.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get cmdNewFolder;

  /// No description provided for @cmdNewFolderWithSelection.
  ///
  /// In en, this message translates to:
  /// **'New Folder with Selection'**
  String get cmdNewFolderWithSelection;

  /// No description provided for @cmdNewFile.
  ///
  /// In en, this message translates to:
  /// **'New File'**
  String get cmdNewFile;

  /// No description provided for @cmdNewTab.
  ///
  /// In en, this message translates to:
  /// **'New Tab'**
  String get cmdNewTab;

  /// No description provided for @cmdCloseTab.
  ///
  /// In en, this message translates to:
  /// **'Close Tab'**
  String get cmdCloseTab;

  /// No description provided for @cmdCloseOtherTabs.
  ///
  /// In en, this message translates to:
  /// **'Close Other Tabs'**
  String get cmdCloseOtherTabs;

  /// No description provided for @cmdReopenClosedTab.
  ///
  /// In en, this message translates to:
  /// **'Reopen Closed Tab'**
  String get cmdReopenClosedTab;

  /// No description provided for @cmdNextTab.
  ///
  /// In en, this message translates to:
  /// **'Next Tab'**
  String get cmdNextTab;

  /// No description provided for @cmdPreviousTab.
  ///
  /// In en, this message translates to:
  /// **'Previous Tab'**
  String get cmdPreviousTab;

  /// No description provided for @cmdToggleTabBar.
  ///
  /// In en, this message translates to:
  /// **'Show Tab Bar'**
  String get cmdToggleTabBar;

  /// No description provided for @cmdOpenItem.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get cmdOpenItem;

  /// No description provided for @cmdRevealInOppositePanel.
  ///
  /// In en, this message translates to:
  /// **'Reveal in Opposite Panel'**
  String get cmdRevealInOppositePanel;

  /// No description provided for @cmdRevealInOppositeTab.
  ///
  /// In en, this message translates to:
  /// **'Reveal in Opposite Panel Tab'**
  String get cmdRevealInOppositeTab;

  /// No description provided for @cmdCalcFolderSizes.
  ///
  /// In en, this message translates to:
  /// **'Calculate Folder Sizes'**
  String get cmdCalcFolderSizes;

  /// No description provided for @cmdCalcAllFolderSizes.
  ///
  /// In en, this message translates to:
  /// **'Calculate All Folder Sizes'**
  String get cmdCalcAllFolderSizes;

  /// No description provided for @cmdDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get cmdDuplicate;

  /// No description provided for @cmdAddToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Add to Favorites'**
  String get cmdAddToFavorites;

  /// No description provided for @cmdManageFavorites.
  ///
  /// In en, this message translates to:
  /// **'Manage Favorites…'**
  String get cmdManageFavorites;

  /// No description provided for @cmdFindFiles.
  ///
  /// In en, this message translates to:
  /// **'Find Files…'**
  String get cmdFindFiles;

  /// No description provided for @cmdCopyPaths.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get cmdCopyPaths;

  /// No description provided for @cmdPasteItems.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get cmdPasteItems;

  /// No description provided for @cmdMoveItemsHere.
  ///
  /// In en, this message translates to:
  /// **'Move Items Here'**
  String get cmdMoveItemsHere;

  /// No description provided for @cmdSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get cmdSelectAll;

  /// No description provided for @cmdDeselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect All'**
  String get cmdDeselectAll;

  /// No description provided for @cmdInvertSelection.
  ///
  /// In en, this message translates to:
  /// **'Invert Selection'**
  String get cmdInvertSelection;

  /// No description provided for @cmdSelectWithMask.
  ///
  /// In en, this message translates to:
  /// **'Select with Mask…'**
  String get cmdSelectWithMask;

  /// No description provided for @cmdDeselectWithMask.
  ///
  /// In en, this message translates to:
  /// **'Deselect with Mask…'**
  String get cmdDeselectWithMask;

  /// No description provided for @cmdSelectWithExtension.
  ///
  /// In en, this message translates to:
  /// **'Select with Extension'**
  String get cmdSelectWithExtension;

  /// No description provided for @cmdDeselectWithExtension.
  ///
  /// In en, this message translates to:
  /// **'Deselect with Extension'**
  String get cmdDeselectWithExtension;

  /// No description provided for @cmdToggleSinglePane.
  ///
  /// In en, this message translates to:
  /// **'Toggle Single-Panel Mode'**
  String get cmdToggleSinglePane;

  /// No description provided for @cmdSwapPanels.
  ///
  /// In en, this message translates to:
  /// **'Swap Panels'**
  String get cmdSwapPanels;

  /// No description provided for @cmdSyncPanels.
  ///
  /// In en, this message translates to:
  /// **'Sync Panels'**
  String get cmdSyncPanels;

  /// No description provided for @cmdViewMode.
  ///
  /// In en, this message translates to:
  /// **'View Mode {number}'**
  String cmdViewMode(int number);

  /// No description provided for @cmdSortByName.
  ///
  /// In en, this message translates to:
  /// **'Sort by Name'**
  String get cmdSortByName;

  /// No description provided for @cmdSortByExtension.
  ///
  /// In en, this message translates to:
  /// **'Sort by Extension'**
  String get cmdSortByExtension;

  /// No description provided for @cmdSortByModified.
  ///
  /// In en, this message translates to:
  /// **'Sort by Modified Time'**
  String get cmdSortByModified;

  /// No description provided for @cmdSortBySize.
  ///
  /// In en, this message translates to:
  /// **'Sort by Size'**
  String get cmdSortBySize;

  /// No description provided for @cmdSortByCreated.
  ///
  /// In en, this message translates to:
  /// **'Sort by Creation Time'**
  String get cmdSortByCreated;

  /// No description provided for @cmdSortByAdded.
  ///
  /// In en, this message translates to:
  /// **'Sort by Added Time'**
  String get cmdSortByAdded;

  /// No description provided for @cmdSortByAccessed.
  ///
  /// In en, this message translates to:
  /// **'Sort by Accessed Time'**
  String get cmdSortByAccessed;

  /// No description provided for @cmdToggleFoldersFirst.
  ///
  /// In en, this message translates to:
  /// **'Separate Folders from Files'**
  String get cmdToggleFoldersFirst;

  /// No description provided for @cmdToggleExtensionlessFolders.
  ///
  /// In en, this message translates to:
  /// **'Extensionless Folders'**
  String get cmdToggleExtensionlessFolders;

  /// No description provided for @cmdCollationNatural.
  ///
  /// In en, this message translates to:
  /// **'Natural Comparison'**
  String get cmdCollationNatural;

  /// No description provided for @cmdCollationCaseInsensitive.
  ///
  /// In en, this message translates to:
  /// **'Case-Insensitive Comparison'**
  String get cmdCollationCaseInsensitive;

  /// No description provided for @cmdCollationCaseSensitive.
  ///
  /// In en, this message translates to:
  /// **'Case-Sensitive Comparison'**
  String get cmdCollationCaseSensitive;

  /// No description provided for @cmdToggleHiddenFiles.
  ///
  /// In en, this message translates to:
  /// **'Show Hidden Items'**
  String get cmdToggleHiddenFiles;

  /// No description provided for @cmdPanelsMoveLeft.
  ///
  /// In en, this message translates to:
  /// **'Move the Split Left'**
  String get cmdPanelsMoveLeft;

  /// No description provided for @cmdPanelsMoveRight.
  ///
  /// In en, this message translates to:
  /// **'Move the Split Right'**
  String get cmdPanelsMoveRight;

  /// No description provided for @cmdResizePanels.
  ///
  /// In en, this message translates to:
  /// **'Resize Panels with the Keys'**
  String get cmdResizePanels;

  /// No description provided for @cmdRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get cmdRefresh;

  /// No description provided for @cmdToggleOperations.
  ///
  /// In en, this message translates to:
  /// **'Show Operations'**
  String get cmdToggleOperations;

  /// No description provided for @cmdGoToLeftPanel.
  ///
  /// In en, this message translates to:
  /// **'Go to… (Left Panel)'**
  String get cmdGoToLeftPanel;

  /// No description provided for @cmdGoToRightPanel.
  ///
  /// In en, this message translates to:
  /// **'Go to… (Right Panel)'**
  String get cmdGoToRightPanel;

  /// No description provided for @cmdGoBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get cmdGoBack;

  /// No description provided for @cmdGoForward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get cmdGoForward;

  /// No description provided for @cmdGoEnclosingFolder.
  ///
  /// In en, this message translates to:
  /// **'Enclosing Folder'**
  String get cmdGoEnclosingFolder;

  /// No description provided for @cmdGoInto.
  ///
  /// In en, this message translates to:
  /// **'Enter'**
  String get cmdGoInto;

  /// No description provided for @cmdFollowSymlink.
  ///
  /// In en, this message translates to:
  /// **'Follow Symbolic Link'**
  String get cmdFollowSymlink;

  /// No description provided for @cmdGoDocuments.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get cmdGoDocuments;

  /// No description provided for @cmdGoDesktop.
  ///
  /// In en, this message translates to:
  /// **'Desktop'**
  String get cmdGoDesktop;

  /// No description provided for @cmdGoDownloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get cmdGoDownloads;

  /// No description provided for @cmdGoHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get cmdGoHome;

  /// No description provided for @cmdGoLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get cmdGoLibrary;

  /// No description provided for @cmdGoApplications.
  ///
  /// In en, this message translates to:
  /// **'Applications'**
  String get cmdGoApplications;

  /// No description provided for @cmdGoUtilities.
  ///
  /// In en, this message translates to:
  /// **'Utilities'**
  String get cmdGoUtilities;

  /// No description provided for @cmdGoRoot.
  ///
  /// In en, this message translates to:
  /// **'Root'**
  String get cmdGoRoot;

  /// No description provided for @cmdQuickListParents.
  ///
  /// In en, this message translates to:
  /// **'Enclosing Folders'**
  String get cmdQuickListParents;

  /// No description provided for @cmdQuickListHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get cmdQuickListHistory;

  /// No description provided for @cmdQuickListFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get cmdQuickListFavorites;

  /// No description provided for @cmdQuickListVolumes.
  ///
  /// In en, this message translates to:
  /// **'Volumes'**
  String get cmdQuickListVolumes;

  /// No description provided for @cmdGoToFolder.
  ///
  /// In en, this message translates to:
  /// **'Go to Folder…'**
  String get cmdGoToFolder;

  /// No description provided for @cmdFileAttributes.
  ///
  /// In en, this message translates to:
  /// **'File Attributes…'**
  String get cmdFileAttributes;

  /// No description provided for @cmdCopyItemName.
  ///
  /// In en, this message translates to:
  /// **'Copy Item Name'**
  String get cmdCopyItemName;

  /// No description provided for @cmdCopyItemPath.
  ///
  /// In en, this message translates to:
  /// **'Copy Item Path'**
  String get cmdCopyItemPath;

  /// No description provided for @cmdCopyItemDirectory.
  ///
  /// In en, this message translates to:
  /// **'Copy Item Folder'**
  String get cmdCopyItemDirectory;

  /// No description provided for @cmdPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get cmdPreview;

  /// No description provided for @cmdInternalViewer.
  ///
  /// In en, this message translates to:
  /// **'Internal Viewer'**
  String get cmdInternalViewer;

  /// No description provided for @cmdExternalEditor.
  ///
  /// In en, this message translates to:
  /// **'External Editor'**
  String get cmdExternalEditor;

  /// No description provided for @cmdEjectVolume.
  ///
  /// In en, this message translates to:
  /// **'Eject Volume'**
  String get cmdEjectVolume;

  /// No description provided for @cmdBatchRename.
  ///
  /// In en, this message translates to:
  /// **'Batch Rename…'**
  String get cmdBatchRename;

  /// No description provided for @cmdCopyTo.
  ///
  /// In en, this message translates to:
  /// **'Copy To…'**
  String get cmdCopyTo;

  /// No description provided for @cmdCopyAs.
  ///
  /// In en, this message translates to:
  /// **'Copy As…'**
  String get cmdCopyAs;

  /// No description provided for @cmdMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move To…'**
  String get cmdMoveTo;

  /// No description provided for @cmdMoveAs.
  ///
  /// In en, this message translates to:
  /// **'Move As…'**
  String get cmdMoveAs;

  /// No description provided for @cmdRenameInPlace.
  ///
  /// In en, this message translates to:
  /// **'Rename in Place'**
  String get cmdRenameInPlace;

  /// No description provided for @cmdCreateDirectory.
  ///
  /// In en, this message translates to:
  /// **'Create Folder…'**
  String get cmdCreateDirectory;

  /// No description provided for @cmdCreateDirectoryInOppositePanel.
  ///
  /// In en, this message translates to:
  /// **'Create Folder in Opposite Panel…'**
  String get cmdCreateDirectoryInOppositePanel;

  /// No description provided for @cmdMoveToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get cmdMoveToTrash;

  /// No description provided for @cmdDeleteItems.
  ///
  /// In en, this message translates to:
  /// **'Delete…'**
  String get cmdDeleteItems;

  /// No description provided for @cmdDeletePermanently.
  ///
  /// In en, this message translates to:
  /// **'Delete Permanently…'**
  String get cmdDeletePermanently;

  /// No description provided for @cmdCompress.
  ///
  /// In en, this message translates to:
  /// **'Compress…'**
  String get cmdCompress;

  /// No description provided for @cmdCompressTo.
  ///
  /// In en, this message translates to:
  /// **'Compress To…'**
  String get cmdCompressTo;

  /// No description provided for @cmdCreateSymlink.
  ///
  /// In en, this message translates to:
  /// **'Create Symbolic Link…'**
  String get cmdCreateSymlink;

  /// No description provided for @cmdCreateHardlink.
  ///
  /// In en, this message translates to:
  /// **'Create Hard Link…'**
  String get cmdCreateHardlink;

  /// No description provided for @cmdEditSymlink.
  ///
  /// In en, this message translates to:
  /// **'Edit Symbolic Link…'**
  String get cmdEditSymlink;

  /// No description provided for @cmdRevealInFileManager.
  ///
  /// In en, this message translates to:
  /// **'Show in File Manager'**
  String get cmdRevealInFileManager;

  /// No description provided for @cmdOpenWith.
  ///
  /// In en, this message translates to:
  /// **'Open With…'**
  String get cmdOpenWith;

  /// No description provided for @cmdFocusLeftPanel.
  ///
  /// In en, this message translates to:
  /// **'Focus Left Panel'**
  String get cmdFocusLeftPanel;

  /// No description provided for @cmdFocusRightPanel.
  ///
  /// In en, this message translates to:
  /// **'Focus Right Panel'**
  String get cmdFocusRightPanel;

  /// No description provided for @cmdOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings…'**
  String get cmdOpenSettings;

  /// No description provided for @cmdHintMode.
  ///
  /// In en, this message translates to:
  /// **'Click Hints'**
  String get cmdHintMode;

  /// No description provided for @cmdCheatSheet.
  ///
  /// In en, this message translates to:
  /// **'Keyboard Shortcuts'**
  String get cmdCheatSheet;

  /// No description provided for @cmdContextMenu.
  ///
  /// In en, this message translates to:
  /// **'Show Context Menu'**
  String get cmdContextMenu;

  /// No description provided for @cmdMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move Up'**
  String get cmdMoveUp;

  /// No description provided for @cmdMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move Down'**
  String get cmdMoveDown;

  /// No description provided for @cmdMoveLeft.
  ///
  /// In en, this message translates to:
  /// **'Move Left'**
  String get cmdMoveLeft;

  /// No description provided for @cmdMoveRight.
  ///
  /// In en, this message translates to:
  /// **'Move Right'**
  String get cmdMoveRight;

  /// No description provided for @cmdMoveFirst.
  ///
  /// In en, this message translates to:
  /// **'Move to the First Item'**
  String get cmdMoveFirst;

  /// No description provided for @cmdMoveLast.
  ///
  /// In en, this message translates to:
  /// **'Move to the Last Item'**
  String get cmdMoveLast;

  /// No description provided for @cmdScrollFirst.
  ///
  /// In en, this message translates to:
  /// **'Scroll to the First Item'**
  String get cmdScrollFirst;

  /// No description provided for @cmdScrollLast.
  ///
  /// In en, this message translates to:
  /// **'Scroll to the Last Item'**
  String get cmdScrollLast;

  /// No description provided for @cmdMovePageUp.
  ///
  /// In en, this message translates to:
  /// **'Move to the Previous Page'**
  String get cmdMovePageUp;

  /// No description provided for @cmdMovePageDown.
  ///
  /// In en, this message translates to:
  /// **'Move to the Next Page'**
  String get cmdMovePageDown;

  /// No description provided for @cmdScrollPageUp.
  ///
  /// In en, this message translates to:
  /// **'Scroll to the Previous Page'**
  String get cmdScrollPageUp;

  /// No description provided for @cmdScrollPageDown.
  ///
  /// In en, this message translates to:
  /// **'Scroll to the Next Page'**
  String get cmdScrollPageDown;

  /// No description provided for @cmdSelectMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Select and Move Up'**
  String get cmdSelectMoveUp;

  /// No description provided for @cmdSelectMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Select and Move Down'**
  String get cmdSelectMoveDown;

  /// No description provided for @cmdSelectMoveLeft.
  ///
  /// In en, this message translates to:
  /// **'Select and Move Left'**
  String get cmdSelectMoveLeft;

  /// No description provided for @cmdSelectMoveRight.
  ///
  /// In en, this message translates to:
  /// **'Select and Move Right'**
  String get cmdSelectMoveRight;

  /// No description provided for @cmdSelectMoveFirst.
  ///
  /// In en, this message translates to:
  /// **'Select to the First Item'**
  String get cmdSelectMoveFirst;

  /// No description provided for @cmdSelectMoveLast.
  ///
  /// In en, this message translates to:
  /// **'Select to the Last Item'**
  String get cmdSelectMoveLast;

  /// No description provided for @cmdSelectMovePageUp.
  ///
  /// In en, this message translates to:
  /// **'Select to the Previous Page'**
  String get cmdSelectMovePageUp;

  /// No description provided for @cmdSelectMovePageDown.
  ///
  /// In en, this message translates to:
  /// **'Select to the Next Page'**
  String get cmdSelectMovePageDown;

  /// No description provided for @cmdToggleSelection.
  ///
  /// In en, this message translates to:
  /// **'Toggle Selection'**
  String get cmdToggleSelection;

  /// No description provided for @cmdToggleSelectionMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Toggle Selection and Move Down'**
  String get cmdToggleSelectionMoveDown;

  /// No description provided for @cmdEnterItem.
  ///
  /// In en, this message translates to:
  /// **'Enter'**
  String get cmdEnterItem;

  /// No description provided for @cmdGoParent.
  ///
  /// In en, this message translates to:
  /// **'Go to the Enclosing Folder'**
  String get cmdGoParent;

  /// No description provided for @cmdSwitchPanel.
  ///
  /// In en, this message translates to:
  /// **'Change Active Panel'**
  String get cmdSwitchPanel;

  /// No description provided for @cmdShowPreview.
  ///
  /// In en, this message translates to:
  /// **'Show Preview'**
  String get cmdShowPreview;

  /// No description provided for @cmdClearQuickSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear Quick Search'**
  String get cmdClearQuickSearch;

  /// No description provided for @cmdShowTab.
  ///
  /// In en, this message translates to:
  /// **'Show Tab {number}'**
  String cmdShowTab(int number);

  /// No description provided for @cmdViewerText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get cmdViewerText;

  /// No description provided for @cmdViewerHex.
  ///
  /// In en, this message translates to:
  /// **'Hex'**
  String get cmdViewerHex;

  /// No description provided for @cmdViewerPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get cmdViewerPreview;

  /// No description provided for @cmdViewerGoTo.
  ///
  /// In en, this message translates to:
  /// **'Go to Offset…'**
  String get cmdViewerGoTo;

  /// No description provided for @cmdViewerFind.
  ///
  /// In en, this message translates to:
  /// **'Find…'**
  String get cmdViewerFind;

  /// No description provided for @cmdViewerFindNext.
  ///
  /// In en, this message translates to:
  /// **'Find Next'**
  String get cmdViewerFindNext;

  /// No description provided for @cmdViewerFindPrevious.
  ///
  /// In en, this message translates to:
  /// **'Find Previous'**
  String get cmdViewerFindPrevious;

  /// No description provided for @cmdViewerToggleWrap.
  ///
  /// In en, this message translates to:
  /// **'Wrap Lines'**
  String get cmdViewerToggleWrap;

  /// No description provided for @cmdRenameItem.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get cmdRenameItem;

  /// No description provided for @cmdDeleteItem.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get cmdDeleteItem;

  /// No description provided for @cmdFilterList.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get cmdFilterList;

  /// No description provided for @cmdMoveItemUp.
  ///
  /// In en, this message translates to:
  /// **'Move Up'**
  String get cmdMoveItemUp;

  /// No description provided for @cmdVimVisual.
  ///
  /// In en, this message translates to:
  /// **'Visual Selection'**
  String get cmdVimVisual;

  /// No description provided for @cmdVimSearch.
  ///
  /// In en, this message translates to:
  /// **'Search in Panel'**
  String get cmdVimSearch;

  /// No description provided for @cmdVimSearchNext.
  ///
  /// In en, this message translates to:
  /// **'Next Match'**
  String get cmdVimSearchNext;

  /// No description provided for @cmdVimSearchPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous Match'**
  String get cmdVimSearchPrevious;

  /// No description provided for @cmdVimCommandLine.
  ///
  /// In en, this message translates to:
  /// **'Command Line'**
  String get cmdVimCommandLine;

  /// No description provided for @cmdVimCut.
  ///
  /// In en, this message translates to:
  /// **'Cut (Take to Move)'**
  String get cmdVimCut;

  /// No description provided for @cmdVimYank.
  ///
  /// In en, this message translates to:
  /// **'Yank (Take to Copy)'**
  String get cmdVimYank;

  /// No description provided for @cmdVimPaste.
  ///
  /// In en, this message translates to:
  /// **'Put Here'**
  String get cmdVimPaste;

  /// No description provided for @cmdVimCancelRegister.
  ///
  /// In en, this message translates to:
  /// **'Let the Taken Rows Go'**
  String get cmdVimCancelRegister;

  /// No description provided for @cmdVimFindChar.
  ///
  /// In en, this message translates to:
  /// **'Jump to a Name by Its First Letter'**
  String get cmdVimFindChar;

  /// No description provided for @cmdVimFindCharBack.
  ///
  /// In en, this message translates to:
  /// **'Jump Back to a Name by Its First Letter'**
  String get cmdVimFindCharBack;

  /// No description provided for @cmdVimRepeatFind.
  ///
  /// In en, this message translates to:
  /// **'Repeat the Jump'**
  String get cmdVimRepeatFind;

  /// No description provided for @cmdVimRepeatFindBack.
  ///
  /// In en, this message translates to:
  /// **'Repeat the Jump Backwards'**
  String get cmdVimRepeatFindBack;

  /// No description provided for @cmdVimSetMark.
  ///
  /// In en, this message translates to:
  /// **'Set a Mark'**
  String get cmdVimSetMark;

  /// No description provided for @cmdVimGoMark.
  ///
  /// In en, this message translates to:
  /// **'Go to a Mark'**
  String get cmdVimGoMark;

  /// No description provided for @cmdVimScreenTop.
  ///
  /// In en, this message translates to:
  /// **'Top of the Screen'**
  String get cmdVimScreenTop;

  /// No description provided for @cmdVimScreenMiddle.
  ///
  /// In en, this message translates to:
  /// **'Middle of the Screen'**
  String get cmdVimScreenMiddle;

  /// No description provided for @cmdVimScreenBottom.
  ///
  /// In en, this message translates to:
  /// **'Bottom of the Screen'**
  String get cmdVimScreenBottom;

  /// No description provided for @cmdVimScrollCenter.
  ///
  /// In en, this message translates to:
  /// **'Scroll the Cursor to the Middle'**
  String get cmdVimScrollCenter;

  /// No description provided for @cmdVimScrollTop.
  ///
  /// In en, this message translates to:
  /// **'Scroll the Cursor to the Top'**
  String get cmdVimScrollTop;

  /// No description provided for @cmdVimScrollBottom.
  ///
  /// In en, this message translates to:
  /// **'Scroll the Cursor to the Bottom'**
  String get cmdVimScrollBottom;

  /// No description provided for @cmdVimHalfPageDown.
  ///
  /// In en, this message translates to:
  /// **'Half a Page Down'**
  String get cmdVimHalfPageDown;

  /// No description provided for @cmdVimHalfPageUp.
  ///
  /// In en, this message translates to:
  /// **'Half a Page Up'**
  String get cmdVimHalfPageUp;

  /// No description provided for @cmdVimColumnNext.
  ///
  /// In en, this message translates to:
  /// **'Next Column'**
  String get cmdVimColumnNext;

  /// No description provided for @cmdVimColumnPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous Column'**
  String get cmdVimColumnPrevious;

  /// No description provided for @cmdVimRenameAppend.
  ///
  /// In en, this message translates to:
  /// **'Rename at the End of the Name'**
  String get cmdVimRenameAppend;

  /// No description provided for @cmdVimRenamePrepend.
  ///
  /// In en, this message translates to:
  /// **'Rename at the Start of the Name'**
  String get cmdVimRenamePrepend;

  /// No description provided for @cmdVimSortReverse.
  ///
  /// In en, this message translates to:
  /// **'Reverse the Sort Order'**
  String get cmdVimSortReverse;

  /// No description provided for @cmdVimReselect.
  ///
  /// In en, this message translates to:
  /// **'Reselect the Last Selection'**
  String get cmdVimReselect;

  /// No description provided for @cmdMoveItemDown.
  ///
  /// In en, this message translates to:
  /// **'Move Down'**
  String get cmdMoveItemDown;

  /// No description provided for @cmdConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get cmdConfirm;

  /// No description provided for @cmdDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get cmdDismiss;

  /// No description provided for @cmdCommandPalette.
  ///
  /// In en, this message translates to:
  /// **'Command Palette'**
  String get cmdCommandPalette;

  /// No description provided for @cmdJumpToFolder.
  ///
  /// In en, this message translates to:
  /// **'Jump to a Frequent Folder'**
  String get cmdJumpToFolder;

  /// No description provided for @cmdAddToShelf.
  ///
  /// In en, this message translates to:
  /// **'Add to the Shelf'**
  String get cmdAddToShelf;

  /// No description provided for @cmdToggleShelf.
  ///
  /// In en, this message translates to:
  /// **'Show or Hide the Shelf'**
  String get cmdToggleShelf;

  /// No description provided for @cmdRenameInEditor.
  ///
  /// In en, this message translates to:
  /// **'Rename in an Editor'**
  String get cmdRenameInEditor;

  /// No description provided for @paletteHint.
  ///
  /// In en, this message translates to:
  /// **'Type a command'**
  String get paletteHint;

  /// No description provided for @paletteNoResults.
  ///
  /// In en, this message translates to:
  /// **'No command matches'**
  String get paletteNoResults;

  /// No description provided for @paletteRecent.
  ///
  /// In en, this message translates to:
  /// **'Recently used'**
  String get paletteRecent;

  /// No description provided for @paletteKeySelect.
  ///
  /// In en, this message translates to:
  /// **'select'**
  String get paletteKeySelect;

  /// No description provided for @paletteKeyRun.
  ///
  /// In en, this message translates to:
  /// **'run'**
  String get paletteKeyRun;

  /// No description provided for @paletteKeyClose.
  ///
  /// In en, this message translates to:
  /// **'close'**
  String get paletteKeyClose;

  /// No description provided for @paletteSectionFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get paletteSectionFile;

  /// No description provided for @paletteSectionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get paletteSectionEdit;

  /// No description provided for @paletteSectionView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get paletteSectionView;

  /// No description provided for @paletteSectionGo.
  ///
  /// In en, this message translates to:
  /// **'Go'**
  String get paletteSectionGo;

  /// No description provided for @paletteSectionCommand.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get paletteSectionCommand;

  /// No description provided for @paletteSectionWindow.
  ///
  /// In en, this message translates to:
  /// **'Window'**
  String get paletteSectionWindow;

  /// No description provided for @paletteSectionPanel.
  ///
  /// In en, this message translates to:
  /// **'File panel'**
  String get paletteSectionPanel;

  /// No description provided for @paletteSectionVim.
  ///
  /// In en, this message translates to:
  /// **'Vim'**
  String get paletteSectionVim;

  /// No description provided for @paletteSectionViewer.
  ///
  /// In en, this message translates to:
  /// **'Viewer'**
  String get paletteSectionViewer;

  /// No description provided for @paletteSectionLists.
  ///
  /// In en, this message translates to:
  /// **'Lists'**
  String get paletteSectionLists;

  /// No description provided for @paletteSectionDialogs.
  ///
  /// In en, this message translates to:
  /// **'Dialogs'**
  String get paletteSectionDialogs;

  /// No description provided for @jumpTitle.
  ///
  /// In en, this message translates to:
  /// **'Jump to a frequent folder'**
  String get jumpTitle;

  /// No description provided for @jumpHint.
  ///
  /// In en, this message translates to:
  /// **'Type parts of the folder’s path'**
  String get jumpHint;

  /// No description provided for @jumpEmpty.
  ///
  /// In en, this message translates to:
  /// **'The folders you open show here, the most used first'**
  String get jumpEmpty;

  /// No description provided for @jumpNoResults.
  ///
  /// In en, this message translates to:
  /// **'No folder you visited matches'**
  String get jumpNoResults;

  /// No description provided for @jumpKeyOpen.
  ///
  /// In en, this message translates to:
  /// **'open'**
  String get jumpKeyOpen;

  /// No description provided for @jumpKeyNewTab.
  ///
  /// In en, this message translates to:
  /// **'in a new tab'**
  String get jumpKeyNewTab;

  /// No description provided for @jumpKeyOtherPanel.
  ///
  /// In en, this message translates to:
  /// **'in the other panel'**
  String get jumpKeyOtherPanel;

  /// No description provided for @jumpGone.
  ///
  /// In en, this message translates to:
  /// **'{path} is gone; it is off the list now'**
  String jumpGone(String path);

  /// No description provided for @jumpNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No folder you visited matches “{query}”'**
  String jumpNoMatch(String query);

  /// No description provided for @shelfTitle.
  ///
  /// In en, this message translates to:
  /// **'Shelf'**
  String get shelfTitle;

  /// No description provided for @shelfNote.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 on the shelf} other{{count} on the shelf}}'**
  String shelfNote(int count);

  /// No description provided for @shelfAdded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item put on the shelf} other{{count} items put on the shelf}}'**
  String shelfAdded(int count);

  /// No description provided for @shelfEmpty.
  ///
  /// In en, this message translates to:
  /// **'Gather files from any folder with {key}, then copy or move them here together'**
  String shelfEmpty(String key);

  /// No description provided for @shelfClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get shelfClear;

  /// No description provided for @shelfCopyHere.
  ///
  /// In en, this message translates to:
  /// **'Copy Here'**
  String get shelfCopyHere;

  /// No description provided for @shelfMoveHere.
  ///
  /// In en, this message translates to:
  /// **'Move Here'**
  String get shelfMoveHere;

  /// No description provided for @shelfInto.
  ///
  /// In en, this message translates to:
  /// **'Into {folder}'**
  String shelfInto(String folder);

  /// No description provided for @shelfRemove.
  ///
  /// In en, this message translates to:
  /// **'Take off the shelf'**
  String get shelfRemove;

  /// No description provided for @shelfMissing.
  ///
  /// In en, this message translates to:
  /// **'no longer there'**
  String get shelfMissing;

  /// No description provided for @shelfMissingTooltip.
  ///
  /// In en, this message translates to:
  /// **'{path} is no longer on disk'**
  String shelfMissingTooltip(String path);

  /// No description provided for @shelfCutTooltip.
  ///
  /// In en, this message translates to:
  /// **'Moved, not copied, when put'**
  String get shelfCutTooltip;

  /// No description provided for @shelfAlreadyHere.
  ///
  /// In en, this message translates to:
  /// **'The shelf’s items are in this folder already'**
  String get shelfAlreadyHere;

  /// No description provided for @shelfNothingToPut.
  ///
  /// In en, this message translates to:
  /// **'None of the shelf’s items is on disk any more'**
  String get shelfNothingToPut;

  /// No description provided for @shelfHintReveal.
  ///
  /// In en, this message translates to:
  /// **'show in the panel'**
  String get shelfHintReveal;

  /// No description provided for @shelfHintRemove.
  ///
  /// In en, this message translates to:
  /// **'take off'**
  String get shelfHintRemove;
}

class _FerryxLocalizationsDelegate
    extends LocalizationsDelegate<FerryxLocalizations> {
  const _FerryxLocalizationsDelegate();

  @override
  Future<FerryxLocalizations> load(Locale locale) {
    return SynchronousFuture<FerryxLocalizations>(
      lookupFerryxLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_FerryxLocalizationsDelegate old) => false;
}

FerryxLocalizations lookupFerryxLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return FerryxLocalizationsEn();
    case 'ru':
      return FerryxLocalizationsRu();
  }

  throw FlutterError(
    'FerryxLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
