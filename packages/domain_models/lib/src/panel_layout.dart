import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// How a panel lays its rows out.
enum ViewMode {
  /// Names in columns, as many as fit; the cursor moves in both directions.
  brief,

  /// One row per item with columns of attributes.
  list,
}

/// A column of the list mode.
enum ListColumn {
  name,
  extension,
  size,
  modified,
  created,
  added,
  accessed,
  permissions,
  owner,
  group,
}

/// How brief mode sizes its columns.
enum BriefColumns {
  /// Three equal columns.
  fixed,

  /// As wide as the longest name in each.
  dynamic,
}

/// One of the panel layouts the view-mode keys switch between (Ctrl+1…).
@immutable
class PanelLayout extends Equatable {
  const PanelLayout({
    required this.name,
    required this.mode,
    this.briefColumns = BriefColumns.fixed,
    this.columns = const [
      ListColumn.name,
      ListColumn.size,
      ListColumn.modified,
    ],
    this.iconSize = IconSize.small,
  });

  final String name;
  final ViewMode mode;
  final BriefColumns briefColumns;
  final List<ListColumn> columns;
  final IconSize iconSize;

  /// The five presets the app starts with.
  static const List<PanelLayout> defaults = [
    PanelLayout(name: 'Short', mode: ViewMode.brief),
    PanelLayout(
      name: 'Medium',
      mode: ViewMode.brief,
      briefColumns: BriefColumns.dynamic,
    ),
    PanelLayout(
      name: 'Full',
      mode: ViewMode.list,
      columns: [
        ListColumn.name,
        ListColumn.size,
        ListColumn.created,
        ListColumn.modified,
        ListColumn.added,
      ],
    ),
    PanelLayout(
      name: 'Wide',
      mode: ViewMode.list,
      columns: [ListColumn.name, ListColumn.size],
    ),
    PanelLayout(
      name: 'Details',
      mode: ViewMode.list,
      columns: [
        ListColumn.name,
        ListColumn.size,
        ListColumn.modified,
        ListColumn.permissions,
        ListColumn.owner,
      ],
    ),
  ];

  Map<String, Object?> toJson() => {
    'name': name,
    'mode': mode.name,
    'briefColumns': briefColumns.name,
    'columns': [for (final c in columns) c.name],
    'iconSize': iconSize.name,
  };

  static PanelLayout? fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final mode = ViewMode.values
        .where((m) => m.name == json['mode'])
        .firstOrNull;
    if (name is! String || mode == null) return null;
    final columns = [
      if (json['columns'] case final List<Object?> raw)
        for (final c in raw)
          ...ListColumn.values.where((column) => column.name == c),
    ];
    return PanelLayout(
      name: name,
      mode: mode,
      briefColumns:
          BriefColumns.values
              .where((b) => b.name == json['briefColumns'])
              .firstOrNull ??
          BriefColumns.fixed,
      columns: columns.isEmpty ? const [ListColumn.name] : columns,
      iconSize:
          IconSize.values
              .where((s) => s.name == json['iconSize'])
              .firstOrNull ??
          IconSize.small,
    );
  }

  @override
  List<Object?> get props => [name, mode, briefColumns, columns, iconSize];
}

enum IconSize { none, small, large }

/// Where Quick Search looks for the typed letters.
enum QuickSearchWhere { fuzzy, anywhere, beginning, ending, beginningOrEnding }

/// The modifier Quick Search wants held, or none, or off.
enum QuickSearchModifier { none, alt, controlAlt, shiftAlt, disabled }
