import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Every icon the app uses, backed by Lucide. Swap sets here only.
abstract final class AppIcons {
  // Navigation
  static const IconData search = LucideIcons.search;
  static const IconData today = LucideIcons.calendar;
  static const IconData documents = LucideIcons.fileText;
  static const IconData flashcards = LucideIcons.layers;
  static const IconData graph = LucideIcons.waypoints;
  static const IconData trash = LucideIcons.trash2;
  static const IconData settings = LucideIcons.settings;
  static const IconData bookmark = LucideIcons.star;
  static const IconData pin = LucideIcons.pin;
  static const IconData bookmarkRemove = LucideIcons.starOff;
  static const IconData savedSearch = LucideIcons.textSearch;

  /// A rem that is not a page: a bookmark of one, a dot like its bullet.
  static const IconData rem = LucideIcons.dot;
  static const IconData tag = LucideIcons.hash;
  static const IconData folder = LucideIcons.folder;
  static const IconData document = LucideIcons.file;

  // Chrome
  static const IconData sidebar = LucideIcons.panelLeft;
  static const IconData rightPanel = LucideIcons.panelRight;
  static const IconData split = LucideIcons.columns2;
  static const IconData more = LucideIcons.ellipsis;
  static const IconData close = LucideIcons.x;

  // Window buttons of an app-drawn header bar.
  static const IconData windowMinimize = LucideIcons.minus;
  static const IconData windowMaximize = LucideIcons.square;
  static const IconData windowRestore = LucideIcons.copy;
  static const IconData back = LucideIcons.arrowLeft;
  static const IconData forward = LucideIcons.arrowRight;
  static const IconData up = LucideIcons.arrowUp;
  static const IconData chevronDown = LucideIcons.chevronDown;
  static const IconData chevronRight = LucideIcons.chevronRight;
  static const IconData chevronLeft = LucideIcons.chevronLeft;
  static const IconData chevronUp = LucideIcons.chevronUp;

  /// A pop-up button's two chevrons: the choice can go either way.
  static const IconData chevronsUpDown = LucideIcons.chevronsUpDown;
  static const IconData add = LucideIcons.plus;
  static const IconData addCircle = LucideIcons.circlePlus;
  static const IconData check = LucideIcons.check;

  /// A mixed check box: on for some of the items.
  static const IconData minus = LucideIcons.minus;
  static const IconData copy = LucideIcons.copy;
  static const IconData edit = LucideIcons.pencil;
  static const IconData undo = LucideIcons.undo2;
  static const IconData info = LucideIcons.info;
  static const IconData keyboard = LucideIcons.keyboard;
  static const IconData link = LucideIcons.link;
  static const IconData externalLink = LucideIcons.externalLink;
  static const IconData dragHandle = LucideIcons.gripVertical;
  static const IconData filter = LucideIcons.listFilter;
  static const IconData refresh = LucideIcons.refreshCw;
  static const IconData warning = LucideIcons.triangleAlert;
  static const IconData merge = LucideIcons.merge;
  static const IconData calloutNote = LucideIcons.info;
  static const IconData calloutTip = LucideIcons.lightbulb;
  static const IconData calloutImportant = LucideIcons.messageSquareWarning;
  static const IconData calloutWarning = LucideIcons.triangleAlert;
  static const IconData calloutCaution = LucideIcons.octagonAlert;
  static const IconData tableOfContents = LucideIcons.tableOfContents;
  static const IconData reveal = LucideIcons.folderOpen;
  static const IconData resizeWidth = LucideIcons.moveHorizontal;
  static const IconData error = LucideIcons.circleAlert;

  // Editor blocks
  static const IconData heading = LucideIcons.heading;
  static const IconData todo = LucideIcons.squareCheck;
  static const IconData taskOpen = LucideIcons.square;
  static const IconData quote = LucideIcons.quote;
  static const IconData code = LucideIcons.code;
  static const IconData image = LucideIcons.image;
  static const IconData imageOff = LucideIcons.imageOff;
  static const IconData pdf = LucideIcons.bookOpenText;
  static const IconData outline = LucideIcons.tableOfContents;
  static const IconData magnifyIn = LucideIcons.zoomIn;
  static const IconData magnifyOut = LucideIcons.zoomOut;
  static const IconData highlighter = LucideIcons.highlighter;
  static const IconData areaSelect = LucideIcons.squareDashedMousePointer;
  static const IconData note = LucideIcons.stickyNote;
  static const IconData divider = LucideIcons.minus;
  static const IconData math = LucideIcons.sigma;
  static const IconData table = LucideIcons.table;
  static const IconData card = LucideIcons.layers;
  static const IconData cardForward = LucideIcons.arrowRight;
  static const IconData cardBackward = LucideIcons.arrowLeft;
  static const IconData cardBoth = LucideIcons.arrowLeftRight;
  static const IconData cardCloze = LucideIcons.rectangleEllipsis;
  static const IconData cardList = LucideIcons.list;
  static const IconData cardChoice = LucideIcons.listChecks;
  static const IconData cardListItem = LucideIcons.listOrdered;
  static const IconData numberedList = LucideIcons.listOrdered;
  static const IconData heading1 = LucideIcons.heading1;
  static const IconData heading2 = LucideIcons.heading2;
  static const IconData heading3 = LucideIcons.heading3;

  // Key symbols drawn inside key caps, so every platform shows the same
  // glyphs instead of whatever font happens to hold ⌘ or ⇧.
  static const IconData keyCommand = LucideIcons.command;
  static const IconData keyShift = LucideIcons.arrowBigUp;
  static const IconData keyOption = LucideIcons.option;
  static const IconData keyControl = LucideIcons.chevronUp;
  static const IconData keyEnter = LucideIcons.cornerDownLeft;
  static const IconData keyBackspace = LucideIcons.delete;
  static const IconData keyTab = LucideIcons.arrowRightToLine;
  static const IconData keyUp = LucideIcons.arrowUp;
  static const IconData keyDown = LucideIcons.arrowDown;
  static const IconData keyLeft = LucideIcons.arrowLeft;
  static const IconData keyRight = LucideIcons.arrowRight;
  static const IconData zoomIn = LucideIcons.focus;

  // Flashcards
  static const IconData play = LucideIcons.play;
  static const IconData skip = LucideIcons.skipForward;
  static const IconData streak = LucideIcons.flame;
  static const IconData history = LucideIcons.history;
  static const IconData pause = LucideIcons.pause;

  /// A rem set aside to be rewritten, its cards out of review; not a
  /// pencil, which is [edit] beside it in the review's menu.
  static const IconData rework = LucideIcons.wrench;

  /// A card taken out of review for good.
  static const IconData disableCard = LucideIcons.circlePause;

  /// Cards laid out over several days.
  static const IconData spreadDays = LucideIcons.chartColumn;

  /// A practice in a random order, and in the documents' order.
  static const IconData practiceShuffled = LucideIcons.shuffle;
  static const IconData practiceInOrder = LucideIcons.listOrdered;

  /// The review grows to the whole window, or goes back to a window over
  /// the app.
  static const IconData fillWindow = LucideIcons.maximize2;
  static const IconData showAsWindow = LucideIcons.minimize2;

  // Knowledge bases
  static const IconData database = LucideIcons.database;
  static const IconData backup = LucideIcons.archive;
  static const IconData folderOpen = LucideIcons.folderOpen;
  static const IconData import = LucideIcons.download;
  static const IconData export = LucideIcons.upload;
  static const IconData shield = LucideIcons.shieldCheck;

  // Files and folders
  static const IconData file = LucideIcons.file;
  static const IconData fileText = LucideIcons.fileText;
  static const IconData fileCode = LucideIcons.fileCode;
  static const IconData fileImage = LucideIcons.fileImage;
  static const IconData fileAudio = LucideIcons.fileAudio;
  static const IconData fileVideo = LucideIcons.fileVideo;
  static const IconData fileArchive = LucideIcons.fileArchive;
  static const IconData fileSpreadsheet = LucideIcons.fileSpreadsheet;
  static const IconData filePdf = LucideIcons.fileType;
  static const IconData fileExecutable = LucideIcons.squareTerminal;
  static const IconData fileSymlink = LucideIcons.fileSymlink;
  static const IconData folderSymlink = LucideIcons.folderSymlink;
  static const IconData folderUp = LucideIcons.cornerLeftUp;
  static const IconData application = LucideIcons.appWindowMac;
  static const IconData hardDrive = LucideIcons.hardDrive;
  static const IconData usb = LucideIcons.usb;
  static const IconData eject = LucideIcons.circleArrowUp;
  static const IconData home = LucideIcons.house;
  static const IconData desktop = LucideIcons.monitor;
  static const IconData downloads = LucideIcons.download;
  static const IconData star = LucideIcons.star;
  static const IconData clock = LucideIcons.clock;
  static const IconData sort = LucideIcons.arrowDownUp;
  static const IconData layoutList = LucideIcons.list;
  static const IconData layoutBrief = LucideIcons.columns3;
  static const IconData terminal = LucideIcons.terminal;
  static const IconData hidden = LucideIcons.eyeOff;
  static const IconData visible = LucideIcons.eye;
  static const IconData swap = LucideIcons.arrowLeftRight;
  static const IconData singlePane = LucideIcons.square;
  static const IconData dualPane = LucideIcons.columns2;
  static const IconData stackedPanes = LucideIcons.rows2;
  static const IconData operations = LucideIcons.activity;
  static const IconData checkCircle = LucideIcons.circleCheck;
  static const IconData wrench = LucideIcons.wrench;
  static const IconData lock = LucideIcons.lock;
  static const IconData calculator = LucideIcons.calculator;
  static const IconData scissors = LucideIcons.scissors;
  static const IconData paste = LucideIcons.clipboardPaste;
  static const IconData cancel = LucideIcons.circleX;
  static const IconData goTo = LucideIcons.compass;
  static const IconData hex = LucideIcons.binary;
  static const IconData text = LucideIcons.alignLeft;
  static const IconData preview = LucideIcons.scanEye;
  static const IconData wrap = LucideIcons.wrapText;
  static const IconData quickLook = LucideIcons.eye;
  static const IconData share = LucideIcons.share;

  // Appearance
  static const IconData sun = LucideIcons.sun;
  static const IconData moon = LucideIcons.moon;
  static const IconData monitor = LucideIcons.monitor;

  // ─── Terminal ───
  static const IconData terminalHide = LucideIcons.panelBottomClose;
  static const IconData terminalTab = LucideIcons.squareTerminal;
  static const IconData terminalDock = LucideIcons.panelBottomOpen;
  static const IconData panelsHide = LucideIcons.panelTopClose;
  static const IconData panelsShow = LucideIcons.panelTopOpen;
  static const IconData clear = LucideIcons.eraser;
  // ─── Operations stream ───
  static const IconData redo = LucideIcons.redo2;
  static const IconData compareFolders = LucideIcons.gitCompareArrows;
  static const IconData synchronize = LucideIcons.folderSync;
  static const IconData checksum = LucideIcons.fingerprint;
  static const IconData duplicates = LucideIcons.files;
  static const IconData equal = LucideIcons.equal;
  static const IconData notEqual = LucideIcons.equalNot;
  // ─── Network ───
  static const IconData server = LucideIcons.server;
  static const IconData serverOff = LucideIcons.serverOff;
  static const IconData globe = LucideIcons.globe;
  static const IconData unlocked = LucideIcons.lockOpen;
  static const IconData disconnect = LucideIcons.unplug;
  static const IconData keyFile = LucideIcons.keyRound;
  static const IconData shieldAlert = LucideIcons.shieldAlert;
}
