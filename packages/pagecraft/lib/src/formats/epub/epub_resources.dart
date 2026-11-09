/// The package document's manifest, spine, guide and cover (`Resources`
/// in `epub.js`), with hrefs resolved to container paths.
library;

import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

import '../../epubcfi/cfi.dart';
import '../../epubcfi/cfi_resolve.dart';
import '../../epubcfi/xml_cfi_document.dart';
import 'epub_xml.dart';

/// A manifest item: a file of the publication.
@immutable
class EpubManifestItem {
  const EpubManifestItem({
    required this.id,
    required this.href,
    this.mediaType,
    this.properties,
    this.mediaOverlay,
  });

  final String id;

  /// The container path, resolved against the package document.
  final String href;
  final String? mediaType;
  final List<String>? properties;

  /// The id of the media overlay item, when the item has one.
  final String? mediaOverlay;

  bool hasProperty(String property) => properties?.contains(property) ?? false;

  @override
  String toString() => 'EpubManifestItem($id, $href, $mediaType)';
}

/// A spine entry: a reading-order reference to a manifest item.
@immutable
class EpubSpineItem {
  const EpubSpineItem({
    required this.idref,
    this.id,
    this.linear,
    this.properties,
  });

  final String idref;
  final String? id;

  /// `no` for auxiliary content; null or `yes` otherwise.
  final String? linear;
  final List<String>? properties;

  bool get isLinear => linear != 'no';

  @override
  String toString() => 'EpubSpineItem($idref, linear: $linear)';
}

/// A guide reference (EPUB 2 landmarks).
@immutable
class EpubGuideReference {
  const EpubGuideReference({
    required this.label,
    required this.type,
    required this.href,
  });

  final String? label;
  final List<String> type;
  final String href;
}

/// Where a CFI points: the spine index and the CFI to resolve in that
/// section's document.
@immutable
class EpubCfiTarget {
  const EpubCfiTarget({required this.index, required this.cfi});

  /// The spine index, or -1 when the CFI names no spine item.
  final int index;
  final Cfi cfi;
}

/// The manifest, spine and what the package document says about them.
class EpubResources {
  EpubResources._({
    required this.opf,
    required this.manifest,
    required this.spine,
    required this.pageProgressionDirection,
    required this.navPath,
    required this.ncxPath,
    required this.guide,
    required this.cover,
    required this.spineCfis,
    required XmlCfiDocument cfiDocument,
  }) : _cfiDocument = cfiDocument,
       _byId = {for (final item in manifest) item.id: item};

  /// Reads [opf], resolving hrefs with [resolveHref] (relative to the
  /// package document's path in the container).
  factory EpubResources.parse(
    XmlDocument opf, {
    required String Function(String href) resolveHref,
  }) {
    final query = EpubXmlQuery(opf, EpubNamespace.opf);
    final root = opf.rootElement;
    final manifestElement = query.child(root, 'manifest');
    final spineElement = query.child(root, 'spine');
    final manifest = <EpubManifestItem>[
      if (manifestElement != null)
        for (final item in query.children(manifestElement, 'item'))
          if (item.getAttribute('id') case final id?)
            if (item.getAttribute('href') case final href?)
              EpubManifestItem(
                id: id,
                href: resolveHref(href),
                mediaType: item.getAttribute('media-type'),
                properties: splitProperties(item.getAttribute('properties')),
                mediaOverlay: item.getAttribute('media-overlay'),
              ),
    ];
    final itemrefs = spineElement == null
        ? const <XmlElement>[]
        : query.children(spineElement, 'itemref');
    final spine = <EpubSpineItem>[
      for (final ref in itemrefs)
        EpubSpineItem(
          idref: ref.getAttribute('idref') ?? '',
          id: ref.getAttribute('id'),
          linear: ref.getAttribute('linear'),
          properties: splitProperties(ref.getAttribute('properties')),
        ),
    ];
    EpubManifestItem? byId(String? id) {
      if (id == null) return null;
      for (final item in manifest) {
        if (item.id == id) return item;
      }
      return null;
    }

    EpubManifestItem? byHref(String? href) {
      if (href == null) return null;
      for (final item in manifest) {
        if (item.href == href) return item;
      }
      return null;
    }

    EpubManifestItem? byProperty(String property) {
      for (final item in manifest) {
        if (item.hasProperty(property)) return item;
      }
      return null;
    }

    final guideElement = query.child(root, 'guide');
    final guide = guideElement == null
        ? null
        : <EpubGuideReference>[
            for (final ref in query.children(guideElement, 'reference'))
              EpubGuideReference(
                label: ref.getAttribute('title'),
                type: splitProperties(ref.getAttribute('type')) ?? const [],
                href: resolveHref(ref.getAttribute('href') ?? ''),
              ),
          ];

    // EPUB 3 property, else the EPUB 2 meta, else the guide's cover page.
    XmlElement? coverMeta;
    for (final meta in query.descendants(opf, 'meta')) {
      if (meta.getAttribute('name') == 'cover') {
        coverMeta = meta;
        break;
      }
    }
    final cover =
        byProperty('cover-image') ??
        byId(coverMeta?.getAttribute('content')) ??
        byHref(
          guide?.where((ref) => ref.type.contains('cover')).firstOrNull?.href,
        );

    final cfiDocument = XmlCfiDocument(opf);
    final spineCfis = spineElement == null
        ? const <Cfi>[]
        : cfisFromElements([
            for (final ref in itemrefs) cfiDocument.nodeFor(ref)!,
          ]);

    return EpubResources._(
      opf: opf,
      manifest: manifest,
      spine: spine,
      pageProgressionDirection: spineElement?.getAttribute(
        'page-progression-direction',
      ),
      navPath: byProperty('nav')?.href,
      ncxPath:
          (byId(spineElement?.getAttribute('toc')) ??
                  manifest
                      .where((item) => item.mediaType == EpubMediaType.ncx)
                      .firstOrNull)
              ?.href,
      guide: guide,
      cover: cover,
      spineCfis: spineCfis,
      cfiDocument: cfiDocument,
    );
  }

  final XmlDocument opf;
  final List<EpubManifestItem> manifest;
  final List<EpubSpineItem> spine;

  /// `ltr`, `rtl`, `default` or null.
  final String? pageProgressionDirection;
  final String? navPath;
  final String? ncxPath;
  final List<EpubGuideReference>? guide;
  final EpubManifestItem? cover;

  /// The CFI of each spine item (`epubcfi(/6/2[id])`, ...), what every
  /// position in the book starts with.
  final List<Cfi> spineCfis;

  final XmlCfiDocument _cfiDocument;
  final Map<String, EpubManifestItem> _byId;

  EpubManifestItem? itemById(String? id) => id == null ? null : _byId[id];

  EpubManifestItem? itemByHref(String? href) {
    if (href == null) return null;
    for (final item in manifest) {
      if (item.href == href) return item;
    }
    return null;
  }

  EpubManifestItem? itemByProperty(String property) {
    for (final item in manifest) {
      if (item.hasProperty(property)) return item;
    }
    return null;
  }

  /// The spine index of the manifest item with [id], or -1.
  int spineIndexOfId(String? id) {
    if (id == null) return -1;
    for (var i = 0; i < spine.length; i++) {
      if (spine[i].idref == id) return i;
    }
    return -1;
  }

  /// Which spine item [cfi] starts in (`resolveCFI`). An id assertion
  /// that names something other than an itemref is dropped and the path
  /// tried again, as Epub.js once wrote wrong assertions.
  EpubCfiTarget resolveCfi(Cfi cfi) {
    final top = cfi.firstPath;
    var element = _topElement(top);
    if (element != null &&
        element.name.local != 'itemref' &&
        top.isNotEmpty &&
        top.last.id != null) {
      element = _topElement([
        ...top.take(top.length - 1),
        top.last.copyWith(id: null),
      ]);
    }
    final idref = element?.getAttribute('idref');
    return EpubCfiTarget(index: spineIndexOfId(idref), cfi: cfi);
  }

  XmlElement? _topElement(CfiPath path) {
    try {
      final node = cfiToElement(_cfiDocument, CfiLocation([path]));
      final xml = (node as XmlCfiNode).xml;
      return xml is XmlElement ? xml : null;
    } on CfiResolveException {
      return null;
    }
  }
}
