import 'package:domain_models/domain_models.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import 'terminal_preferences.dart';
import 'compare_options.dart';

enum AppThemeMode { system, light, dark }

/// Immutable snapshot of the installation's preferences.
@immutable
class Preferences extends Equatable {
  const Preferences({
    this.themeMode = AppThemeMode.system,
    this.localeCode,
    this.textScale = 1.0,
    this.shortcutOverrides = const {},
    this.windowBounds,
    this.windowMaximized = false,
    this.splitFraction = 0.5,
    this.singlePane = false,
    this.panelArrangement = PanelArrangement.byWindowShape,
    this.panelState = const {},
    this.layouts = PanelLayout.defaults,
    this.showHiddenFiles = false,
    this.showParentEntry = true,
    this.foldersFirst = true,
    this.extensionlessFolders = true,
    this.collation = Collation.natural,
    this.quickSearchWhere = QuickSearchWhere.anywhere,
    this.quickSearchModifier = QuickSearchModifier.none,
    this.quickSearchOnlyMatching = false,
    this.favorites = const [],
    this.editors = const [],
    this.tools = const [],
    this.confirmTrash = false,
    this.confirmDelete = true,
    this.verifyCopies = false,
    this.preserveAttributes = true,
    this.viewerWrap = true,
    this.viewerFontSize = 13,
    this.showTabBarAlways = false,
    this.showKeyHints = true,
    this.operationsVisible = true,
    this.vimMode = false,
    this.vimMarks = const {},
    this.terminal = const TerminalPreferences(),
    this.compareOptions = const CompareOptions(),
    this.servers = const [],
  });

  static const int schemaVersion = 1;

  final AppThemeMode themeMode;

  /// `null` follows the system locale.
  final String? localeCode;

  /// Multiplier on the interface's text size (0.8–1.6).
  final double textScale;

  /// Command name → encoded chords; see `ChordCodec` in the shortcuts package.
  final Map<String, List<String>> shortcutOverrides;

  /// Last window frame (logical pixels) and whether it was maximised.
  final WindowBounds? windowBounds;
  final bool windowMaximized;

  /// The left panel's share of the window.
  final double splitFraction;
  final bool singlePane;
  final PanelArrangement panelArrangement;

  /// Each panel's tabs, their locations, sort and layout, as the panels
  /// write them (opaque here), by panel id (`left`, `right`, `active`).
  final Map<String, String> panelState;

  /// The layouts Ctrl+1… switch between.
  final List<PanelLayout> layouts;
  final bool showHiddenFiles;

  /// The `..` row at the top of a listing.
  final bool showParentEntry;
  final bool foldersFirst;
  final bool extensionlessFolders;
  final Collation collation;
  final QuickSearchWhere quickSearchWhere;
  final QuickSearchModifier quickSearchModifier;

  /// Quick Search hides the rows that do not match, instead of only
  /// underlining the ones that do.
  final bool quickSearchOnlyMatching;
  final List<Favorite> favorites;
  final List<ExternalEditor> editors;
  final List<ExternalTool> tools;
  final bool confirmTrash;
  final bool confirmDelete;
  final bool verifyCopies;
  final bool preserveAttributes;
  final bool viewerWrap;
  final double viewerFontSize;
  final bool showTabBarAlways;

  /// A line under the panels with the keys for what is under the cursor
  /// or selected.
  final bool showKeyHints;

  /// The operations strip stays shown while operations run.
  final bool operationsVisible;

  /// Vim keys in the panels: `h j k l`, counts, `/` to search, `v` to
  /// select, `yy` `dd` `p`, marks and the `:` command line.
  final bool vimMode;

  /// Vim marks: a letter to an encoded `Location`, set with `m`.
  final Map<String, String> vimMarks;

  /// The integrated terminal: its settings and its height under the panels.
  final TerminalPreferences terminal;

  /// Compare Folders and Synchronize Folders, as last used.
  final CompareOptions compareOptions;

  // ─── Network ───

  /// The servers the user saved for Connect to Server, in the order they
  /// keep them; never a password (only the system's keychain keeps those).
  final List<ServerProfile> servers;

  /// The sort options a new panel starts with.
  SortOptions get defaultSort => SortOptions(
    foldersFirst: foldersFirst,
    extensionlessFolders: extensionlessFolders,
    collation: collation,
  );

  Preferences copyWith({
    AppThemeMode? themeMode,
    String? localeCode,
    bool clearLocale = false,
    double? textScale,
    Map<String, List<String>>? shortcutOverrides,
    WindowBounds? windowBounds,
    bool? windowMaximized,
    double? splitFraction,
    bool? singlePane,
    PanelArrangement? panelArrangement,
    Map<String, String>? panelState,
    List<PanelLayout>? layouts,
    bool? showHiddenFiles,
    bool? showParentEntry,
    bool? foldersFirst,
    bool? extensionlessFolders,
    Collation? collation,
    QuickSearchWhere? quickSearchWhere,
    QuickSearchModifier? quickSearchModifier,
    bool? quickSearchOnlyMatching,
    List<Favorite>? favorites,
    List<ExternalEditor>? editors,
    List<ExternalTool>? tools,
    bool? confirmTrash,
    bool? confirmDelete,
    bool? verifyCopies,
    bool? preserveAttributes,
    bool? viewerWrap,
    double? viewerFontSize,
    bool? showTabBarAlways,
    bool? showKeyHints,
    bool? operationsVisible,
    bool? vimMode,
    Map<String, String>? vimMarks,
    TerminalPreferences? terminal,
    CompareOptions? compareOptions,
    List<ServerProfile>? servers,
  }) => Preferences(
    themeMode: themeMode ?? this.themeMode,
    localeCode: clearLocale ? null : (localeCode ?? this.localeCode),
    textScale: textScale ?? this.textScale,
    shortcutOverrides: shortcutOverrides ?? this.shortcutOverrides,
    windowBounds: windowBounds ?? this.windowBounds,
    windowMaximized: windowMaximized ?? this.windowMaximized,
    splitFraction: splitFraction ?? this.splitFraction,
    singlePane: singlePane ?? this.singlePane,
    panelArrangement: panelArrangement ?? this.panelArrangement,
    panelState: panelState ?? this.panelState,
    layouts: layouts ?? this.layouts,
    showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
    showParentEntry: showParentEntry ?? this.showParentEntry,
    foldersFirst: foldersFirst ?? this.foldersFirst,
    extensionlessFolders: extensionlessFolders ?? this.extensionlessFolders,
    collation: collation ?? this.collation,
    quickSearchWhere: quickSearchWhere ?? this.quickSearchWhere,
    quickSearchModifier: quickSearchModifier ?? this.quickSearchModifier,
    quickSearchOnlyMatching:
        quickSearchOnlyMatching ?? this.quickSearchOnlyMatching,
    favorites: favorites ?? this.favorites,
    editors: editors ?? this.editors,
    tools: tools ?? this.tools,
    confirmTrash: confirmTrash ?? this.confirmTrash,
    confirmDelete: confirmDelete ?? this.confirmDelete,
    verifyCopies: verifyCopies ?? this.verifyCopies,
    preserveAttributes: preserveAttributes ?? this.preserveAttributes,
    viewerWrap: viewerWrap ?? this.viewerWrap,
    viewerFontSize: viewerFontSize ?? this.viewerFontSize,
    showTabBarAlways: showTabBarAlways ?? this.showTabBarAlways,
    showKeyHints: showKeyHints ?? this.showKeyHints,
    operationsVisible: operationsVisible ?? this.operationsVisible,
    vimMode: vimMode ?? this.vimMode,
    vimMarks: vimMarks ?? this.vimMarks,
    terminal: terminal ?? this.terminal,
    compareOptions: compareOptions ?? this.compareOptions,
    servers: servers ?? this.servers,
  );

  Map<String, Object?> toJson() => {
    'version': schemaVersion,
    'themeMode': themeMode.name,
    'localeCode': localeCode,
    'textScale': textScale,
    'shortcutOverrides': shortcutOverrides,
    'windowBounds': windowBounds?.toJson(),
    'windowMaximized': windowMaximized,
    'splitFraction': splitFraction,
    'singlePane': singlePane,
    'panelArrangement': panelArrangement.name,
    'panelState': panelState,
    'layouts': [for (final l in layouts) l.toJson()],
    'showHiddenFiles': showHiddenFiles,
    'showParentEntry': showParentEntry,
    'foldersFirst': foldersFirst,
    'extensionlessFolders': extensionlessFolders,
    'collation': collation.name,
    'quickSearchWhere': quickSearchWhere.name,
    'quickSearchModifier': quickSearchModifier.name,
    'quickSearchOnlyMatching': quickSearchOnlyMatching,
    'favorites': [for (final f in favorites) f.toJson()],
    'editors': [for (final e in editors) e.toJson()],
    'tools': [for (final t in tools) t.toJson()],
    'confirmTrash': confirmTrash,
    'confirmDelete': confirmDelete,
    'verifyCopies': verifyCopies,
    'preserveAttributes': preserveAttributes,
    'viewerWrap': viewerWrap,
    'viewerFontSize': viewerFontSize,
    'showTabBarAlways': showTabBarAlways,
    'showKeyHints': showKeyHints,
    'operationsVisible': operationsVisible,
    'vimMode': vimMode,
    'vimMarks': vimMarks,
    'terminal': terminal.toJson(),
    'compareOptions': compareOptions.toJson(),
    'servers': [for (final s in servers) s.toJson()],
  };

  /// Tolerant decoding: unknown or malformed fields fall back to defaults so
  /// a newer or damaged file never blocks startup.
  factory Preferences.fromJson(Map<String, Object?> json) {
    const defaults = Preferences();
    final overrides = <String, List<String>>{};
    if (json['shortcutOverrides'] case final Map<String, Object?> raw) {
      for (final entry in raw.entries) {
        if (entry.value case final List<Object?> chords) {
          overrides[entry.key] = chords.whereType<String>().toList(
            growable: false,
          );
        }
      }
    }
    List<T> items<T>(Object? raw, T? Function(Map<String, Object?>) parse) =>
        raw is List
        ? List.unmodifiable([
            for (final item in raw)
              if (item is Map<String, Object?>) ?parse(item),
          ])
        : const [];
    final layouts = items(json['layouts'], PanelLayout.fromJson);
    return Preferences(
      themeMode:
          _enumByName(AppThemeMode.values, json['themeMode']) ??
          defaults.themeMode,
      localeCode: json['localeCode'] is String
          ? json['localeCode'] as String
          : null,
      textScale: _doubleOr(
        json['textScale'],
        defaults.textScale,
      ).clamp(0.8, 1.6),
      shortcutOverrides: Map.unmodifiable(overrides),
      windowBounds: json['windowBounds'] is Map<String, Object?>
          ? WindowBounds.fromJson(json['windowBounds'] as Map<String, Object?>)
          : null,
      windowMaximized: _boolOr(
        json['windowMaximized'],
        defaults.windowMaximized,
      ),
      splitFraction: _doubleOr(
        json['splitFraction'],
        defaults.splitFraction,
      ).clamp(0.1, 0.9),
      singlePane: _boolOr(json['singlePane'], defaults.singlePane),
      panelArrangement:
          _enumByName(PanelArrangement.values, json['panelArrangement']) ??
          defaults.panelArrangement,
      panelState: json['panelState'] is Map<String, Object?>
          ? Map.unmodifiable({
              for (final entry
                  in (json['panelState'] as Map<String, Object?>).entries)
                if (entry.value case final String state) entry.key: state,
            })
          : defaults.panelState,
      layouts: layouts.isEmpty ? defaults.layouts : layouts,
      showHiddenFiles: _boolOr(
        json['showHiddenFiles'],
        defaults.showHiddenFiles,
      ),
      showParentEntry: _boolOr(
        json['showParentEntry'],
        defaults.showParentEntry,
      ),
      foldersFirst: _boolOr(json['foldersFirst'], defaults.foldersFirst),
      extensionlessFolders: _boolOr(
        json['extensionlessFolders'],
        defaults.extensionlessFolders,
      ),
      collation:
          _enumByName(Collation.values, json['collation']) ??
          defaults.collation,
      quickSearchWhere:
          _enumByName(QuickSearchWhere.values, json['quickSearchWhere']) ??
          defaults.quickSearchWhere,
      quickSearchModifier:
          _enumByName(
            QuickSearchModifier.values,
            json['quickSearchModifier'],
          ) ??
          defaults.quickSearchModifier,
      quickSearchOnlyMatching: _boolOr(
        json['quickSearchOnlyMatching'],
        defaults.quickSearchOnlyMatching,
      ),
      favorites: items(json['favorites'], Favorite.fromJson),
      editors: items(json['editors'], ExternalEditor.fromJson),
      tools: items(json['tools'], ExternalTool.fromJson),
      confirmTrash: _boolOr(json['confirmTrash'], defaults.confirmTrash),
      confirmDelete: _boolOr(json['confirmDelete'], defaults.confirmDelete),
      verifyCopies: _boolOr(json['verifyCopies'], defaults.verifyCopies),
      preserveAttributes: _boolOr(
        json['preserveAttributes'],
        defaults.preserveAttributes,
      ),
      viewerWrap: _boolOr(json['viewerWrap'], defaults.viewerWrap),
      viewerFontSize: _doubleOr(
        json['viewerFontSize'],
        defaults.viewerFontSize,
      ).clamp(9, 32),
      showTabBarAlways: _boolOr(
        json['showTabBarAlways'],
        defaults.showTabBarAlways,
      ),
      showKeyHints: _boolOr(json['showKeyHints'], defaults.showKeyHints),
      operationsVisible: _boolOr(
        json['operationsVisible'],
        defaults.operationsVisible,
      ),
      vimMode: _boolOr(json['vimMode'], defaults.vimMode),
      vimMarks: json['vimMarks'] is Map<String, Object?>
          ? Map.unmodifiable({
              for (final entry
                  in (json['vimMarks'] as Map<String, Object?>).entries)
                if (entry.value case final String location) entry.key: location,
            })
          : defaults.vimMarks,
      terminal: TerminalPreferences.fromJson(json['terminal']),
      compareOptions: CompareOptions.fromJson(json['compareOptions']),
      servers: json['servers'] is List
          ? [
              for (final item in json['servers'] as List)
                ?ServerProfile.fromJson(item),
            ]
          : defaults.servers,
    );
  }

  static T? _enumByName<T extends Enum>(List<T> values, Object? name) {
    if (name is! String) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static double _doubleOr(Object? value, double fallback) =>
      value is num ? value.toDouble() : fallback;

  static bool _boolOr(Object? value, bool fallback) =>
      value is bool ? value : fallback;

  @override
  List<Object?> get props => [
    themeMode,
    localeCode,
    textScale,
    shortcutOverrides,
    windowBounds,
    windowMaximized,
    splitFraction,
    singlePane,
    panelArrangement,
    panelState,
    layouts,
    showHiddenFiles,
    showParentEntry,
    foldersFirst,
    extensionlessFolders,
    collation,
    quickSearchWhere,
    quickSearchModifier,
    quickSearchOnlyMatching,
    favorites,
    editors,
    tools,
    confirmTrash,
    confirmDelete,
    verifyCopies,
    preserveAttributes,
    viewerWrap,
    viewerFontSize,
    showTabBarAlways,
    showKeyHints,
    operationsVisible,
    vimMode,
    vimMarks,
    terminal,
    compareOptions,
    servers,
  ];
}

/// A window frame in logical pixels.
@immutable
class WindowBounds extends Equatable {
  const WindowBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, Object?> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  /// `null` when any side is missing or not a number.
  static WindowBounds? fromJson(Map<String, Object?> json) {
    final values = [json['x'], json['y'], json['width'], json['height']];
    if (values.any((v) => v is! num)) return null;
    final [x, y, width, height] = values
        .map((v) => (v! as num).toDouble())
        .toList();
    if (width <= 0 || height <= 0) return null;
    return WindowBounds(x: x, y: y, width: width, height: height);
  }

  @override
  List<Object?> get props => [x, y, width, height];
}
