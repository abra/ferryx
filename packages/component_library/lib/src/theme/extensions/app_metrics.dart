import 'package:flutter/material.dart';

import '../app_platform_style.dart';
import '../app_typography.dart';
import '../tokens/app_radius.dart';

/// Corner radii of one platform style, by what they round.
@immutable
class AppRadii {
  const AppRadii({
    required this.chip,
    required this.control,
    required this.row,
    required this.menu,
    required this.menuItem,
    required this.card,
    required this.popover,
    required this.dialog,
    double? tableRow,
    double? tableFrame,
    double? field,
    double? search,
    double? alert,
    double? alertAction,
  }) : tableRow = tableRow ?? row,
       tableFrame = tableFrame ?? card,
       field = field ?? control,
       search = search ?? control,
       alert = alert ?? dialog,
       alertAction = alertAction ?? control;

  /// Tags, key caps, page chips, small badges.
  final double chip;

  /// Push buttons, text fields, segmented controls, icon buttons.
  final double control;

  /// The highlight of a sidebar or list row.
  final double row;

  /// The highlight of a table's row (a panel's files, a dialog's table of
  /// results): a list row's unless the platform's tables draw it square
  /// (Finder's list view up to macOS 15).
  final double tableRow;

  /// The frame of a table inside a dialog (find results, a comparison):
  /// a card's unless the platform's bezeled scroll views are square (macOS
  /// 15).
  final double tableFrame;

  /// Context menus and the slash menu.
  final double menu;

  /// The highlight of a menu item, inset in the menu.
  final double menuItem;

  /// Settings groups, stat tiles, panels inside a pane.
  final double card;

  /// Popovers and pickers anchored to a control.
  final double popover;

  /// Alerts and dialogs.
  final double dialog;

  /// Text fields: a push button's unless the platform squares them (an
  /// NSTextField up to macOS 15).
  final double field;

  /// Search fields: a push button's unless the platform rounds them more
  /// (a capsule on macOS 26).
  final double search;

  /// An alert (a short question, no form): a dialog's unless the platform
  /// rounds it more (AdwAlertDialog).
  final double alert;

  /// An alert's buttons: a push button's unless the platform rounds them
  /// more.
  final double alertAction;
}

/// How a sidebar marks the selected row.
enum AppNavSelection {
  /// macOS source list: a grey fill, the accent while the list has the
  /// keyboard focus.
  tint,

  /// Fluent NavigationView: a subtle fill and an accent pill at the left.
  indicator,

  /// libadwaita navigation sidebar: a fill of the text colour.
  fill,
}

/// The unit a platform names logical lengths in.
enum AppLengthUnit { points, pixels }

/// What differs between the platform styles besides colour: sizes, radii,
/// type families and the behaviour of shared controls.
///
/// Built once per style; read through `context.metrics`. Spacing stays on
/// the shared 4-pt grid (`AppSpacing`) and layout widths in `AppSizes`;
/// whatever a platform draws differently lives here, so features never
/// branch on the platform themselves.
@immutable
class AppMetrics extends ThemeExtension<AppMetrics> {
  const AppMetrics({
    required this.style,
    this.generation = MacGeneration.sequoia,
    required this.typeScale,
    required this.radius,
    required this.topBarHeight,
    required this.navItemHeight,
    required this.menuItemHeight,
    required this.controlHeight,
    required this.controlHeightSmall,
    required this.controlHeightLarge,
    required this.iconButtonSize,
    required this.toolbarSpacing,
    required this.focusRingWidth,
    required this.focusRingGap,
    required this.navSelection,
    required this.navHover,
    required this.menuHighlightAccent,
    required this.contentLayer,
    required this.centeredBarTitle,
    required this.toggleSize,
    required this.toggleKnob,
    double? toggleKnobWidth,
    required this.lengthUnit,
    this.navItemGap = 0,
    this.navRowMargin = 8,
    this.navRowPadding = 8,
    this.navLabelGap = 8,
    this.navIndent = 16,
    this.rowInset = 8,
    double? tableRowInset,
    this.listRowHeight = 22,
    this.contentMargin = 20,
    this.menuInset = 5,
    this.menuItemMargin = EdgeInsets.zero,
    this.menuItemPadding = 8,
    this.menuSeparatorSpace = 4,
    this.menuShortcutGap = 16,
    this.dragThreshold = 4,
    this.menuIcons = true,
    this.menuCheckWidth = 18,
    this.menuCheckPull = -2,
    this.menuIconGap = 8,
    this.sheetDim = 0,
    this.sheetDimDark = 0,
    this.fieldPadding = 10,
    this.popupCap = false,
    this.bezelShade = false,
  }) : toggleKnobWidth = toggleKnobWidth ?? toggleKnob,
       tableRowInset = tableRowInset ?? rowInset;

  /// The metrics of [style]; on macOS, of the system's [generation].
  factory AppMetrics.of(
    AppPlatformStyle style, {
    MacGeneration generation = MacGeneration.sequoia,
  }) => switch (style) {
    AppPlatformStyle.macos => switch (generation) {
      MacGeneration.sequoia => _macos,
      MacGeneration.tahoe => _macosTahoe,
    },
    AppPlatformStyle.windows => _windows,
    AppPlatformStyle.gnome => _gnome,
  };

  final AppPlatformStyle style;

  /// The macOS release the metrics follow; Sequoia for the other styles.
  final MacGeneration generation;

  /// Families and the monospace and key-cap styles of the style.
  final AppTypeScale typeScale;
  final AppRadii radius;

  /// The window's top row: pane bars, the sidebar's strip, the title strip.
  /// macOS: a unified toolbar (the runner centres the traffic lights in
  /// it); GNOME: a header bar; Windows: the command bar under the system
  /// title bar.
  final double topBarHeight;

  /// Sidebar and document-tree rows.
  final double navItemHeight;
  final double menuItemHeight;

  /// Push buttons, text fields and pop-up buttons at the regular size.
  final double controlHeight;
  final double controlHeightSmall;
  final double controlHeightLarge;

  /// Borderless icon buttons in bars and panels.
  final Size iconButtonSize;

  /// Space between neighbouring controls of a bar (icon buttons, a push
  /// button beside them), so their hover fills and focus rings stay apart:
  /// the header bar's spacing on GNOME, a command bar's on Windows, a
  /// toolbar's on macOS. Groups of controls sit further apart.
  final double toolbarSpacing;

  /// The keyboard focus ring, drawn outside the control.
  final double focusRingWidth;

  /// Space between a control's edge and its focus ring; negative draws the
  /// ring inside the control (libadwaita).
  final double focusRingGap;
  final AppNavSelection navSelection;

  /// Whether a sidebar row lights up under the pointer (macOS source lists
  /// do not).
  final bool navHover;

  /// Whether the highlighted menu item takes the accent with light text
  /// (macOS) rather than a subtle fill.
  final bool menuHighlightAccent;

  /// Fluent: the panes sit on a layer with a rounded top-left corner over
  /// the window's backdrop, the sidebar on the backdrop itself.
  final bool contentLayer;

  /// libadwaita: a header bar's title sits in the middle of the bar, as
  /// far as its buttons allow; the others start it after the buttons.
  final bool centeredBarTitle;

  /// Track of the on/off switch, and its knob's height and width: a
  /// circle, or a pill wider than tall (macOS 26).
  final Size toggleSize;
  final double toggleKnob;
  final double toggleKnobWidth;

  /// What a logical length is called where the interface shows one (a
  /// panel's width): points on macOS, pixels elsewhere.
  final AppLengthUnit lengthUnit;

  /// Space between two sidebar rows, inside a row's extent: Fluent's
  /// NavigationView items stand 4 apart (36 high, 40 apart), libadwaita's
  /// 2 (36, 38); a source list's rows touch.
  final double navItemGap;

  /// A sidebar row's fill from the sidebar's edge (NavigationView 4,
  /// `.navigation-sidebar` 6, a source list 8), and its content from the
  /// fill's edge (12, 8, 8): the icon lands 16, 14, 16 from the edge.
  final double navRowMargin;
  final double navRowPadding;

  /// Between a row's icon and its label (NavigationView's 40-wide icon
  /// column: 12; libadwaita's sidebar: 12; a source list: 8).
  final double navLabelGap;

  /// One level of nesting in the tree: 13 in a source list, 16 in a
  /// TreeView and a GTK tree expander.
  final double navIndent;

  /// A table or list row at the body size: Finder's list view (22, 24 on
  /// macOS 26), Explorer's details view (28), a GTK list (32).
  final double listRowHeight;

  /// A window's or dialog's content from its edge, and between groups of
  /// controls: 20 on macOS, 24 on Fluent and libadwaita.
  final double contentMargin;

  /// A list row's highlight from the list's edge: the inset, rounded
  /// selection of a sidebar, a pop-up list or a picker (an NSTableView's
  /// inset style), a ListView item's margin on Fluent (4), a GTK list's (6).
  final double rowInset;

  /// A table row's highlight from the table's edge, and with
  /// `AppSpacing.sm` its first cell's: [rowInset] unless the platform's
  /// tables reach their edges (Finder's list view up to macOS 15: the
  /// highlight spans the row, square).
  final double tableRowInset;

  /// The menu's plate to its items (NSMenu 5, MenuFlyout 2, a GTK popover
  /// menu 6), each item's margin inside it (Fluent: 2 by 2, so the items
  /// stand 4 from the plate's edge and 4 apart), and an item's label from
  /// its fill (9, 11, 12).
  final double menuInset;
  final EdgeInsets menuItemMargin;
  final double menuItemPadding;

  /// Above and below a menu separator's line: NSMenu's 11-high separator,
  /// Fluent's 1 px margins, libadwaita's 6.
  final double menuSeparatorSpace;

  /// Whether a menu item shows its symbol (`AppMenuAction.icon`): menus
  /// carry symbols on macOS 26, Windows and GNOME, not on macOS 15. A
  /// leading widget that says something (a tag's colour) always shows.
  final bool menuIcons;

  /// The check mark's column, which a menu keeps only while an item in it
  /// is checked (NSMenu since macOS 14): its width, the mark at its start,
  /// and how far it starts before an unchecked label would (on macOS 15
  /// the mark sits 6 in, the labels 20 in, 11 without one).
  final double menuCheckWidth;
  final double menuCheckPull;

  /// Between an item's symbol and its label (NSMenu: 7 after a 16-pt
  /// image in its 20-pt column, so 6 here).
  final double menuIconGap;

  /// A text field's text from its border, besides the 4 the outline keeps
  /// (NSTextField on macOS 15: 3 from a 1-pt bezel).
  final double fieldPadding;

  /// Whether a pop-up button ends in the accent's cap with its chevrons
  /// (NSPopUpButton on macOS 15) rather than in the bare chevrons.
  final bool popupCap;

  /// Whether a push button's, a pop-up's and a text field's bezel is
  /// darker along its bottom edge (`AppBezelBorder`), as AppKit draws them
  /// on macOS 15.
  final bool bezelShade;

  /// How much a sheet or an alert darkens the window behind it: macOS 15
  /// lays black at about 19 % (light) and 28 % (dark) over it.
  final double sheetDim;
  final double sheetDimDark;

  /// Least room between an item's label and its key: 24 (macOS, Fluent),
  /// 12 (libadwaita).
  final double menuShortcutGap;

  /// How far the pointer moves with the button down before a press
  /// becomes a drag: AppKit's and Windows' 4 (`SM_CXDRAG`), GTK's 8
  /// (`gtk-dnd-drag-threshold`). Shorter moves stay clicks.
  final double dragThreshold;

  /// [style] in the platform's monospace face: its family and fallbacks.
  TextStyle monospace(TextStyle style) => style.copyWith(
    fontFamily: typeScale.monoFamily,
    fontFamilyFallback: typeScale.monoFallback,
  );

  static final _macos = AppMetrics(
    style: AppPlatformStyle.macos,
    typeScale: AppTypography.of(AppPlatformStyle.macos),
    radius: const AppRadii(
      chip: 4,
      control: 6,
      row: 6,
      menu: 8,
      menuItem: 4,
      card: 8,
      popover: 10,
      dialog: 12,
      // Finder's list view and an NSTextField, measured on macOS 15.
      tableRow: 0,
      tableFrame: 0,
      field: 0,
    ),
    topBarHeight: 52,
    navItemHeight: 28,
    menuItemHeight: 22,
    controlHeight: 22,
    controlHeightSmall: 19,
    controlHeightLarge: 28,
    iconButtonSize: const Size(28, 24),
    toolbarSpacing: 8,
    focusRingWidth: 3,
    focusRingGap: 0,
    navSelection: AppNavSelection.tint,
    navHover: false,
    menuHighlightAccent: true,
    contentLayer: false,
    centeredBarTitle: false,
    // NSSwitch at the regular size, as System Settings draws a pane's
    // switch (drawn on macOS 15: 38 × 22, a 20 pt knob 1 pt in).
    toggleSize: const Size(38, 22),
    toggleKnob: 20,
    lengthUnit: AppLengthUnit.points,
    navIndent: 13,
    tableRowInset: 0,
    menuItemPadding: 9,
    menuSeparatorSpace: 5,
    menuShortcutGap: 24,
    menuIcons: false,
    menuCheckWidth: 15,
    menuCheckPull: 4,
    menuIconGap: 6,
    sheetDim: 0.19,
    sheetDimDark: 0.28,
    fieldPadding: 0,
    popupCap: true,
    bezelShade: true,
  );

  /// macOS 26 (Tahoe): the controls of System Settings measured on the
  /// system (2× screenshots, in points): push buttons 24 tall, the switch
  /// at the regular size 44 × 20 with a 26 × 16 pill for a knob, search
  /// fields capsules, list rows 32 with a selection rounded about 8,
  /// grouped boxes about 12.
  static final _macosTahoe = AppMetrics(
    style: AppPlatformStyle.macos,
    generation: MacGeneration.tahoe,
    typeScale: AppTypography.of(AppPlatformStyle.macos),
    radius: const AppRadii(
      chip: 6,
      control: 8,
      row: 8,
      menu: 12,
      menuItem: 6,
      card: 12,
      popover: 14,
      dialog: 16,
      search: AppRadius.full,
    ),
    topBarHeight: 52,
    navItemHeight: 32,
    menuItemHeight: 22,
    listRowHeight: 24,
    controlHeight: 24,
    controlHeightSmall: 20,
    controlHeightLarge: 32,
    iconButtonSize: const Size(32, 28),
    toolbarSpacing: 8,
    focusRingWidth: 3,
    focusRingGap: 0,
    navSelection: AppNavSelection.tint,
    navHover: false,
    menuHighlightAccent: true,
    contentLayer: false,
    centeredBarTitle: false,
    toggleSize: const Size(44, 20),
    toggleKnob: 16,
    toggleKnobWidth: 26,
    lengthUnit: AppLengthUnit.points,
    navIndent: 13,
    menuItemPadding: 9,
    menuSeparatorSpace: 5,
    menuShortcutGap: 24,
    menuCheckWidth: 15,
    menuCheckPull: 4,
    menuIconGap: 6,
    sheetDim: 0.19,
    sheetDimDark: 0.28,
    fieldPadding: 7,
  );

  static final _windows = AppMetrics(
    style: AppPlatformStyle.windows,
    typeScale: AppTypography.of(AppPlatformStyle.windows),
    radius: const AppRadii(
      chip: 4,
      control: 4,
      row: 4,
      menu: 8,
      menuItem: 4,
      card: 8,
      popover: 8,
      dialog: 8,
    ),
    topBarHeight: 48,
    navItemHeight: 36,
    // A mouse-opened MenuFlyout item: padding 11,4,11,5 around a 14 px
    // line; its margin keeps the next one 4 away.
    menuItemHeight: 28,
    controlHeight: 32,
    controlHeightSmall: 24,
    controlHeightLarge: 40,
    iconButtonSize: const Size(32, 32),
    toolbarSpacing: 4,
    focusRingWidth: 2,
    focusRingGap: 1,
    navSelection: AppNavSelection.indicator,
    navHover: true,
    menuHighlightAccent: false,
    contentLayer: true,
    centeredBarTitle: false,
    toggleSize: const Size(40, 20),
    toggleKnob: 14,
    lengthUnit: AppLengthUnit.pixels,
    navItemGap: 4,
    navRowMargin: 4,
    rowInset: 4,
    listRowHeight: 28,
    contentMargin: 24,
    navRowPadding: 12,
    navLabelGap: 12,
    menuInset: 2,
    menuItemMargin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
    menuItemPadding: 11,
    menuSeparatorSpace: 1,
    menuShortcutGap: 24,
  );

  static final _gnome = AppMetrics(
    style: AppPlatformStyle.gnome,
    typeScale: AppTypography.of(AppPlatformStyle.gnome),
    // libadwaita: buttons, entries, rows and menu items 9; cards 12;
    // popovers and dialogs 15; alerts 18 and their buttons 12.
    radius: const AppRadii(
      chip: 6,
      control: 9,
      row: 9,
      menu: 15,
      menuItem: 9,
      card: 12,
      popover: 15,
      dialog: 15,
      alert: 18,
      alertAction: 12,
    ),
    // The header bar: 46 and its 1 px shade.
    topBarHeight: 47,
    navItemHeight: 36,
    menuItemHeight: 32,
    controlHeight: 34,
    controlHeightSmall: 28,
    controlHeightLarge: 44,
    iconButtonSize: const Size(34, 34),
    toolbarSpacing: 6,
    focusRingWidth: 2,
    // Adwaita draws the ring inside the control (outline-offset −2).
    focusRingGap: -2,
    navSelection: AppNavSelection.fill,
    navHover: true,
    menuHighlightAccent: false,
    contentLayer: false,
    centeredBarTitle: true,
    toggleSize: const Size(46, 26),
    toggleKnob: 20,
    lengthUnit: AppLengthUnit.pixels,
    navItemGap: 2,
    navRowMargin: 6,
    rowInset: 6,
    listRowHeight: 32,
    contentMargin: 24,
    navRowPadding: 8,
    navLabelGap: 12,
    menuInset: 6,
    menuItemPadding: 12,
    menuSeparatorSpace: 6,
    menuShortcutGap: 12,
    dragThreshold: 8,
  );

  /// Metrics are fixed per style; a theme for another style is a new
  /// theme, not a copy.
  @override
  AppMetrics copyWith() => this;

  /// Nothing to blend between styles: the light and dark themes of one
  /// style share the same metrics.
  @override
  AppMetrics lerp(AppMetrics? other, double t) =>
      other == null || t < 0.5 ? this : other;
}
