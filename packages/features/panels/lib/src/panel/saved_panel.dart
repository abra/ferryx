import 'dart:convert';

import 'package:domain_models/domain_models.dart';

/// What a panel keeps between runs: its tabs' locations, sort and layout,
/// the tab shown, the tabs closed lately.
class SavedPanel {
  const SavedPanel({
    required this.tabs,
    this.activeIndex = 0,
    this.closedTabs = const [],
  });

  final List<SavedTab> tabs;
  final int activeIndex;
  final List<Location> closedTabs;

  String encode() => jsonEncode({
    'tabs': [for (final t in tabs) t.toJson()],
    'active': activeIndex,
    'closed': [for (final c in closedTabs) c.encode()],
  });

  static SavedPanel? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return null;
      final tabs = <SavedTab>[];
      if (json['tabs'] case final List<Object?> items) {
        for (final item in items) {
          if (item is Map<String, Object?>) {
            final tab = SavedTab.fromJson(item);
            if (tab != null) tabs.add(tab);
          }
        }
      }
      if (tabs.isEmpty) return null;
      final active = json['active'];
      final closed = <Location>[];
      if (json['closed'] case final List<Object?> items) {
        for (final item in items) {
          if (item is String) {
            final location = Location.decode(item);
            if (location != null) closed.add(location);
          }
        }
      }
      return SavedPanel(
        tabs: tabs,
        activeIndex: active is int ? active.clamp(0, tabs.length - 1) : 0,
        closedTabs: closed,
      );
    } on FormatException {
      return null;
    }
  }
}

class SavedTab {
  const SavedTab({
    required this.location,
    this.sort = const SortOptions(),
    this.layoutIndex = 0,
  });

  final Location location;
  final SortOptions sort;
  final int layoutIndex;

  Map<String, Object?> toJson() => {
    'location': location.encode(),
    'sort': sort.toJson(),
    'layout': layoutIndex,
  };

  static SavedTab? fromJson(Map<String, Object?> json) {
    final encoded = json['location'];
    if (encoded is! String) return null;
    final location = Location.decode(encoded);
    if (location == null) return null;
    final layout = json['layout'];
    return SavedTab(
      location: location,
      sort: json['sort'] is Map<String, Object?>
          ? SortOptions.fromJson(json['sort']! as Map<String, Object?>)
          : const SortOptions(),
      layoutIndex: layout is int ? layout : 0,
    );
  }
}
