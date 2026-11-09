/// Builds MOBI 6 and KF8 files in memory for tests, laying out the
/// records the way the readers expect: a PDB header and record list,
/// record 0 with the PalmDOC, MOBI, (KF8) and EXTH headers, text records
/// (uncompressed or PalmDOC-compressed, with optional trailing entries),
/// resources, and for KF8 the FDST, skeleton, fragment, NCX and guide
/// index records.
library;

import 'dart:convert';
import 'dart:typed_data';

/// An EXTH record to write.
class MobiExthRecord {
  const MobiExthRecord(this.type, this.data);

  MobiExthRecord.string(this.type, String value)
    : data = Uint8List.fromList(utf8.encode(value));

  MobiExthRecord.uint(this.type, int value)
    : data = Uint8List(4)..buffer.asByteData().setUint32(0, value);

  final int type;
  final Uint8List data;
}

/// An entry of an index record: a name and tag values, as the readers
/// decode them.
class MobiIndexEntryData {
  const MobiIndexEntryData(this.name, this.tags);

  final String name;

  /// Tag number to its values, in the order the TAGX lists tags.
  final Map<int, List<int>> tags;
}

/// A tag of a TAGX table: number, values per entry, control mask.
typedef MobiTagx = ({int tag, int numValues, int mask});

/// Builds a book record by record; [build] returns the file bytes.
class MobiBuilder {
  MobiBuilder({
    this.title = 'Test Book',
    this.version = 6,
    this.encoding = 65001,
    this.uid = 1234,
    this.compress = false,
    this.trailingMultibyte = false,
    this.localeLanguage = 9,
    this.localeRegion = 4,
    this.exth = const [],
    this.mobiHeaderLength = 264,
  });

  final String title;
  final int version;
  final int encoding;
  final int uid;

  /// PalmDOC-compress the text records.
  final bool compress;

  /// Append the multibyte trailing entry to every text record.
  final bool trailingMultibyte;
  final int localeLanguage;
  final int localeRegion;
  final List<MobiExthRecord> exth;

  /// The MOBI header's own length: 264 holds the KF8 fields; old MOBI 3
  /// files end it at 208 (0xD0), before the trailing flags, and what
  /// follows (EXTH, the title) sits where those fields would be.
  final int mobiHeaderLength;

  final _textRecords = <Uint8List>[];
  final _resources = <Uint8List>[];
  final _indexRecords = <List<Uint8List>>[];
  Uint8List? _fdst;
  int _fullTextLength = 0;
  int? _skelIndex;
  int? _fragIndex;
  int? _ncxIndex;
  int? _guideIndex;

  static const recordSize = 4096;

  /// Adds the book text, split into records of [recordSize] bytes.
  void addText(List<int> text) {
    final bytes = Uint8List.fromList(text);
    _fullTextLength = bytes.length;
    for (var start = 0; start < bytes.length; start += recordSize) {
      final end = start + recordSize < bytes.length
          ? start + recordSize
          : bytes.length;
      _textRecords.add(Uint8List.sublistView(bytes, start, end));
    }
    if (bytes.isEmpty) _textRecords.add(Uint8List(0));
  }

  /// Adds a resource record (an image, or a FONT/VIDE record as given)
  /// and returns its resource index.
  int addResource(List<int> bytes) {
    _resources.add(Uint8List.fromList(bytes));
    return _resources.length - 1;
  }

  /// Adds the KF8 flow table: `(start, end)` per flow.
  void setFlows(List<(int, int)> flows) {
    final out = BytesBuilder();
    out.add(ascii.encode('FDST'));
    out.add(_u32(12));
    out.add(_u32(flows.length));
    for (final (start, end) in flows) {
      out.add(_u32(start));
      out.add(_u32(end));
    }
    _fdst = out.toBytes();
  }

  /// Adds an index (INDX primary record, one data record, CNCX records)
  /// and returns the primary record's index among the index records.
  int addIndex({
    required List<MobiTagx> tagx,
    required List<MobiIndexEntryData> entries,
    List<String> cncx = const [],
  }) {
    final records = <Uint8List>[];
    final numCncx = cncx.isEmpty ? 0 : 1;
    final tagxBytes = _tagx(tagx);
    final primary = _indxHeader(
      numRecords: 1,
      idxt: 0,
      numCncx: numCncx,
      total: entries.length,
    );
    records.add(_concat(primary, tagxBytes));
    records.add(_indexDataRecord(tagx, entries));
    if (cncx.isNotEmpty) {
      final out = BytesBuilder();
      for (final text in cncx) {
        final bytes = utf8.encode(text);
        out.add(_varLen(bytes.length));
        out.add(bytes);
      }
      records.add(out.toBytes());
    }
    _indexRecords.add(records);
    return _indexRecords.length - 1;
  }

  /// Offsets of the CNCX strings written by [addIndex], for tag values.
  static List<int> cncxOffsets(List<String> cncx) {
    final offsets = <int>[];
    var offset = 0;
    for (final text in cncx) {
      offsets.add(offset);
      final length = utf8.encode(text).length;
      offset += _varLen(length).length + length;
    }
    return offsets;
  }

  /// The skeleton index: name, fragment count (tag 1) and `[offset,
  /// length]` (tag 6).
  void setSkeletons(
    List<({String name, int numFragments, int offset, int length})> skeletons,
  ) {
    _skelIndex = addIndex(
      tagx: const [
        (tag: 1, numValues: 1, mask: 3),
        (tag: 6, numValues: 2, mask: 12),
      ],
      entries: [
        for (final s in skeletons)
          MobiIndexEntryData(s.name, {
            1: [s.numFragments],
            6: [s.offset, s.length],
          }),
      ],
    );
  }

  /// The fragment index: insert offset as the name, selector (tag 2, a
  /// CNCX offset), fragment id (tag 4), `[offset, length]` (tag 6).
  void setFragments(
    List<({int insertOffset, int selector, int fid, int offset, int length})>
    fragments, {
    required List<String> cncx,
  }) {
    _fragIndex = addIndex(
      tagx: const [
        (tag: 2, numValues: 1, mask: 1),
        (tag: 4, numValues: 1, mask: 2),
        (tag: 6, numValues: 2, mask: 12),
      ],
      entries: [
        for (final f in fragments)
          MobiIndexEntryData('${f.insertOffset}', {
            2: [f.selector],
            4: [f.fid],
            6: [f.offset, f.length],
          }),
      ],
      cncx: cncx,
    );
  }

  /// The NCX index: label (tag 3, CNCX offset), heading level (tag 4),
  /// position `[fid, off]` (tag 6), parent/children (21..23).
  void setNcx(
    List<
      ({
        String name,
        int label,
        int level,
        int fid,
        int off,
        int? parent,
        int? firstChild,
        int? lastChild,
      })
    >
    items, {
    required List<String> cncx,
  }) {
    _ncxIndex = addIndex(
      tagx: const [
        (tag: 3, numValues: 1, mask: 1),
        (tag: 4, numValues: 1, mask: 2),
        (tag: 6, numValues: 2, mask: 4),
        (tag: 21, numValues: 1, mask: 8),
        (tag: 22, numValues: 1, mask: 16),
        (tag: 23, numValues: 1, mask: 32),
      ],
      entries: [
        for (final i in items)
          MobiIndexEntryData(i.name, {
            3: [i.label],
            4: [i.level],
            6: [i.fid, i.off],
            if (i.parent != null) 21: [i.parent!],
            if (i.firstChild != null) 22: [i.firstChild!],
            if (i.lastChild != null) 23: [i.lastChild!],
          }),
      ],
      cncx: cncx,
    );
  }

  /// The guide index: type as the name, label (tag 1, CNCX), fid (tag 6).
  void setGuide(
    List<({String type, int label, int fid})> items, {
    required List<String> cncx,
  }) {
    _guideIndex = addIndex(
      tagx: const [
        (tag: 1, numValues: 1, mask: 1),
        (tag: 6, numValues: 1, mask: 2),
      ],
      entries: [
        for (final i in items)
          MobiIndexEntryData(i.type, {
            1: [i.label],
            6: [i.fid],
          }),
      ],
      cncx: cncx,
    );
  }

  /// The file bytes.
  Uint8List build() {
    // Record layout: 0 header, text records, [FDST], index records,
    // resources (resource start points here).
    final records = <Uint8List>[];
    records.add(Uint8List(0)); // placeholder for record 0
    for (final text in _textRecords) {
      var bytes = compress ? compressPalmDoc(text) : text;
      if (trailingMultibyte) {
        // One trailing byte whose low bits say "1 byte" (0 + 1).
        bytes = _concat(bytes, Uint8List.fromList([0]));
      }
      records.add(bytes);
    }
    final fdstIndex = _fdst == null ? null : records.length;
    if (_fdst != null) records.add(_fdst!);
    final indexStarts = <int>[];
    for (final index in _indexRecords) {
      indexStarts.add(records.length);
      records.addAll(index);
    }
    final resourceStart = records.length;
    records.addAll(_resources);
    // A trailing record keeps resource lookups by magic in bounds.
    records.add(ascii.encode('EOF '));

    records[0] = _record0(
      resourceStart: resourceStart,
      fdstIndex: fdstIndex,
      indexStarts: indexStarts,
    );

    final out = BytesBuilder();
    final name = Uint8List(32)
      ..setRange(
        0,
        title.length < 31 ? title.length : 31,
        ascii.encode(title.length < 31 ? title : title.substring(0, 31)),
      );
    out.add(name);
    out.add(
      Uint8List(28),
    ); // attributes, version, times, modification, app info, sort info
    out.add(ascii.encode('BOOK'));
    out.add(ascii.encode('MOBI'));
    out.add(Uint8List(8)); // unique id seed, next record list
    out.add(_u16(records.length));
    var offset = 78 + records.length * 8 + 2;
    for (var i = 0; i < records.length; i++) {
      out.add(_u32(offset));
      out.add(Uint8List(4)); // attributes + unique id
      offset += records[i].length;
    }
    out.add(Uint8List(2)); // gap
    for (final record in records) {
      out.add(record);
    }
    return out.toBytes();
  }

  Uint8List _record0({
    required int resourceStart,
    required int? fdstIndex,
    required List<int> indexStarts,
  }) {
    final out = BytesBuilder();
    // PalmDOC header (16 bytes).
    out.add(_u16(compress ? 2 : 1));
    out.add(_u16(0));
    out.add(_u32(_fullTextLength));
    out.add(_u16(_textRecords.length));
    out.add(_u16(recordSize));
    out.add(_u16(0)); // encryption
    out.add(_u16(0));
    // MOBI header, written 264 bytes long for KF8 fields and cut to
    // [mobiHeaderLength].
    const mobiLength = 264;
    final mobi = Uint8List(mobiLength);
    final view = mobi.buffer.asByteData();
    mobi.setRange(0, 4, ascii.encode('MOBI'));
    view.setUint32(4, mobiHeaderLength);
    view.setUint32(8, 2); // type: book
    view.setUint32(12, encoding);
    view.setUint32(16, uid);
    view.setUint32(20, version);
    for (var i = 24; i < 64; i += 4) {
      view.setUint32(i, 0xFFFFFFFF);
    }
    final titleBytes = utf8.encode(title);
    final exthBytes = _exth();
    // Title follows the EXTH block in record 0.
    final titleOffset = 16 + mobiHeaderLength + exthBytes.length;
    view.setUint32(68, titleOffset); // title offset at header offset 84 - 16
    view.setUint32(72, titleBytes.length);
    view.setUint32(76, 0); // locale, with region/language bytes below
    mobi[78] = localeRegion; // offset 94 in the record
    mobi[79] = localeLanguage; // offset 95
    view.setUint32(80, 0); // input language
    view.setUint32(84, 0); // output language
    view.setUint32(88, version); // min version
    view.setUint32(92, resourceStart); // first resource record (offset 108)
    view.setUint32(96, 0xFFFFFFFF); // huffman record
    view.setUint32(100, 0); // huffman count
    view.setUint32(104, 0);
    view.setUint32(108, 0);
    view.setUint32(112, 0x40); // EXTH flags (offset 128)
    for (var i = 116; i < 176; i += 4) {
      view.setUint32(i, 0);
    }
    view.setUint32(176, fdstIndex ?? 0xFFFFFFFF); // FDST (offset 192)
    view.setUint32(180, fdstIndex == null ? 0 : 1); // FDST count (196)
    view.setUint32(184, 0xFFFFFFFF); // FCIS
    view.setUint32(188, 0xFFFFFFFF); // FLIS
    for (var i = 192; i < 224; i += 4) {
      view.setUint32(i, 0xFFFFFFFF);
    }
    view.setUint32(224, trailingMultibyte ? 1 : 0); // trailing flags (240)
    view.setUint32(
      228,
      _ncxIndex == null ? 0xFFFFFFFF : indexStarts[_ncxIndex!],
    ); // INDX (244)
    view.setUint32(
      232,
      _fragIndex == null ? 0xFFFFFFFF : indexStarts[_fragIndex!],
    ); // frag (248)
    view.setUint32(
      236,
      _skelIndex == null ? 0xFFFFFFFF : indexStarts[_skelIndex!],
    ); // skel (252)
    view.setUint32(240, 0xFFFFFFFF); // datp (256)
    view.setUint32(
      244,
      _guideIndex == null ? 0xFFFFFFFF : indexStarts[_guideIndex!],
    ); // guide (260)
    out.add(Uint8List.sublistView(mobi, 0, mobiHeaderLength));
    out.add(exthBytes);
    out.add(titleBytes);
    out.add(Uint8List(8)); // padding
    return out.toBytes();
  }

  Uint8List _exth() {
    final out = BytesBuilder();
    var length = 12;
    final body = BytesBuilder();
    for (final record in exth) {
      body.add(_u32(record.type));
      body.add(_u32(8 + record.data.length));
      body.add(record.data);
      length += 8 + record.data.length;
    }
    out.add(ascii.encode('EXTH'));
    out.add(_u32(length));
    out.add(_u32(exth.length));
    out.add(body.toBytes());
    // Pad to a multiple of four, as writers do.
    while (out.length % 4 != 0) {
      out.addByte(0);
    }
    return out.toBytes();
  }

  Uint8List _indxHeader({
    required int numRecords,
    required int idxt,
    required int numCncx,
    required int total,
  }) {
    final header = Uint8List(192);
    final view = header.buffer.asByteData();
    header.setRange(0, 4, ascii.encode('INDX'));
    view.setUint32(4, 192);
    view.setUint32(8, 0);
    view.setUint32(20, idxt);
    view.setUint32(24, numRecords);
    view.setUint32(28, encoding);
    view.setUint32(32, 0xFFFFFFFF);
    view.setUint32(36, total);
    view.setUint32(40, 0);
    view.setUint32(44, 0);
    view.setUint32(48, 0);
    view.setUint32(52, numCncx);
    return header;
  }

  static Uint8List _tagx(List<MobiTagx> tags) {
    final out = BytesBuilder();
    out.add(ascii.encode('TAGX'));
    out.add(_u32(12 + (tags.length + 1) * 4));
    out.add(_u32(1)); // control bytes
    for (final t in tags) {
      out.add([t.tag, t.numValues, t.mask, 0]);
    }
    out.add([0, 0, 0, 1]); // end-of-control-byte marker
    return out.toBytes();
  }

  /// An index data record: INDX header, entries, then the IDXT table of
  /// entry offsets.
  Uint8List _indexDataRecord(
    List<MobiTagx> tagx,
    List<MobiIndexEntryData> entries,
  ) {
    final body = BytesBuilder();
    final offsets = <int>[];
    const headerLength = 192;
    for (final entry in entries) {
      offsets.add(headerLength + body.length);
      final name = ascii.encode(entry.name);
      body.addByte(name.length);
      body.add(name);
      var control = 0;
      for (final t in tagx) {
        final values = entry.tags[t.tag];
        if (values == null || values.isEmpty) continue;
        // Each tag's mask holds the count of value sets; one set here.
        control |= t.mask & (t.mask ^ (t.mask << 1));
      }
      body.addByte(control);
      for (final t in tagx) {
        final values = entry.tags[t.tag];
        if (values == null || values.isEmpty) continue;
        for (final value in values) {
          body.add(_varLen(value));
        }
      }
    }
    final idxt = headerLength + body.length;
    final header = _indxHeader(
      numRecords: entries.length,
      idxt: idxt,
      numCncx: 0,
      total: entries.length,
    );
    final out = BytesBuilder();
    out.add(header);
    out.add(body.toBytes());
    out.add(ascii.encode('IDXT'));
    for (final offset in offsets) {
      out.add(_u16(offset));
    }
    return out.toBytes();
  }
}

/// A simple PalmDOC compressor: back references of 3–10 bytes within
/// 2047 bytes, space-plus-character pairs, and literals. Not Amazon's
/// encoder, but every output decodes by the format's rules.
Uint8List compressPalmDoc(Uint8List input) {
  final out = BytesBuilder();
  var i = 0;
  while (i < input.length) {
    // Back reference.
    var bestLength = 0;
    var bestDistance = 0;
    final windowStart = i > 2047 ? i - 2047 : 0;
    for (var j = windowStart; j < i; j++) {
      var length = 0;
      while (length < 10 &&
          i + length < input.length &&
          input[j + length] == input[i + length]) {
        length++;
      }
      if (length > bestLength) {
        bestLength = length;
        bestDistance = i - j;
      }
    }
    if (bestLength >= 3) {
      final pair = 0x8000 | (bestDistance << 3) | (bestLength - 3);
      out.addByte(pair >> 8);
      out.addByte(pair & 0xFF);
      i += bestLength;
      continue;
    }
    final byte = input[i];
    if (byte == 0x20 &&
        i + 1 < input.length &&
        input[i + 1] >= 0x40 &&
        input[i + 1] <= 0x7F) {
      out.addByte(input[i + 1] | 0x80);
      i += 2;
      continue;
    }
    if (byte == 0 || (byte >= 0x09 && byte <= 0x7F)) {
      out.addByte(byte);
      i++;
      continue;
    }
    // Other bytes go as a literal run of 1..8.
    var run = 0;
    while (run < 8 &&
        i + run < input.length &&
        !(input[i + run] == 0 ||
            (input[i + run] >= 0x09 && input[i + run] <= 0x7F))) {
      run++;
    }
    out.addByte(run);
    out.add(Uint8List.sublistView(input, i, i + run));
    i += run;
  }
  return out.toBytes();
}

Uint8List _varLen(int value) {
  final bytes = <int>[];
  var v = value;
  do {
    bytes.insert(0, v & 0x7F);
    v >>= 7;
  } while (v > 0);
  bytes[bytes.length - 1] |= 0x80;
  return Uint8List.fromList(bytes);
}

Uint8List _u16(int value) =>
    Uint8List(2)..buffer.asByteData().setUint16(0, value);

Uint8List _u32(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value);

Uint8List _concat(Uint8List a, Uint8List b) {
  final out = Uint8List(a.length + b.length);
  out.setRange(0, a.length, a);
  out.setRange(a.length, out.length, b);
  return out;
}
