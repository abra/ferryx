/// Navigation documents: the EPUB 3 `nav` (`parseNav`) and the EPUB 2 NCX
/// (`parseNCX`), both read into the same item tree.
library;

import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

import '../../container/book_url.dart';
import '../book_navigation.dart';
import 'epub_xml.dart';

/// A `nav` the reader has no slot for (`others`), kept with its heading.
@immutable
class EpubNavList {
  const EpubNavList({
    required this.label,
    required this.type,
    required this.list,
  });

  final String label;
  final List<String> type;
  final List<BookNavItem>? list;
}

/// What a navigation document provides; lists are null when absent.
@immutable
class EpubNavigation {
  const EpubNavigation({
    this.toc,
    this.pageList,
    this.landmarks,
    this.others = const [],
  });

  final List<BookNavItem>? toc;
  final List<BookNavItem>? pageList;
  final List<BookNavItem>? landmarks;
  final List<EpubNavList> others;
}

/// Reads an EPUB 3 navigation document. [resolve] turns an href into a
/// container path (relative to the document); the result is percent-
/// decoded, as the reader matches it against manifest paths.
EpubNavigation parseEpubNav(
  XmlDocument document, {
  String Function(String href)? resolve,
}) {
  final query = EpubXmlQuery(document, EpubNamespace.xhtml);
  // An empty href is no target, as `href ? … : null` reads in epub.js.
  String? resolveHref(String? href) => href == null || href.isEmpty
      ? null
      : decodeBookUri(resolve?.call(href) ?? href);

  List<BookNavItem>? parseList(XmlElement? ol, {bool withType = false}) {
    if (ol == null) return null;
    return [
      for (final li in query.children(ol, 'li'))
        _parseLi(li, query, resolveHref, withType: withType),
    ];
  }

  List<BookNavItem>? parseNav(XmlElement nav, {bool withType = false}) =>
      parseList(query.child(nav, 'ol'), withType: withType);

  List<BookNavItem>? toc;
  List<BookNavItem>? pageList;
  List<BookNavItem>? landmarks;
  final others = <EpubNavList>[];
  for (final nav in query.descendants(document, 'nav')) {
    final type =
        splitProperties(attributeNs(nav, EpubNamespace.epub, 'type')) ??
        const <String>[];
    if (type.contains('toc')) {
      toc ??= parseNav(nav);
    } else if (type.contains('page-list')) {
      pageList ??= parseNav(nav);
    } else if (type.contains('landmarks')) {
      landmarks ??= parseNav(nav, withType: true);
    } else {
      others.add(
        EpubNavList(
          label: elementText(nav.childElements.firstOrNull),
          type: type,
          list: parseNav(nav),
        ),
      );
    }
  }
  return EpubNavigation(
    toc: toc,
    pageList: pageList,
    landmarks: landmarks,
    others: others,
  );
}

BookNavItem _parseLi(
  XmlElement li,
  EpubXmlQuery query,
  String? Function(String?) resolveHref, {
  required bool withType,
}) {
  final a = query.child(li, 'a') ?? query.child(li, 'span');
  final ol = query.child(li, 'ol');
  final href = resolveHref(a?.getAttribute('href'));
  final text = elementText(a);
  final label = text.isNotEmpty ? text : (a?.getAttribute('title') ?? '');
  return BookNavItem(
    label: label,
    href: href,
    subitems: ol == null
        ? null
        : [
            for (final sub in query.children(ol, 'li'))
              _parseLi(sub, query, resolveHref, withType: withType),
          ],
    type: withType
        ? splitProperties(
            a == null ? null : attributeNs(a, EpubNamespace.epub, 'type'),
          )
        : null,
  );
}

/// Reads an EPUB 2 NCX. A `navPoint` without a target takes the first
/// target below it, as `parseNCX` does.
EpubNavigation parseEpubNcx(
  XmlDocument document, {
  String Function(String href)? resolve,
}) {
  final query = EpubXmlQuery(document, EpubNamespace.ncx);
  // An empty href is no target, as `href ? … : null` reads in epub.js.
  String? resolveHref(String? href) => href == null || href.isEmpty
      ? null
      : decodeBookUri(resolve?.call(href) ?? href);

  String? firstNavigableHref(List<BookNavItem>? items) {
    if (items == null) return null;
    for (final item in items) {
      final href = item.href ?? firstNavigableHref(item.subitems);
      if (href != null && href.isNotEmpty) return href;
    }
    return null;
  }

  BookNavItem parseItem(XmlElement el) {
    final label = elementText(query.child(el, 'navLabel'));
    final href = resolveHref(query.child(el, 'content')?.getAttribute('src'));
    if (el.name.local == 'navPoint') {
      final points = query.children(el, 'navPoint');
      final subitems = points.isEmpty ? null : points.map(parseItem).toList();
      return BookNavItem(
        label: label,
        href: href == null || href.isEmpty
            ? firstNavigableHref(subitems)
            : href,
        subitems: subitems,
      );
    }
    return BookNavItem(label: label, href: href);
  }

  List<BookNavItem>? single(String container, String itemName) {
    final element = query.child(document.rootElement, container);
    if (element == null) return null;
    return query.children(element, itemName).map(parseItem).toList();
  }

  return EpubNavigation(
    toc: single('navMap', 'navPoint'),
    pageList: single('pageList', 'pageTarget'),
    others: [
      for (final list in query.children(document.rootElement, 'navList'))
        EpubNavList(
          label: elementText(query.child(list, 'navLabel')),
          type: const [],
          list: query.children(list, 'navTarget').map(parseItem).toList(),
        ),
    ],
  );
}
