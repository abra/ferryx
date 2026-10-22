import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// Which way Synchronize Folders makes the folders alike.
enum SyncDirection {
  /// Each side takes what the other has newer or alone.
  bothWays,

  /// The right folder becomes like the left one.
  leftToRight,

  /// The left folder becomes like the right one.
  rightToLeft,
}

/// Compare Folders and Synchronize Folders, as last used: the dialog's
/// options and which rows it shows.
@immutable
class CompareOptions extends Equatable {
  const CompareOptions({
    this.quickContents = false,
    this.recursive = true,
    this.byContent = false,
    this.fatTime = false,
    this.includeHidden = false,
    this.direction = SyncDirection.bothWays,
    this.deleteMissing = false,
    this.showLeftOnly = true,
    this.showRightOnly = true,
    this.showNewer = true,
    this.showDifferent = true,
    this.showIdentical = false,
  });

  /// Compare Folders (the panels' command) also compares the contents of
  /// files of one size.
  final bool quickContents;
  final bool recursive;
  final bool byContent;

  /// Times two seconds apart count as the same (FAT, exFAT).
  final bool fatTime;
  final bool includeHidden;
  final SyncDirection direction;

  /// One way only: what the source lacks is deleted on the other side.
  final bool deleteMissing;
  final bool showLeftOnly;
  final bool showRightOnly;
  final bool showNewer;
  final bool showDifferent;
  final bool showIdentical;

  CompareOptions copyWith({
    bool? quickContents,
    bool? recursive,
    bool? byContent,
    bool? fatTime,
    bool? includeHidden,
    SyncDirection? direction,
    bool? deleteMissing,
    bool? showLeftOnly,
    bool? showRightOnly,
    bool? showNewer,
    bool? showDifferent,
    bool? showIdentical,
  }) => CompareOptions(
    quickContents: quickContents ?? this.quickContents,
    recursive: recursive ?? this.recursive,
    byContent: byContent ?? this.byContent,
    fatTime: fatTime ?? this.fatTime,
    includeHidden: includeHidden ?? this.includeHidden,
    direction: direction ?? this.direction,
    deleteMissing: deleteMissing ?? this.deleteMissing,
    showLeftOnly: showLeftOnly ?? this.showLeftOnly,
    showRightOnly: showRightOnly ?? this.showRightOnly,
    showNewer: showNewer ?? this.showNewer,
    showDifferent: showDifferent ?? this.showDifferent,
    showIdentical: showIdentical ?? this.showIdentical,
  );

  Map<String, Object?> toJson() => {
    'quickContents': quickContents,
    'recursive': recursive,
    'byContent': byContent,
    'fatTime': fatTime,
    'includeHidden': includeHidden,
    'direction': direction.name,
    'deleteMissing': deleteMissing,
    'showLeftOnly': showLeftOnly,
    'showRightOnly': showRightOnly,
    'showNewer': showNewer,
    'showDifferent': showDifferent,
    'showIdentical': showIdentical,
  };

  /// Tolerant: a missing or malformed field keeps its default.
  factory CompareOptions.fromJson(Object? raw) {
    const defaults = CompareOptions();
    if (raw is! Map<String, Object?>) return defaults;
    bool flag(String key, bool fallback) =>
        raw[key] is bool ? raw[key]! as bool : fallback;
    return CompareOptions(
      quickContents: flag('quickContents', defaults.quickContents),
      recursive: flag('recursive', defaults.recursive),
      byContent: flag('byContent', defaults.byContent),
      fatTime: flag('fatTime', defaults.fatTime),
      includeHidden: flag('includeHidden', defaults.includeHidden),
      direction: SyncDirection.values.firstWhere(
        (d) => d.name == raw['direction'],
        orElse: () => defaults.direction,
      ),
      deleteMissing: flag('deleteMissing', defaults.deleteMissing),
      showLeftOnly: flag('showLeftOnly', defaults.showLeftOnly),
      showRightOnly: flag('showRightOnly', defaults.showRightOnly),
      showNewer: flag('showNewer', defaults.showNewer),
      showDifferent: flag('showDifferent', defaults.showDifferent),
      showIdentical: flag('showIdentical', defaults.showIdentical),
    );
  }

  @override
  List<Object?> get props => [
    quickContents,
    recursive,
    byContent,
    fatTime,
    includeHidden,
    direction,
    deleteMissing,
    showLeftOnly,
    showRightOnly,
    showNewer,
    showDifferent,
    showIdentical,
  ];
}
