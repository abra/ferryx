/// Notes shown over the page: foliate-js's `footnotes.js`. Whether a
/// link is a note reference, what kind of note its target is, and the
/// note's content laid out on its own.
library;

import '../document/content_document.dart';
import '../fonts/book_font_face.dart';
import '../layout/book_style.dart';
import '../layout/box_builder.dart';
import '../layout/box_tree.dart';
import 'section_preparer.dart';
import 'text_anchor.dart';
import 'text_book_source.dart';

/// How sure it is that a link opens a note (`isFootnoteReference`).
enum FootnoteReference {
  /// An ordinary link: follow it.
  no,

  /// It looks like one (raised, not a back link): show the block around
  /// its target, or follow it when there is none.
  maybe,

  /// The book says so (`epub:type` noteref, glossref, biblioref, or the
  /// matching ARIA role): show its target.
  yes,
}

const _refTypes = {'biblioref', 'glossref', 'noteref'};
const _refRoles = {'doc-biblioref', 'doc-glossref', 'doc-noteref'};

Set<String> _tokens(ContentDocument doc, int element, String name) {
  final value = doc.attributeOf(element, name);
  return value == null ? const {} : value.split(' ').toSet();
}

/// What [link], an `<a>` of the document [boxes] were built from, is.
FootnoteReference footnoteReferenceOf(
  ContentDocument doc,
  SectionBoxes boxes,
  int link,
) {
  final types = _tokens(doc, link, 'epub:type');
  final roles = _tokens(doc, link, 'role');
  if (roles.any(_refRoles.contains) || types.any(_refTypes.contains)) {
    return FootnoteReference.yes;
  }
  if (types.contains('backlink') || roles.contains('doc-backlink')) {
    return FootnoteReference.no;
  }
  bool isSuper(int element) =>
      element >= 0 &&
      doc.isElement(element) &&
      (doc.localNameOf(element) == 'sup' ||
          boxes.raisedElements.contains(element));
  final onlyChild = doc.elementChildCountOf(link) == 1
      ? _firstElementChild(doc, link)
      : -1;
  return isSuper(link) || isSuper(onlyChild) || isSuper(doc.parentOf(link))
      ? FootnoteReference.maybe
      : FootnoteReference.no;
}

int _firstElementChild(ContentDocument doc, int element) {
  for (final child in doc.childrenOf(element)) {
    if (doc.isElement(child)) return child;
  }
  return -1;
}

/// The kind of note [element] is (`getReferencedType`): `biblioentry`,
/// `definition`, `endnote`, `footnote`, `note`, or null.
String? referencedTypeOf(ContentDocument doc, int element) {
  final types = _tokens(doc, element, 'epub:type');
  final roles = _tokens(doc, element, 'role');
  if (roles.contains('doc-biblioentry') || types.contains('biblioentry')) {
    return 'biblioentry';
  }
  if (roles.contains('definition') || types.contains('glossdef')) {
    return 'definition';
  }
  if (roles.contains('doc-endnote') ||
      types.contains('endnote') ||
      types.contains('rearnote')) {
    return 'endnote';
  }
  if (roles.contains('doc-footnote') || types.contains('footnote')) {
    return 'footnote';
  }
  if (roles.contains('note') || types.contains('note')) return 'note';
  return null;
}

const _inline = {
  'a',
  'span',
  'sup',
  'sub',
  'em',
  'strong',
  'i',
  'b',
  'small',
  'big',
};

/// The block holding [target] (`extractFootnote`): up through inline
/// ancestors; at the body, the element after the target when it is a
/// block. -1 when there is none.
int extractFootnote(ContentDocument doc, int target) {
  var element = target;
  while (_inline.contains(doc.localNameOf(element))) {
    final parent = doc.parentOf(element);
    if (parent < 0) break;
    element = parent;
  }
  if (doc.localNameOf(element) == 'body') {
    final sibling = doc.nextElementSiblingOf(target);
    return sibling >= 0 && !_inline.contains(doc.localNameOf(sibling))
        ? sibling
        : -1;
  }
  return element;
}

/// A note's boxes, with the document they came from and its kind.
typedef FootnoteBoxes = ({
  ContentDocument document,
  SectionBoxes boxes,
  String? type,
  List<BookFontFace> fontFaces,
});

/// A note ready to lay out: its [content] (a section of its own whose
/// boxes are only the note) and [type] ([referencedTypeOf]).
class PreparedFootnote {
  const PreparedFootnote({required this.content, required this.type});

  final PreparedSection content;
  final String? type;
}

/// Parses and styles the section a note is in and boxes the note alone:
/// what `SectionPreparer.prepareFootnote` runs in an isolate. An `li` or
/// `aside` gives its contents, any other element itself. Null when
/// [anchor] finds nothing (or, with [extract], no block holds it).
Future<FootnoteBoxes?> prepareFootnoteBoxes({
  required String text,
  required String? mediaType,
  required String href,
  required Map<String, String> styleSheets,
  required List<String> defaultStyleSheets,
  required BookStyle style,
  required TextAnchor? anchor,
  bool extract = false,
  String? language,
  BookCssRewrite? rewriteCss,
}) async {
  final doc = parseSectionDocument(text, mediaType: mediaType);
  var element = anchor?.find(doc) ?? -1;
  if (element < 0) return null;
  if (extract) {
    element = extractFootnote(doc, element);
    if (element < 0) return null;
  }
  final (:styles, :fontFaces) = await resolveSectionStyles(
    doc,
    href: href,
    styleSheets: styleSheets,
    defaultStyleSheets: defaultStyleSheets,
    style: style,
    language: language,
    rewriteCss: rewriteCss,
  );
  final name = doc.localNameOf(element);
  return (
    document: doc,
    boxes: buildFragmentBoxes(
      doc,
      styles,
      element,
      contentsOnly: name == 'li' || name == 'aside',
      hyphenation: style.hyphenation,
    ),
    type: referencedTypeOf(doc, element),
    fontFaces: fontFaces,
  );
}
