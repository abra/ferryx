/// INDX records: the tag-indexed tables MOBI uses for the NCX, KF8
/// skeletons, fragments and guide (`getIndexData`, `getNCX`).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../text/charsets.dart';
import 'mobi_compression.dart';
import 'mobi_headers.dart';

/// One entry of an index: its name and the values of each tag.
@immutable
class MobiIndexEntry {
  const MobiIndexEntry({required this.name, required this.tags});

  final String name;

  /// Tag number to its values.
  final Map<int, List<int>> tags;

  /// The first value of [tag], or null.
  int? first(int tag) {
    final values = tags[tag];
    return values == null || values.isEmpty ? null : values.first;
  }
}

/// An index with its CNCX strings (labels), keyed by offset.
@immutable
class MobiIndex {
  const MobiIndex({required this.entries, required this.cncx});

  final List<MobiIndexEntry> entries;
  final Map<int, String> cncx;
}

/// Reads the index whose primary record is [indxIndex].
Future<MobiIndex> readMobiIndex(
  int indxIndex,
  Future<Uint8List> Function(int index) loadRecord,
) async {
  final indx = MobiBytes(await loadRecord(indxIndex));
  if (indx.ascii(0, 4) != 'INDX') {
    throw const FormatException('Invalid INDX record');
  }
  final headerLength = indx.u32(4);
  final numRecords = indx.u32(24);
  final charset = mobiCharset(indx.u32(28));
  final numCncx = indx.u32(52);

  final tagx = MobiBytes(indx.slice(headerLength));
  if (tagx.ascii(0, 4) != 'TAGX') {
    throw const FormatException('Invalid TAGX section');
  }
  final tagxLength = tagx.u32(4);
  final numControlBytes = tagx.u32(8);
  final numTags = (tagxLength - 12) ~/ 4;
  final tagTable = [
    for (var i = 0; i < numTags; i++)
      (
        tag: tagx.u8(12 + i * 4),
        numValues: tagx.u8(13 + i * 4),
        mask: tagx.u8(14 + i * 4),
        end: tagx.u8(15 + i * 4),
      ),
  ];

  final cncx = <int, String>{};
  var cncxRecordOffset = 0;
  for (var i = 0; i < numCncx; i++) {
    final record = await loadRecord(indxIndex + numRecords + i + 1);
    var pos = 0;
    while (pos < record.length) {
      final index = pos;
      final (:value, :length) = readVarLen(record, pos);
      pos += length;
      final end = pos + value > record.length ? record.length : pos + value;
      cncx[cncxRecordOffset + index] = decodeCharset(
        Uint8List.sublistView(record, pos, end),
        charset,
      );
      pos = end;
    }
    cncxRecordOffset += 0x10000;
  }

  final entries = <MobiIndexEntry>[];
  for (var i = 0; i < numRecords; i++) {
    final record = await loadRecord(indxIndex + 1 + i);
    final b = MobiBytes(record);
    if (b.ascii(0, 4) != 'INDX') {
      throw const FormatException('Invalid INDX record');
    }
    final idxt = b.u32(20);
    final count = b.u32(24);
    for (var j = 0; j < count; j++) {
      final offset = b.u16(idxt + 4 + 2 * j);
      final nameLength = b.u8(offset);
      final name = b.ascii(offset + 1, nameLength);
      final startPos = offset + 1 + nameLength;
      var controlByteIndex = 0;
      var pos = startPos + numControlBytes;
      final tags =
          <({int tag, int? valueCount, int? valueBytes, int numValues})>[];
      for (final (:tag, :numValues, :mask, :end) in tagTable) {
        if (end & 1 != 0) {
          controlByteIndex++;
          continue;
        }
        final value = b.u8(startPos + controlByteIndex) & mask;
        if (value == mask) {
          if (countBitsSet(mask) > 1) {
            final (value: bytes, :length) = readVarLen(record, pos);
            tags.add((
              tag: tag,
              valueCount: null,
              valueBytes: bytes,
              numValues: numValues,
            ));
            pos += length;
          } else {
            tags.add((
              tag: tag,
              valueCount: 1,
              valueBytes: null,
              numValues: numValues,
            ));
          }
        } else {
          tags.add((
            tag: tag,
            valueCount: value >> countUnsetEnd(mask),
            valueBytes: null,
            numValues: numValues,
          ));
        }
      }
      final tagMap = <int, List<int>>{};
      for (final (:tag, :valueCount, :valueBytes, :numValues) in tags) {
        final values = <int>[];
        if (valueCount != null) {
          for (var k = 0; k < valueCount * numValues; k++) {
            final (:value, :length) = readVarLen(record, pos);
            values.add(value);
            pos += length;
          }
        } else {
          var consumed = 0;
          while (consumed < valueBytes!) {
            final (:value, :length) = readVarLen(record, pos);
            values.add(value);
            pos += length;
            consumed += length;
          }
        }
        tagMap[tag] = values;
      }
      entries.add(MobiIndexEntry(name: name, tags: tagMap));
    }
  }
  return MobiIndex(entries: entries, cncx: cncx);
}

/// An NCX entry from the index: a table-of-contents item with its
/// position, heading level and children.
@immutable
class MobiNcxItem {
  const MobiNcxItem({
    required this.index,
    required this.offset,
    required this.size,
    required this.label,
    required this.headingLevel,
    required this.pos,
    required this.parent,
    required this.firstChild,
    required this.lastChild,
    this.children,
  });

  final int index;
  final int? offset;
  final int? size;
  final String label;
  final int? headingLevel;

  /// KF8: `[fid, off]` of the target.
  final List<int>? pos;
  final int? parent;
  final int? firstChild;
  final int? lastChild;
  final List<MobiNcxItem>? children;

  MobiNcxItem withChildren(List<MobiNcxItem> children) => MobiNcxItem(
    index: index,
    offset: offset,
    size: size,
    label: label,
    headingLevel: headingLevel,
    pos: pos,
    parent: parent,
    firstChild: firstChild,
    lastChild: lastChild,
    children: children,
  );
}

/// The NCX tree of the index at [indxIndex] (`getNCX`): top-level items
/// are those at heading level 0, children follow the parent tags.
Future<List<MobiNcxItem>> readMobiNcx(
  int indxIndex,
  Future<Uint8List> Function(int index) loadRecord,
) async {
  final index = await readMobiIndex(indxIndex, loadRecord);
  final items = <MobiNcxItem>[];
  for (var i = 0; i < index.entries.length; i++) {
    final entry = index.entries[i];
    final labelOffset = entry.first(3);
    items.add(
      MobiNcxItem(
        index: i,
        offset: entry.first(1),
        size: entry.first(2),
        label: labelOffset == null ? '' : index.cncx[labelOffset] ?? '',
        headingLevel: entry.first(4),
        pos: entry.tags[6],
        parent: entry.first(21),
        firstChild: entry.first(22),
        lastChild: entry.first(23),
      ),
    );
  }
  MobiNcxItem withChildren(MobiNcxItem item) {
    if (item.firstChild == null) return item;
    return item.withChildren([
      for (final child in items)
        if (child.parent == item.index) withChildren(child),
    ]);
  }

  return [
    for (final item in items)
      if (item.headingLevel == 0) withChildren(item),
  ];
}
