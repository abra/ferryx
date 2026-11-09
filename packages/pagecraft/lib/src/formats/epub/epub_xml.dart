/// XML helpers shared by the EPUB parsers, with `epub.js`'s leniency:
/// namespaces are honoured only when the document uses them at all, and
/// text is stripped and collapsed the HTML way.
library;

import 'package:xml/xml.dart';

import '../../text/whitespace.dart';

/// EPUB namespaces.
abstract final class EpubNamespace {
  static const container = 'urn:oasis:names:tc:opendocument:xmlns:container';
  static const xhtml = 'http://www.w3.org/1999/xhtml';
  static const opf = 'http://www.idpf.org/2007/opf';
  static const epub = 'http://www.idpf.org/2007/ops';
  static const dc = 'http://purl.org/dc/elements/1.1/';
  static const dcterms = 'http://purl.org/dc/terms/';
  static const enc = 'http://www.w3.org/2001/04/xmlenc#';
  static const ncx = 'http://www.daisy.org/z3986/2005/ncx/';
  static const xlink = 'http://www.w3.org/1999/xlink';
}

/// Media types the parsers branch on.
abstract final class EpubMediaType {
  static const ncx = 'application/x-dtbncx+xml';
  static const xhtml = 'application/xhtml+xml';
  static const html = 'text/html';
  static const css = 'text/css';
  static const svg = 'image/svg+xml';
  static const package = 'application/oebps-package+xml';
}

/// The text of [element] stripped and collapsed, or empty for null
/// (`getElementText`).
String elementText(XmlElement? element) =>
    normalizeWhitespace(element?.innerText);

/// Child lookups in a namespace, or in no namespace when the document
/// never declares it (`childGetter`): books that forget the namespace
/// still open.
class EpubXmlQuery {
  EpubXmlQuery(XmlDocument document, this.namespace)
    : _useNamespace = _declares(document, namespace);

  final String namespace;
  final bool _useNamespace;

  static bool _declares(XmlDocument document, String namespace) {
    final root = document.rootElement;
    if (root.namespaceUri == namespace) return true;
    for (final attribute in root.attributes) {
      if (attribute.value == namespace &&
          (attribute.name.prefix == 'xmlns' ||
              attribute.name.local == 'xmlns')) {
        return true;
      }
    }
    return false;
  }

  bool _matches(XmlElement element, String name) =>
      element.name.local == name &&
      (!_useNamespace || element.namespaceUri == namespace);

  /// The first child element named [name] (`$`).
  XmlElement? child(XmlElement element, String name) {
    for (final child in element.childElements) {
      if (_matches(child, name)) return child;
    }
    return null;
  }

  /// The child elements named [name] (`$$`).
  List<XmlElement> children(XmlElement element, String name) => [
    for (final child in element.childElements)
      if (_matches(child, name)) child,
  ];

  /// Every descendant named [name], in document order (`$$$`).
  List<XmlElement> descendants(XmlNode node, String name) => [
    for (final element in node.descendantElements)
      if (_matches(element, name)) element,
  ];
}

/// [attribute] of [element] in [namespace], as `getAttributeNS` finds it:
/// a prefixed attribute bound to that namespace.
String? attributeNs(XmlElement element, String namespace, String attribute) {
  for (final a in element.attributes) {
    if (a.name.local == attribute && a.name.namespaceUri == namespace) {
      return a.value;
    }
  }
  return null;
}

/// [value] split on whitespace into a property list, or null when absent.
List<String>? splitProperties(String? value) =>
    value?.split(RegExp(r'\s')).toList(growable: false);
