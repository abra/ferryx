import 'generated/ferryx_localizations.dart';

/// Finder tags in words.
extension TagLabels on FerryxLocalizations {
  /// The name of Finder's standard tag of [color] (its number: 1 grey,
  /// 2 green, 3 purple, 4 blue, 5 yellow, 6 red, 7 orange), as Finder
  /// names it in this language.
  String tagColorName(int color) => switch (color) {
    1 => tagColorGray,
    2 => tagColorGreen,
    3 => tagColorPurple,
    4 => tagColorBlue,
    5 => tagColorYellow,
    6 => tagColorRed,
    7 => tagColorOrange,
    _ => tagsColorNone,
  };

  /// [names] as one list.
  String tagNames(Iterable<String> names) =>
      names.isEmpty ? '' : names.reduce(tagsList);
}
