/// Layout dimensions shared by every platform style: widths of panels,
/// dialogs and documents, the window's minimum. Heights of controls, rows
/// and the window's top row are the platform's (`context.metrics`).
abstract final class AppSizes {
  /// Below this width a pane's top bar tries its compact actions first,
  /// before it has measured the full set (`AppTopBarRow`).
  static const double paneCompactWidth = 600;

  /// Room a top bar's title keeps when the bar weighs its actions.
  static const double topBarTitleMinWidth = 64;

  /// Below this width a list pane stacks its filter row.
  static const double paneWideHeader = 760;
  static const double sidebarWidth = 240;
  static const double sidebarRailWidth = 52;
  static const double sidebarMinWidth = 180;
  static const double sidebarMaxWidth = 480;

  /// Dragging the sidebar edge narrower than this folds it to the rail.
  static const double sidebarCollapseWidth = 120;
  static const double resizeHandleWidth = 6;

  /// Short accent bars: active tabs, drop targets and editor cursors.
  static const double focusBarHeight = 2;

  /// Inset outline around the area receiving keys (`AppFocusArea`).
  static const double focusFrameWidth = 2;

  /// Leading marker of the current file, independent of marked selections.
  static const double cursorBarWidth = 3;

  /// How narrow a pane of a split may get by moving the edge between them.
  static const double paneMinWidth = 320;
  static const double rightPanelWidth = 300;
  static const double rightPanelMinWidth = 240;
  static const double rightPanelMaxWidth = 480;

  /// The card beside a panel edge that the keys are moving.
  static const double splitterBadgeWidth = 320;
  static const double documentMaxWidth = 720;

  /// Room for the page/section position before document actions compact.
  static const double documentPositionMinWidth = 240;

  /// Tallest an image shows inside a rem; the viewer has the whole image.
  static const double imageMaxHeight = 480;
  static const double thumbnailCellWidth = 160;
  static const double thumbnailImageHeight = 112;
  static const double documentWideMaxWidth = 900;
  static const double previewTableMinColumnWidth = 120;
  static const double previewTableMaxColumnWidth = 360;
  static const double previewTableIndexWidth = 52;

  /// Formatted documents need room for full words and multi-line headings.
  static const double documentTableCellWidth = 180;
  static const double dialogWidth = 560;

  /// A dialog holding one field or one key cap: a name prompt, a shortcut
  /// being pressed.
  static const double compactDialogWidth = 420;

  /// A dialog's push button at least: NSAlert's and the HIG's 68 (OK, No).
  static const double dialogButtonMinWidth = 68;

  /// A card of an operation under way, floating over the panels.
  static const double operationCardWidth = 360;
  static const double panelDialogWidth = 760;
  static const double panelDialogHeight = 600;
  static const double panelDialogNavWidth = 240;
  static const double settingsDialogWidth = 1040;

  /// The review as a window over the app; smaller windows give it what
  /// they have past the dialog's margins. One size for every card, so
  /// the buttons stay put from card to card.
  static const double reviewSheetWidth = 840;
  static const double reviewSheetHeight = 600;

  /// A rating button at text scale 1: its label and interval with room
  /// above and below; it grows with the text.
  static const double ratingButtonMinHeight = 72;
  static const double settingsNavWidth = 240;

  /// A slider at the end of a settings row.
  static const double settingsSliderWidth = 240;

  /// A number field at the end of a settings row: four digits and a margin.
  static const double settingsNumberFieldWidth = 88;

  /// A search field in a title bar (the settings' Shortcuts page, the
  /// cheat sheet).
  static const double titleBarSearchWidth = 240;

  /// Narrowest a column of the cheat sheet gets; the columns share the
  /// sheet's width.
  static const double cheatSheetColumnWidth = 300;

  /// Narrowest an [AppKeysPanel] beside its place gets at text scale 1:
  /// two keys and their words to a line.
  static const double keysPanelMinWidth = 340;

  /// Narrowest a stat tile gets at text scale 1 (`AppStatTiles`); wider
  /// with the text.
  static const double statTileMinWidth = 96;

  static const double paletteWidth = 680;

  /// The list of a picker dialog (a tag, a page by name): about eight
  /// rows, then it scrolls.
  static const double pickerListMaxHeight = 280;

  /// A menu sized to its widest item stays within these, as NSMenu,
  /// Fluent flyouts and libadwaita popovers do.
  static const double menuMinWidth = 180;
  static const double menuMaxWidth = 420;
  static const double minWindowWidth = 900;
  static const double minWindowHeight = 600;

  // ─── Operations stream ───

  /// A dialog around a table of results (Synchronize Folders, Find
  /// Duplicates, Checksums): room for a path and two sides of figures.
  static const double resultsDialogWidth = 960;

  /// Its table at most; a lower window shrinks it.
  static const double resultsTableHeight = 360;

  /// A table's narrow column of one glyph (an action, a check box).
  static const double glyphColumnWidth = 36;

  /// A field for a short mask (`*.jpg;*.png`) beside other options.
  static const double maskFieldWidth = 220;

  // ─── Network ───

  /// A port number's field beside its host's (five figures and room).
  static const double portFieldWidth = 96;
}
