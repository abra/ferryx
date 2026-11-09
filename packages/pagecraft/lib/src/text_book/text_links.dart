import 'footnotes.dart';
import 'section_preparer.dart';
import 'text_anchor.dart';
import 'text_book_source.dart';

/// Where a tapped link goes (view.js's link handling).
sealed class TextLinkTarget {
  const TextLinkTarget(this.href);

  /// The link as the book resolves it.
  final String href;
}

/// Out of the book: a web address, mail: the reader asks before opening.
class ExternalTextLink extends TextLinkTarget {
  const ExternalTextLink(super.href);
}

/// Into the book: [target] to go to, or, by [reference], a note to show.
class InternalTextLink extends TextLinkTarget {
  const InternalTextLink(super.href, this.target, this.reference);

  final TextTarget target;
  final FootnoteReference reference;
}

/// Where link [link] (an `<a>` element of [section]) goes; null when its
/// `href` is missing or points nowhere in the book.
Future<TextLinkTarget?> resolveTextLink(
  TextBookSource source,
  PreparedSection section,
  int link,
) async {
  final written = section.document.attributeOf(link, 'href');
  if (written == null) return null;
  final href = source.resolveLink(section.index, written);
  if (source.isExternal(href)) return ExternalTextLink(href);
  final target = await source.resolveHref(href);
  if (target == null) return null;
  return InternalTextLink(
    href,
    target,
    footnoteReferenceOf(section.document, section.boxes, link),
  );
}
