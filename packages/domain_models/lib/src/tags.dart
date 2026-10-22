import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import 'exceptions.dart';

/// A Finder tag: its name and its colour in Finder's numbering (0 none,
/// 1 grey, 2 green, 3 purple, 4 blue, 5 yellow, 6 red, 7 orange).
@immutable
class FileTag extends Equatable {
  const FileTag(this.name, {this.color = 0});

  final String name;
  final int color;

  /// The names an English Finder gives its standard tags, by colour: a
  /// tag of these names is that colour's standard tag whatever the
  /// language the interface speaks (Finder writes its own language's).
  static const finderNames = {
    1: 'Gray',
    2: 'Green',
    3: 'Purple',
    4: 'Blue',
    5: 'Yellow',
    6: 'Red',
    7: 'Orange',
  };

  bool sameName(String other) => name.toLowerCase() == other.toLowerCase();

  /// Whether this is the standard tag of [color], named [localName] in
  /// the interface's language or by an English Finder.
  bool isStandard(int color, String localName) =>
      this.color == color &&
      (sameName(localName) || sameName(finderNames[color] ?? ''));

  @override
  List<Object?> get props => [name, color];
}

/// What a tag edit did to one item: its tags after, or why it could not
/// be changed.
@immutable
class TagOutcome extends Equatable {
  const TagOutcome({
    required this.path,
    this.tags = const [],
    this.failure,
  });

  final String path;
  final List<FileTag> tags;
  final FerryxException? failure;

  @override
  List<Object?> get props => [path, tags, failure?.kind, failure?.message];
}

/// What this desktop can do that others cannot; the interface hides what
/// it lacks.
@immutable
class Capabilities extends Equatable {
  const Capabilities({this.finderTags = false, this.spotlight = false});

  /// Finder tags are read and written (macOS).
  final bool finderTags;

  /// Find Files can ask the Spotlight index (macOS).
  final bool spotlight;

  @override
  List<Object?> get props => [finderTags, spotlight];
}
