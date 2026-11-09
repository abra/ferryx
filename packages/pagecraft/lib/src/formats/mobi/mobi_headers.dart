/// The fixed-layout headers of a MOBI file, read as `mobi.js` reads them:
/// PalmDOC, MOBI, KF8, EXTH, INDX, TAGX, HUFF, CDIC, FDST and FONT, each a
/// table of (offset, length, type) fields over a record's bytes.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../text/charsets.dart';

/// A big-endian view over a record.
extension type const MobiBytes(Uint8List bytes) {
  int get length => bytes.length;

  int u8(int offset) => bytes[offset];

  int u16(int offset) => (bytes[offset] << 8) | bytes[offset + 1];

  int u32(int offset) =>
      ((bytes[offset] << 24) |
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3]) &
      0xFFFFFFFF;

  /// An unsigned integer of [length] bytes (1, 2 or 4), as `getUint`.
  int uint(int offset, int length) => switch (length) {
    4 => u32(offset),
    2 => u16(offset),
    _ => u8(offset),
  };

  /// A Latin-1 string of [length] bytes, as `getString` decodes magics
  /// and names (UTF-8 in `mobi.js`, which agrees for ASCII).
  String ascii(int offset, int length) {
    final end = offset + length > bytes.length ? bytes.length : offset + length;
    return String.fromCharCodes(bytes, offset, end);
  }

  Uint8List slice(int start, [int? end]) =>
      Uint8List.sublistView(bytes, start, end);
}

/// Record 0's PalmDOC header.
@immutable
class PalmDocHeader {
  const PalmDocHeader({
    required this.compression,
    required this.numTextRecords,
    required this.recordSize,
    required this.encryption,
  });

  factory PalmDocHeader.read(MobiBytes b) => PalmDocHeader(
    compression: b.u16(0),
    numTextRecords: b.u16(8),
    recordSize: b.u16(10),
    encryption: b.u16(12),
  );

  /// 1 none, 2 PalmDOC, 17480 Huffman/CDIC.
  final int compression;
  final int numTextRecords;
  final int recordSize;
  final int encryption;
}

/// The MOBI header that follows the PalmDOC header in record 0.
@immutable
class MobiHeader {
  const MobiHeader({
    required this.length,
    required this.type,
    required this.encoding,
    required this.uid,
    required this.version,
    required this.title,
    required this.language,
    required this.resourceStart,
    required this.huffcdic,
    required this.numHuffcdic,
    required this.exthFlag,
    required this.trailingFlags,
    required this.indx,
  });

  factory MobiHeader.read(MobiBytes b) {
    final length = b.u32(20);
    final titleOffset = b.u32(84);
    final titleLength = b.u32(88);
    final localeRegion = b.u8(94);
    final localeLanguage = b.u8(95);
    final languages = mobiLanguages[localeLanguage];
    String? language;
    if (languages != null) {
      final regional = localeRegion >> 2;
      language = regional < languages.length ? languages[regional] : null;
      language ??= languages[0];
    }
    return MobiHeader(
      length: length,
      type: b.u32(24),
      encoding: b.u32(28),
      uid: b.u32(32),
      version: b.u32(36),
      title: titleOffset + titleLength <= b.length
          ? b.slice(titleOffset, titleOffset + titleLength)
          : Uint8List(0),
      language: language,
      resourceStart: b.u32(108),
      huffcdic: b.u32(112),
      numHuffcdic: b.u32(116),
      exthFlag: b.u32(128),
      // Past the header's own length (16 bytes after the PalmDOC header)
      // the bytes belong to what follows it, the title in old MOBI 3
      // files: those fields are absent, as Calibre reads them.
      trailingFlags: _within(length, 244, b) ? b.u32(240) : 0,
      indx: _within(length, 248, b) ? b.u32(244) : 0xFFFFFFFF,
    );
  }

  /// Whether record 0 holds bytes up to [end] inside a MOBI header of
  /// [length] bytes.
  static bool _within(int length, int end, MobiBytes b) =>
      16 + length >= end && b.length >= end;

  final int length;
  final int type;

  /// 1252 for Windows-1252, 65001 for UTF-8.
  final int encoding;
  final int uid;
  final int version;

  /// The full title, undecoded.
  final Uint8List title;

  /// The language tag from the locale bytes, or null.
  final String? language;
  final int resourceStart;
  final int huffcdic;
  final int numHuffcdic;
  final int exthFlag;
  final int trailingFlags;
  final int indx;

  bool get hasExth => exthFlag & 0x40 != 0;

  /// The charset name for [encoding].
  String get charset => mobiCharset(encoding);
}

/// Extra fields of record 0 in KF8 files.
@immutable
class Kf8Header {
  const Kf8Header({
    required this.resourceStart,
    required this.fdst,
    required this.numFdst,
    required this.frag,
    required this.skel,
    required this.guide,
  });

  factory Kf8Header.read(MobiBytes b) => Kf8Header(
    resourceStart: b.u32(108),
    fdst: b.u32(192),
    numFdst: b.u32(196),
    frag: b.u32(248),
    skel: b.u32(252),
    guide: b.u32(260),
  );

  final int resourceStart;
  final int fdst;
  final int numFdst;
  final int frag;
  final int skel;
  final int guide;
}

/// The EXTH metadata records `mobi.js` reads, by type.
@immutable
class ExthRecords {
  const ExthRecords(this._values);

  final Map<String, Object> _values;

  String? string(String name) => _values[name] as String?;

  int? uint(String name) => _values[name] as int?;

  List<String>? strings(String name) => _values[name] as List<String>?;

  List<String>? get creator => strings('creator');
  String? get publisher => string('publisher');
  String? get description => string('description');
  String? get isbn => string('isbn');
  List<String>? get subject => strings('subject');
  String? get date => string('date');
  List<String>? get contributor => strings('contributor');
  String? get rights => string('rights');
  List<String>? get source => strings('source');
  String? get asin => string('asin');
  int? get boundary => uint('boundary');
  String? get fixedLayout => string('fixedLayout');
  String? get originalResolution => string('originalResolution');
  String? get coverUri => string('coverURI');
  int? get coverOffset => uint('coverOffset');
  int? get thumbnailOffset => uint('thumbnailOffset');
  String? get title => string('title');
  List<String>? get language => strings('language');
  String? get pageProgressionDirection => string('pageProgressionDirection');

  /// Reads the EXTH block at the start of [b] (`getEXTH`).
  static ExthRecords read(MobiBytes b, String charset) {
    if (b.ascii(0, 4) != 'EXTH') {
      throw const FormatException('Invalid EXTH header');
    }
    final count = b.u32(8);
    final values = <String, Object>{};
    var offset = 12;
    for (var i = 0; i < count; i++) {
      if (offset + 8 > b.length) break;
      final type = b.u32(offset);
      final length = b.u32(offset + 4);
      if (length < 8 || offset + length > b.length) break;
      final spec = _exthTypes[type];
      if (spec != null) {
        final data = b.slice(offset + 8, offset + length);
        final Object value = spec.isUint
            ? MobiBytes(data).uint(0, data.length > 4 ? 4 : data.length)
            : decodeCharset(data, charset);
        if (spec.many) {
          final list = values.putIfAbsent(spec.name, () => <String>[]);
          (list as List<String>).add(value as String);
        } else {
          values[spec.name] = value;
        }
      }
      offset += length;
    }
    return ExthRecords(values);
  }
}

class _Exth {
  const _Exth(this.name, {this.isUint = false, this.many = false});

  final String name;
  final bool isUint;
  final bool many;
}

const _exthTypes = <int, _Exth>{
  100: _Exth('creator', many: true),
  101: _Exth('publisher'),
  103: _Exth('description'),
  104: _Exth('isbn'),
  105: _Exth('subject', many: true),
  106: _Exth('date'),
  108: _Exth('contributor', many: true),
  109: _Exth('rights'),
  110: _Exth('subjectCode', many: true),
  112: _Exth('source', many: true),
  113: _Exth('asin'),
  121: _Exth('boundary', isUint: true),
  122: _Exth('fixedLayout'),
  125: _Exth('numResources', isUint: true),
  126: _Exth('originalResolution'),
  127: _Exth('zeroGutter'),
  128: _Exth('zeroMargin'),
  129: _Exth('coverURI'),
  132: _Exth('regionMagnification'),
  201: _Exth('coverOffset', isUint: true),
  202: _Exth('thumbnailOffset', isUint: true),
  503: _Exth('title'),
  524: _Exth('language', many: true),
  527: _Exth('pageProgressionDirection'),
};

/// Record 0 of a MOBI (or KF8) part, parsed.
@immutable
class MobiHeaders {
  const MobiHeaders({
    required this.palmdoc,
    required this.mobi,
    required this.exth,
    required this.kf8,
  });

  /// Parses record 0 (`#getHeaders`).
  factory MobiHeaders.read(Uint8List record) {
    final b = MobiBytes(record);
    if (b.ascii(16, 4) != 'MOBI') {
      throw const FormatException('Missing MOBI header');
    }
    final palmdoc = PalmDocHeader.read(b);
    final mobi = MobiHeader.read(b);
    final exth = mobi.hasExth && mobi.length + 16 < record.length
        ? ExthRecords.read(MobiBytes(b.slice(mobi.length + 16)), mobi.charset)
        : null;
    final kf8 = mobi.version >= 8 ? Kf8Header.read(b) : null;
    return MobiHeaders(palmdoc: palmdoc, mobi: mobi, exth: exth, kf8: kf8);
  }

  final PalmDocHeader palmdoc;
  final MobiHeader mobi;
  final ExthRecords? exth;
  final Kf8Header? kf8;
}

/// The charset for a MOBI encoding code (`MOBI_ENCODING`).
String mobiCharset(int encoding) => encoding == 1252 ? 'windows-1252' : 'utf-8';

/// MOBI locale language codes to language tags (`MOBI_LANG`); null
/// entries are regions without a tag.
const mobiLanguages = <int, List<String?>>{
  1: [
    'ar', 'ar-SA', 'ar-IQ', 'ar-EG', 'ar-LY', 'ar-DZ', 'ar-MA', 'ar-TN', //
    'ar-OM', 'ar-YE', 'ar-SY', 'ar-JO', 'ar-LB', 'ar-KW', 'ar-AE', 'ar-BH', //
    'ar-QA',
  ],
  2: ['bg'],
  3: ['ca'],
  4: ['zh', 'zh-TW', 'zh-CN', 'zh-HK', 'zh-SG'],
  5: ['cs'],
  6: ['da'],
  7: ['de', 'de-DE', 'de-CH', 'de-AT', 'de-LU', 'de-LI'],
  8: ['el'],
  9: [
    'en', 'en-US', 'en-GB', 'en-AU', 'en-CA', 'en-NZ', 'en-IE', 'en-ZA', //
    'en-JM', null, 'en-BZ', 'en-TT', 'en-ZW', 'en-PH',
  ],
  10: [
    'es', 'es-ES', 'es-MX', null, 'es-GT', 'es-CR', 'es-PA', 'es-DO', //
    'es-VE', 'es-CO', 'es-PE', 'es-AR', 'es-EC', 'es-CL', 'es-UY', 'es-PY', //
    'es-BO', 'es-SV', 'es-HN', 'es-NI', 'es-PR',
  ],
  11: ['fi'],
  12: ['fr', 'fr-FR', 'fr-BE', 'fr-CA', 'fr-CH', 'fr-LU', 'fr-MC'],
  13: ['he'],
  14: ['hu'],
  15: ['is'],
  16: ['it', 'it-IT', 'it-CH'],
  17: ['ja'],
  18: ['ko'],
  19: ['nl', 'nl-NL', 'nl-BE'],
  20: ['no', 'nb', 'nn'],
  21: ['pl'],
  22: ['pt', 'pt-BR', 'pt-PT'],
  23: ['rm'],
  24: ['ro'],
  25: ['ru'],
  26: ['hr', null, 'sr'],
  27: ['sk'],
  28: ['sq'],
  29: ['sv', 'sv-SE', 'sv-FI'],
  30: ['th'],
  31: ['tr'],
  32: ['ur'],
  33: ['id'],
  34: ['uk'],
  35: ['be'],
  36: ['sl'],
  37: ['et'],
  38: ['lv'],
  39: ['lt'],
  41: ['fa'],
  42: ['vi'],
  43: ['hy'],
  44: ['az'],
  45: ['eu'],
  46: ['hsb'],
  47: ['mk'],
  48: ['st'],
  49: ['ts'],
  50: ['tn'],
  52: ['xh'],
  53: ['zu'],
  54: ['af'],
  55: ['ka'],
  56: ['fo'],
  57: ['hi'],
  58: ['mt'],
  59: ['se'],
  62: ['ms'],
  63: ['kk'],
  65: ['sw'],
  67: ['uz', null, 'uz-UZ'],
  68: ['tt'],
  69: ['bn'],
  70: ['pa'],
  71: ['gu'],
  72: ['or'],
  73: ['ta'],
  74: ['te'],
  75: ['kn'],
  76: ['ml'],
  77: ['as'],
  78: ['mr'],
  79: ['sa'],
  82: ['cy', 'cy-GB'],
  83: ['gl', 'gl-ES'],
  87: ['kok'],
  97: ['ne'],
  98: ['fy'],
};
