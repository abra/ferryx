/// KF8 (AZW3) books (`class KF8` in `mobi.js`): sections are skeletons
/// with fragments inserted at byte offsets, resources and positions are
/// `kindle:` URIs, the table of contents comes from the NCX index and
/// page spreads from the RESC record.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

import '../../text/html_entities.dart';
import '../book_navigation.dart';
import '../../fixed_layout/spread_layout.dart' show SpreadSide;
import 'mobi_container.dart';
import 'mobi_headers.dart';
import 'mobi_index.dart';

/// A skeleton: the shell of a section's HTML.
@immutable
class Kf8Skeleton {
  const Kf8Skeleton({
    required this.index,
    required this.name,
    required this.numFragments,
    required this.offset,
    required this.length,
  });

  final int index;
  final String name;
  final int numFragments;
  final int offset;
  final int length;
}

/// A fragment inserted into a skeleton.
@immutable
class Kf8Fragment {
  const Kf8Fragment({
    required this.insertOffset,
    required this.selector,
    required this.index,
    required this.offset,
    required this.length,
  });

  /// Where in the whole text the fragment goes.
  final int insertOffset;
  final String? selector;

  /// The fragment id `kindle:pos:fid:` links use.
  final int index;
  final int offset;
  final int length;
}

/// One section: a skeleton with its fragments; a skeleton without
/// fragments is a non-linear placeholder, as `mobi.js` keeps it.
@immutable
class Kf8Section {
  const Kf8Section({
    required this.index,
    required this.skeleton,
    required this.fragments,
    required this.length,
    required this.pageSpread,
  });

  final int index;
  final Kf8Skeleton skeleton;
  final List<Kf8Fragment> fragments;

  /// Skeleton and fragment bytes together, the progress weight.
  final int length;
  final SpreadSide? pageSpread;

  bool get isLinear => fragments.isNotEmpty;

  int get size => isLinear ? length : 0;
}

/// Where a `kindle:pos:fid:X:off:Y` link points.
@immutable
class Kf8HrefTarget {
  const Kf8HrefTarget({required this.index, required this.selector});

  final int index;

  /// A CSS attribute selector (`[id="x"]`, `[name="x"]`, `[aid="x"]`) for
  /// the element at the position, or null when none was found.
  final String? selector;
}

/// A parsed `kindle:flow:`/`kindle:embed:` URI.
@immutable
class KindleResourceUri {
  const KindleResourceUri({
    required this.resourceType,
    required this.id,
    this.mediaType,
  });

  /// `flow` or `embed`.
  final String resourceType;
  final int id;
  final String? mediaType;
}

/// A parsed `kindle:pos:` URI.
@immutable
class KindlePosition {
  const KindlePosition({required this.fid, required this.off});

  final int fid;
  final int off;

  /// The URI form (`makePosURI`): base-32 upper-case, zero-padded.
  String toUri() =>
      'kindle:pos:fid:${fid.toRadixString(32).toUpperCase().padLeft(4, '0')}'
      ':off:${off.toRadixString(32).toUpperCase().padLeft(10, '0')}';

  @override
  bool operator ==(Object other) =>
      other is KindlePosition && other.fid == fid && other.off == off;

  @override
  int get hashCode => Object.hash(fid, off);

  @override
  String toString() => 'KindlePosition(fid: $fid, off: $off)';
}

final _resourceUri = RegExp(
  r'kindle:(flow|embed):(\w+)(?:\?mime=(\w+\/[-+.\w]+))?',
);
final _posUri = RegExp(r'kindle:pos:fid:(\w+):off:(\w+)');

/// Parses a `kindle:flow:`/`kindle:embed:` URI, or null.
KindleResourceUri? parseKindleResourceUri(String text) {
  final match = _resourceUri.firstMatch(text);
  if (match == null) return null;
  return KindleResourceUri(
    resourceType: match.group(1)!,
    id: int.parse(match.group(2)!, radix: 32),
    mediaType: match.group(3),
  );
}

/// Parses a `kindle:pos:` URI, or null.
KindlePosition? parseKindlePosition(String text) {
  final match = _posUri.firstMatch(text);
  if (match == null) return null;
  return KindlePosition(
    fid: int.parse(match.group(1)!, radix: 32),
    off: int.parse(match.group(2)!, radix: 32),
  );
}

/// The selector for the first `id`, `name` or `aid` attribute in [text],
/// as `getFragmentSelector` finds the element a position names.
String? kindleFragmentSelector(String text) {
  final match = _fragmentAttribute.firstMatch(text);
  if (match == null) return null;
  return '[${match.group(1)!.toLowerCase()}="${_escapeSelector(match.group(2)!)}"]';
}

final _fragmentAttribute = RegExp(
  '''\\s(id|name|aid)\\s*=\\s*['"]([^'"]*)['"]''',
  caseSensitive: false,
);

String _escapeSelector(String value) =>
    value.replaceAllMapped(RegExp(r'["\\]'), (m) => '\\${m[0]}');

/// An opened KF8 book.
class Kf8Book {
  Kf8Book._(this.container, this.sections, this._fdst, this._fullRawLength);

  static Future<Kf8Book> load(MobiContainer container) async {
    final kf8 = container.headers.kf8!;
    List<(int, int)>? fdst;
    int? fullRawLength;
    try {
      final b = MobiBytes(await container.loadRecord(kf8.fdst));
      if (b.ascii(0, 4) == 'FDST') {
        final count = b.u32(8);
        fdst = [
          for (var i = 0; i < count; i++)
            (b.u32(12 + i * 8), b.u32(16 + i * 8)),
        ];
        if (fdst.isNotEmpty) {
          fullRawLength = fdst.last.$2;
        }
      }
    } on Object {
      // No flow table: raw text is loaded from the front only.
    }

    final skeletons = <Kf8Skeleton>[];
    final skelIndex = await readMobiIndex(kf8.skel, container.loadRecord);
    for (var i = 0; i < skelIndex.entries.length; i++) {
      final entry = skelIndex.entries[i];
      skeletons.add(
        Kf8Skeleton(
          index: i,
          name: entry.name,
          numFragments: entry.first(1) ?? 0,
          offset: entry.tags[6]?[0] ?? 0,
          length: entry.tags[6]?[1] ?? 0,
        ),
      );
    }
    final fragIndex = await readMobiIndex(kf8.frag, container.loadRecord);
    final fragments = <Kf8Fragment>[
      for (final entry in fragIndex.entries)
        Kf8Fragment(
          insertOffset: int.tryParse(entry.name) ?? 0,
          selector: fragIndex.cncx[entry.first(2) ?? -1],
          index: entry.first(4) ?? 0,
          offset: entry.tags[6]?[0] ?? 0,
          length: entry.tags[6]?[1] ?? 0,
        ),
    ];

    final pageSpreads = await _readPageSpreads(container);
    final sections = <Kf8Section>[];
    var fragEnd = 0;
    for (final skeleton in skeletons) {
      final fragStart = fragEnd;
      fragEnd = fragStart + skeleton.numFragments;
      final own = fragments.sublist(
        fragStart < fragments.length ? fragStart : fragments.length,
        fragEnd < fragments.length ? fragEnd : fragments.length,
      );
      sections.add(
        Kf8Section(
          index: sections.length,
          skeleton: skeleton,
          fragments: own,
          length: skeleton.length + own.fold(0, (sum, f) => sum + f.length),
          pageSpread: pageSpreads[skeleton.index],
        ),
      );
    }

    final book = Kf8Book._(container, sections, fdst, fullRawLength);
    await book._readNavigation();
    return book;
  }

  final MobiContainer container;
  final List<Kf8Section> sections;
  final List<(int, int)>? _fdst;
  final int? _fullRawLength;

  /// Text loaded from the front and from the back, as `loadRaw` fills
  /// them: at worst half the book is held.
  Uint8List _rawHead = Uint8List(0);
  Uint8List _rawTail = Uint8List(0);
  int _lastLoadedHead = -1;
  int _lastLoadedTail = -1;

  /// Positions the table of contents names, by fragment id.
  final _fragmentOffsets = <int, List<int>>{};
  final _fragmentSelectors = <int, Map<int, String?>>{};

  List<BookNavItem>? toc;
  List<BookNavItem>? landmarks;

  MobiMetadata get metadata => container.metadata;

  Future<MobiCover?> readCover() => container.readCover();

  /// `rtl` or `ltr` from EXTH, or null.
  String? get dir => container.headers.exth?.pageProgressionDirection;

  bool get isFixedLayout => container.headers.exth?.fixedLayout == 'true';

  /// The original resolution as a viewport, when EXTH gives one.
  ({int width, int height})? get viewport {
    final parts = container.headers.exth?.originalResolution?.split('x');
    if (parts == null || parts.length < 2) return null;
    final width = int.tryParse(parts[0]);
    final height = int.tryParse(parts[1]);
    if (width == null || height == null) return null;
    return (width: width, height: height);
  }

  /// Text bytes [start]..[end] of the whole stream, loading records from
  /// whichever end is nearer (`loadRaw`).
  Future<Uint8List> loadRaw(int start, int end) async {
    final distanceHead = end - _rawHead.length;
    final full = _fullRawLength;
    final distanceEnd = full == null
        ? double.infinity
        : ((full - _rawTail.length) - start).toDouble();
    final numText = container.headers.palmdoc.numTextRecords;
    if (distanceHead < 0 || distanceHead < distanceEnd) {
      while (_rawHead.length < end && _lastLoadedHead + 1 < numText) {
        final data = await container.loadText(++_lastLoadedHead);
        _rawHead = _concat(_rawHead, data);
      }
      final to = end < _rawHead.length ? end : _rawHead.length;
      return Uint8List.sublistView(_rawHead, start < to ? start : to, to);
    }
    while (full! - _rawTail.length > start && _lastLoadedTail + 1 < numText) {
      final index = numText - 1 - (++_lastLoadedTail);
      final data = await container.loadText(index);
      _rawTail = _concat(data, _rawTail);
    }
    final tailStart = full - _rawTail.length;
    final from = start - tailStart;
    final to = end - tailStart;
    return Uint8List.sublistView(
      _rawTail,
      from < 0 ? 0 : from,
      to > _rawTail.length ? _rawTail.length : to,
    );
  }

  /// Flow [index] (`kindle:flow:`), or null without a flow table.
  Future<Uint8List?> loadFlow(int index) async {
    final fdst = _fdst;
    if (fdst == null || index >= fdst.length || index >= 0xFFFFFFFF) {
      return null;
    }
    final (start, end) = fdst[index];
    return loadRaw(start, end);
  }

  /// The text of section [index]: its skeleton with the fragments
  /// inserted, decoded (`loadText`).
  Future<String> loadText(int index) async {
    final section = sections[index];
    final skel = section.skeleton;
    final raw = await loadRaw(skel.offset, skel.offset + section.length);
    var skeleton = Uint8List.sublistView(
      raw,
      0,
      skel.length < raw.length ? skel.length : raw.length,
    );
    for (final frag in section.fragments) {
      final insertOffset = frag.insertOffset - skel.offset;
      final offset = skel.length + frag.offset;
      final fragRaw = Uint8List.sublistView(
        raw,
        offset < raw.length ? offset : raw.length,
        offset + frag.length < raw.length ? offset + frag.length : raw.length,
      );
      final at = insertOffset < 0
          ? 0
          : insertOffset > skeleton.length
          ? skeleton.length
          : insertOffset;
      skeleton = _concat3(
        Uint8List.sublistView(skeleton, 0, at),
        fragRaw,
        Uint8List.sublistView(skeleton, at),
      );
      final offsets = _fragmentOffsets[frag.index];
      if (offsets != null) {
        for (final off in offsets) {
          final text = container.decode(
            Uint8List.sublistView(
              fragRaw,
              off < fragRaw.length ? off : fragRaw.length,
            ),
          );
          _setFragmentSelector(frag.index, off, kindleFragmentSelector(text));
        }
      }
    }
    return container.decode(skeleton);
  }

  /// The bytes a `kindle:flow:`/`kindle:embed:` URI names, or null.
  Future<Uint8List?> loadResource(String uri) async {
    final parsed = parseKindleResourceUri(uri);
    if (parsed == null) return null;
    if (parsed.resourceType == 'flow') return loadFlow(parsed.id);
    return container.loadResource(parsed.id - 1);
  }

  /// The section whose fragments include [fid], or -1.
  int indexByFid(int fid) =>
      sections.indexWhere((s) => s.fragments.any((f) => f.index == fid));

  /// Where a `kindle:pos:` link points (`resolveHref`), or null for a
  /// position in no section.
  Future<Kf8HrefTarget?> resolveHref(String href) async {
    final pos = parseKindlePosition(href);
    if (pos == null) return null;
    final index = indexByFid(pos.fid);
    if (index < 0) return null;
    final saved = _fragmentSelectors[pos.fid];
    if (saved != null && saved.containsKey(pos.off)) {
      return Kf8HrefTarget(index: index, selector: saved[pos.off]);
    }
    final section = sections[index];
    final skel = section.skeleton;
    final frag = section.fragments.firstWhere((f) => f.index == pos.fid);
    final offset = skel.offset + skel.length + frag.offset;
    final fragRaw = await loadRaw(offset, offset + frag.length);
    final text = container.decode(
      Uint8List.sublistView(
        fragRaw,
        pos.off < fragRaw.length ? pos.off : fragRaw.length,
      ),
    );
    final selector = kindleFragmentSelector(text);
    _setFragmentSelector(pos.fid, pos.off, selector);
    return Kf8HrefTarget(index: index, selector: selector);
  }

  /// Whether [uri] leaves the book: a scheme other than `kindle:`.
  bool isExternal(String uri) => _external.hasMatch(uri);

  static final _external = RegExp(
    r'^(?!blob|kindle)\w+:',
    caseSensitive: false,
  );

  Future<void> close() => container.close();

  void _setFragmentSelector(int fid, int off, String? selector) {
    (_fragmentSelectors[fid] ??= {})[off] = selector;
  }

  Future<void> _readNavigation() async {
    try {
      final ncx = await container.readNcx();
      if (ncx != null) {
        toc = ncx.map(_tocItem).toList();
      }
      landmarks = await _readGuide();
    } on Object {
      // mobi.js warns and leaves what it has.
    }
  }

  BookNavItem _tocItem(MobiNcxItem item) {
    final pos = item.pos ?? const [0, 0];
    final position = KindlePosition(
      fid: pos.isNotEmpty ? pos[0] : 0,
      off: pos.length > 1 ? pos[1] : 0,
    );
    (_fragmentOffsets[position.fid] ??= []).add(position.off);
    return BookNavItem(
      label: unescapeHtml(item.label),
      href: position.toUri(),
      subitems: item.children?.map(_tocItem).toList(),
    );
  }

  Future<List<BookNavItem>?> _readGuide() async {
    final index = container.headers.kf8!.guide;
    if (index >= 0xFFFFFFFF) return null;
    final guide = await readMobiIndex(index, container.loadRecord);
    return [
      for (final entry in guide.entries)
        BookNavItem(
          label: guide.cncx[entry.first(1) ?? -1] ?? '',
          type: entry.name.split(RegExp(r'\s')),
          href: KindlePosition(
            fid: entry.first(6) ?? entry.first(3) ?? 0,
            off: 0,
          ).toUri(),
        ),
    ];
  }

  /// Page spreads from the RESC record's spine (`skelid` → properties).
  static Future<Map<int, SpreadSide?>> _readPageSpreads(
    MobiContainer container,
  ) async {
    final spreads = <int, SpreadSide?>{};
    final kf8 = container.headers.kf8!;
    for (var i = kf8.resourceStart; i < container.pdb.numRecords; i++) {
      String magic;
      try {
        magic = await container.pdb.readMagic(i);
      } on Object {
        continue;
      }
      if (magic != 'RESC') continue;
      try {
        final record = await container.pdb.readRecord(i);
        final text = container
            .decode(Uint8List.sublistView(record, 16))
            .replaceAll('\u0000', '');
        final at = text.indexOf('?>');
        // The RESC record lacks the root `<package>` element.
        final document = XmlDocument.parse(
          '<package>${at < 0 ? text : text.substring(at)}</package>',
        );
        for (final spine in document.findAllElements('spine')) {
          for (final itemref in spine.findElements('itemref')) {
            final skelid = int.tryParse(itemref.getAttribute('skelid') ?? '');
            if (skelid == null) continue;
            spreads[skelid] = _pageSpread(
              itemref.getAttribute('properties')?.split(' ') ?? const [],
            );
          }
        }
      } on Object {
        // A RESC record that does not parse gives no spreads.
      }
      break;
    }
    return spreads;
  }

  static SpreadSide? _pageSpread(List<String> properties) {
    for (final p in properties) {
      switch (p) {
        case 'page-spread-left' || 'rendition:page-spread-left':
          return SpreadSide.left;
        case 'page-spread-right' || 'rendition:page-spread-right':
          return SpreadSide.right;
        case 'rendition:page-spread-center':
          return SpreadSide.center;
      }
    }
    return null;
  }
}

Uint8List _concat(Uint8List a, Uint8List b) {
  final out = Uint8List(a.length + b.length);
  out.setRange(0, a.length, a);
  out.setRange(a.length, out.length, b);
  return out;
}

Uint8List _concat3(Uint8List a, Uint8List b, Uint8List c) {
  final out = Uint8List(a.length + b.length + c.length);
  out.setRange(0, a.length, a);
  out.setRange(a.length, a.length + b.length, b);
  out.setRange(a.length + b.length, out.length, c);
  return out;
}
