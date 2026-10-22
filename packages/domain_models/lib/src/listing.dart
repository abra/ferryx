import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import 'file_entry.dart';
import 'location.dart';

/// What a panel sorts by. Each field has the order it is first shown in:
/// names and extensions ascend, sizes and times descend.
enum SortField {
  name('n'),
  extension('e'),
  size('s'),
  modified('m'),
  created('b'),
  added('a'),
  accessed('x');

  const SortField(this.letter);

  /// The letter of the panel's sort indicator; upper case when the order
  /// is reversed from the field's default.
  final String letter;

  bool get defaultDescending => this != name && this != extension;
}

enum Collation { natural, caseInsensitive, caseSensitive }

@immutable
class SortOptions extends Equatable {
  const SortOptions({
    this.field = SortField.name,
    this.descending = false,
    this.foldersFirst = true,
    this.extensionlessFolders = true,
    this.collation = Collation.natural,
  });

  final SortField field;
  final bool descending;

  /// Every folder before any file, whatever the field.
  final bool foldersFirst;

  /// Sorting by extension treats folders as having none.
  final bool extensionlessFolders;
  final Collation collation;

  /// The indicator in the panel's corner: the field's letter, upper case
  /// when the order is not the field's own.
  String get indicator => descending == field.defaultDescending
      ? field.letter
      : field.letter.toUpperCase();

  /// After the user picks [field]: the field's own order when it changes,
  /// the opposite order when it is picked again.
  SortOptions toggled(SortField field) => this.field == field
      ? copyWith(descending: !descending)
      : copyWith(field: field, descending: field.defaultDescending);

  SortOptions copyWith({
    SortField? field,
    bool? descending,
    bool? foldersFirst,
    bool? extensionlessFolders,
    Collation? collation,
  }) => SortOptions(
    field: field ?? this.field,
    descending: descending ?? this.descending,
    foldersFirst: foldersFirst ?? this.foldersFirst,
    extensionlessFolders: extensionlessFolders ?? this.extensionlessFolders,
    collation: collation ?? this.collation,
  );

  Map<String, Object?> toJson() => {
    'field': field.name,
    'descending': descending,
    'foldersFirst': foldersFirst,
    'extensionlessFolders': extensionlessFolders,
    'collation': collation.name,
  };

  factory SortOptions.fromJson(Map<String, Object?> json) {
    const defaults = SortOptions();
    return SortOptions(
      field:
          SortField.values.where((f) => f.name == json['field']).firstOrNull ??
          defaults.field,
      descending: json['descending'] is bool
          ? json['descending']! as bool
          : defaults.descending,
      foldersFirst: json['foldersFirst'] is bool
          ? json['foldersFirst']! as bool
          : defaults.foldersFirst,
      extensionlessFolders: json['extensionlessFolders'] is bool
          ? json['extensionlessFolders']! as bool
          : defaults.extensionlessFolders,
      collation:
          Collation.values
              .where((c) => c.name == json['collation'])
              .firstOrNull ??
          defaults.collation,
    );
  }

  @override
  List<Object?> get props => [
    field,
    descending,
    foldersFirst,
    extensionlessFolders,
    collation,
  ];
}

@immutable
class ListingOptions extends Equatable {
  const ListingOptions({
    this.showHidden = false,
    this.showParent = true,
    this.sort = const SortOptions(),
  });

  final bool showHidden;

  /// The `..` row, when the folder has a parent.
  final bool showParent;
  final SortOptions sort;

  ListingOptions copyWith({
    bool? showHidden,
    bool? showParent,
    SortOptions? sort,
  }) => ListingOptions(
    showHidden: showHidden ?? this.showHidden,
    showParent: showParent ?? this.showParent,
    sort: sort ?? this.sort,
  );

  @override
  List<Object?> get props => [showHidden, showParent, sort];
}

/// A panel's rows, sorted, with what the footer shows.
@immutable
class Listing extends Equatable {
  const Listing({
    required this.location,
    required this.entries,
    this.freeBytes,
    this.totalBytes,
    this.volumeName,
    this.watched = false,
  });

  final Location location;
  final List<FileEntry> entries;
  final int? freeBytes;
  final int? totalBytes;
  final String? volumeName;

  /// Whether the folder is watched for changes; an archive is not.
  final bool watched;

  /// The rows without the `..` one.
  Iterable<FileEntry> get items => entries.where((e) => !e.isParent);

  int indexOfName(String name) => entries.indexWhere((e) => e.name == name);

  Listing copyWith({List<FileEntry>? entries}) => Listing(
    location: location,
    entries: entries ?? this.entries,
    freeBytes: freeBytes,
    totalBytes: totalBytes,
    volumeName: volumeName,
    watched: watched,
  );

  @override
  List<Object?> get props => [
    location,
    entries,
    freeBytes,
    totalBytes,
    volumeName,
    watched,
  ];
}
