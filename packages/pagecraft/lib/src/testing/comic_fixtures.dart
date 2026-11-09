import 'dart:typed_data';

import 'png_writer.dart';
import 'zip_builder.dart';

/// A page to put in a fixture comic: its archive name and pixel size.
typedef FixturePage = ({String name, int width, int height});

/// Portrait pages at a phone-like ratio, named like a typical scan.
List<FixturePage> portraitPages(int count, {String folder = ''}) => [
  for (var i = 1; i <= count; i++)
    (
      name: '$folder${i.toString().padLeft(3, '0')}.png',
      width: 600,
      height: 900,
    ),
];

/// Builds a CBZ with the given pages (PNG, solid colour), optionally with
/// the junk a macOS archive carries, in a deterministic byte layout.
Uint8List buildComicArchive(
  List<FixturePage> pages, {
  bool withMacOsJunk = false,
  bool deflate = false,
  List<String> extraEntries = const [],
}) {
  final builder = ZipBuilder();
  for (final (index, page) in pages.indexed) {
    builder.add(
      page.name,
      encodeSolidPng(page.width, page.height, rgba: 0x10203040 + index),
      deflate: deflate,
      utf8Flag: true,
    );
  }
  if (withMacOsJunk) {
    for (final page in pages) {
      builder.add('__MACOSX/._${page.name}', const [
        0,
        5,
        22,
        7,
      ], utf8Flag: true);
    }
    builder.add('.DS_Store', const [0, 0, 0, 1], utf8Flag: true);
  }
  for (final name in extraEntries) {
    builder.add(name, const [1, 2, 3], utf8Flag: true);
  }
  return builder.build();
}
