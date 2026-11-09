/// An EPUB publication: the port of the `EPUB` class in `epub.js`, minus
/// what only a browser needs (blob URLs, media overlay playback).
///
/// Opening reads `META-INF/container.xml`, the package document,
/// `META-INF/encryption.xml`, the navigation document or NCX and the
/// iBooks/Kobo display options, then exposes the spine as [sections],
/// the table of contents, landmarks, page list, metadata, rendition
/// properties and the reading direction. Section text and resources are
/// read on demand; obfuscated fonts are decoded as they are read.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

import '../../fixed_layout/spread_layout.dart' show SpreadSide;
import '../../container/book_url.dart';
import '../../epubcfi/cfi.dart';
import '../../pagecraft_exception.dart';
import '../book_navigation.dart';
import 'epub_encryption.dart';
import 'epub_files.dart';
import 'epub_metadata.dart';
import 'epub_nav.dart';
import 'epub_resources.dart';
import 'epub_url.dart';
import 'epub_xml.dart';

/// One spine item as the reader sees it.
@immutable
class EpubSection {
  const EpubSection({
    required this.index,
    required this.item,
    required this.spineItem,
    required this.size,
    required this.cfi,
    required this.pageSpread,
    required this.mediaOverlay,
  });

  final int index;
  final EpubManifestItem item;
  final EpubSpineItem spineItem;

  /// The container path, the section's identity (`id` in `epub.js`).
  String get href => item.href;

  /// Uncompressed size in bytes, the weight the progress model uses.
  final int size;

  /// The spine step CFI every position in this section starts with.
  final Cfi cfi;

  /// `linear="no"` marks auxiliary content.
  bool get isLinear => spineItem.isLinear;

  final SpreadSide? pageSpread;
  final EpubManifestItem? mediaOverlay;

  /// A link in this section as a container path (`resolveHref`).
  String resolveHref(String href) => resolveBookUrl(href, item.href);

  @override
  String toString() => 'EpubSection($index, $href, $size bytes)';
}

/// Where a link points: the spine index and the fragment, if any.
@immutable
class EpubHrefTarget {
  const EpubHrefTarget({required this.index, this.fragment});

  final int index;
  final String? fragment;
}

/// Cover image bytes with their media type.
@immutable
class EpubCover {
  const EpubCover({required this.bytes, required this.mediaType});

  final Uint8List bytes;
  final String? mediaType;
}

/// An opened EPUB.
class EpubBook {
  EpubBook._({
    required this.files,
    required this.opfPath,
    required this.resources,
    required this.sections,
    required this.toc,
    required this.pageList,
    required this.landmarks,
    required this.metadata,
    required this.parsedMetadata,
    required this.rendition,
    required this.media,
    required this.dir,
    required EpubEncryption encryption,
  }) : _encryption = encryption;

  /// Opens the container at [path].
  static Future<EpubBook> open(String path) async {
    final files = await ZipEpubFiles.open(path);
    try {
      return await load(files);
    } catch (_) {
      await files.close();
      rethrow;
    }
  }

  /// Reads a publication from [files]; the book owns them afterwards.
  static Future<EpubBook> load(EpubFiles files) async {
    final container = await _loadXml(files, 'META-INF/container.xml');
    if (container == null) {
      throw const PagecraftException('Failed to load container file');
    }
    String? opfPath;
    for (final rootfile in container.findAllElements(
      'rootfile',
      namespace: EpubNamespace.container,
    )) {
      if (rootfile.getAttribute('media-type') == EpubMediaType.package) {
        opfPath = rootfile.getAttribute('full-path');
        break;
      }
    }
    if (opfPath == null) {
      throw const PagecraftException(
        'No package document defined in container',
      );
    }
    final opf = await _loadXml(files, opfPath);
    if (opf == null) {
      throw const PagecraftException('Failed to load package document');
    }
    final encryption = EpubEncryption.parse(
      await _loadXml(files, 'META-INF/encryption.xml'),
      opf,
    );
    final opfDir = opfPath;
    final resources = EpubResources.parse(
      opf,
      resolveHref: (href) => resolveBookUrl(href, opfDir),
    );

    final sections = <EpubSection>[];
    for (var i = 0; i < resources.spine.length; i++) {
      final spineItem = resources.spine[i];
      final item = resources.itemById(spineItem.idref);
      // A spine entry without a manifest item is skipped, as epub.js warns
      // and skips it.
      if (item == null) continue;
      sections.add(
        EpubSection(
          index: sections.length,
          item: item,
          spineItem: spineItem,
          size: files.sizeOf(item.href) ?? 0,
          cfi: resources.spineCfis[i],
          pageSpread: _pageSpread(spineItem.properties),
          mediaOverlay: resources.itemById(item.mediaOverlay),
        ),
      );
    }

    List<BookNavItem>? toc;
    List<BookNavItem>? pageList;
    List<BookNavItem>? landmarks;
    final navPath = resources.navPath;
    if (navPath != null) {
      final nav = await _loadXml(files, navPath, lenient: true);
      if (nav != null) {
        final parsed = parseEpubNav(
          nav,
          resolve: (href) => resolveBookUrl(href, navPath),
        );
        toc = parsed.toc;
        pageList = parsed.pageList;
        landmarks = parsed.landmarks;
      }
    }
    final ncxPath = resources.ncxPath;
    if (toc == null && ncxPath != null) {
      final ncx = await _loadXml(files, ncxPath, lenient: true);
      if (ncx != null) {
        final parsed = parseEpubNcx(
          ncx,
          resolve: (href) => resolveBookUrl(href, ncxPath),
        );
        toc = parsed.toc;
        pageList = parsed.pageList;
      }
    }
    landmarks ??= resources.guide
        ?.map(
          (ref) => BookNavItem(
            label: ref.label ?? '',
            href: ref.href,
            type: ref.type,
          ),
        )
        .toList();

    final packageMetadata = parseEpubMetadata(opf);
    final rendition = Map<String, String>.of(packageMetadata.rendition);
    final dir = resources.pageProgressionDirection;
    final displayOptions = _displayOptions(
      await _loadXml(
            files,
            'META-INF/com.apple.ibooks.display-options.xml',
            lenient: true,
          ) ??
          await _loadXml(
            files,
            'META-INF/com.kobobooks.display-options.xml',
            lenient: true,
          ),
    );
    if (displayOptions != null) {
      if (displayOptions.fixedLayout == 'true') {
        rendition.putIfAbsent('layout', () => 'pre-paginated');
      }
      if (displayOptions.openToSpread == 'false') {
        final firstIndex = sections.indexWhere((s) => s.isLinear);
        if (firstIndex >= 0 && sections[firstIndex].pageSpread == null) {
          final first = sections[firstIndex];
          sections[firstIndex] = EpubSection(
            index: first.index,
            item: first.item,
            spineItem: first.spineItem,
            size: first.size,
            cfi: first.cfi,
            pageSpread: dir == 'rtl' ? SpreadSide.left : SpreadSide.right,
            mediaOverlay: first.mediaOverlay,
          );
        }
      }
    }

    return EpubBook._(
      files: files,
      opfPath: opfPath,
      resources: resources,
      sections: List.unmodifiable(sections),
      toc: toc,
      pageList: pageList,
      landmarks: landmarks,
      metadata: packageMetadata.metadata,
      parsedMetadata: packageMetadata.parsed,
      rendition: Map.unmodifiable(rendition),
      media: packageMetadata.media,
      dir: dir,
      encryption: encryption,
    );
  }

  final EpubFiles files;
  final String opfPath;
  final EpubResources resources;

  /// The spine in reading order, without entries that have no item.
  final List<EpubSection> sections;

  final List<BookNavItem>? toc;
  final List<BookNavItem>? pageList;
  final List<BookNavItem>? landmarks;
  final EpubMetadata metadata;
  final EpubParsedMetadata parsedMetadata;

  /// `rendition:*` properties, with `layout` set to `pre-paginated` when
  /// only the iBooks/Kobo display options said so.
  final Map<String, String> rendition;
  final EpubMediaMetadata media;

  /// The spine's page progression direction (`ltr`, `rtl`), or null.
  final String? dir;

  final EpubEncryption _encryption;

  bool get isFixedLayout => rendition['layout'] == 'pre-paginated';

  /// The text of section [index].
  Future<String> readSectionText(int index) async {
    final text = await files.readText(sections[index].href);
    if (text == null) {
      throw PagecraftException('Missing section ${sections[index].href}');
    }
    return text;
  }

  /// The bytes of the resource at container path [href], deobfuscated
  /// when the container obfuscates it, or null when missing.
  Future<Uint8List?> readResource(String href) async {
    final bytes = await files.readBytes(href);
    if (bytes == null) return null;
    return _encryption.decode(href, bytes);
  }

  /// Which section a CFI starts in (`resolveCFI`).
  EpubCfiTarget resolveCfi(Cfi cfi) => resources.resolveCfi(cfi);

  /// Which section a container path with an optional fragment points to,
  /// or null when no manifest item has that path (`resolveHref`).
  EpubHrefTarget? resolveHref(String href) {
    final hash = href.indexOf('#');
    final path = hash < 0 ? href : href.substring(0, hash);
    final fragment = hash < 0 ? null : href.substring(hash + 1);
    final item = resources.itemByHref(decodeBookUri(path));
    if (item == null) return null;
    final index = sections.indexWhere((s) => identical(s.item, item));
    if (index < 0) return null;
    return EpubHrefTarget(
      index: index,
      fragment: fragment == null || fragment.isEmpty ? null : fragment,
    );
  }

  /// Whether [uri] leaves the container.
  bool isExternal(String uri) => isExternalEpubUri(uri);

  /// The cover image (`getCover`): the cover item's bytes, or, when the
  /// cover is a page, the image that page shows.
  Future<EpubCover?> readCover() async {
    final cover = resources.cover;
    if (cover == null) return null;
    if (cover.mediaType == EpubMediaType.xhtml ||
        cover.mediaType == EpubMediaType.html) {
      final text = await files.readText(cover.href);
      if (text != null) {
        final src = _coverImageSource(text);
        if (src != null) {
          final image = resources.itemByHref(resolveBookUrl(src, cover.href));
          if (image != null &&
              (image.mediaType?.startsWith('image/') ?? false)) {
            final bytes = await readResource(image.href);
            if (bytes != null) {
              return EpubCover(bytes: bytes, mediaType: image.mediaType);
            }
          }
        }
      }
    }
    final bytes = await readResource(cover.href);
    if (bytes == null) return null;
    return EpubCover(bytes: bytes, mediaType: cover.mediaType);
  }

  Future<void> close() => files.close();

  static Future<XmlDocument?> _loadXml(
    EpubFiles files,
    String path, {
    bool lenient = false,
  }) async {
    final text = await files.readText(path);
    if (text == null) return null;
    try {
      return XmlDocument.parse(text);
    } on XmlException catch (error) {
      // epub.js warns and goes on without navigation or display options;
      // the container and package documents must parse.
      if (lenient) return null;
      throw PagecraftException('XML parsing error: $path (${error.message})');
    }
  }

  static SpreadSide? _pageSpread(List<String>? properties) {
    if (properties == null) return null;
    for (final property in properties) {
      switch (property) {
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

  static ({String fixedLayout, String openToSpread})? _displayOptions(
    XmlDocument? document,
  ) {
    if (document == null) return null;
    String option(String name) {
      for (final element in document.findAllElements('option')) {
        if (element.getAttribute('name') == name) return elementText(element);
      }
      return '';
    }

    return (
      fixedLayout: option('fixed-layout'),
      openToSpread: option('open-to-spread'),
    );
  }

  /// The `src` of the first `img`, or the `href` of the first SVG
  /// `image`, in a cover page. The page is parsed as XML when it is
  /// well-formed and scanned for the tag otherwise.
  static String? _coverImageSource(String text) {
    try {
      final document = XmlDocument.parse(text);
      for (final element in document.descendantElements) {
        if (element.name.local == 'img') {
          return element.getAttribute('src');
        }
        if (element.name.local == 'image') {
          return element.getAttribute('href') ??
              attributeNs(element, EpubNamespace.xlink, 'href');
        }
      }
      return null;
    } on XmlException {
      final match = _coverTag.firstMatch(text);
      return match?.group(2);
    }
  }

  static final _coverTag = RegExp(
    r'<(?:img|image)\b[^>]*?\s(?:src|href|xlink:href)\s*=\s*["'
    "'"
    r']([^"'
    "'"
    r']*)',
    caseSensitive: false,
  );
}
