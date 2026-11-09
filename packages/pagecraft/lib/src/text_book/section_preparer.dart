import 'dart:isolate';

import 'package:flutter/painting.dart' show Size, TextScaler;

import '../css/css_syntax.dart';
import '../css/style_resolver.dart';
import '../css/stylesheet_loader.dart';
import '../css/ua_stylesheet.dart';
import '../document/content_document.dart';
import '../container/book_url.dart';
import '../layout/book_fonts.dart';
import '../layout/book_image_cache.dart';
import '../layout/book_style.dart';
import '../layout/box_builder.dart';
import '../layout/box_tree.dart';
import '../layout/column_layout.dart';
import '../layout/inline_styler.dart';
import '../layout/paragraph_layout.dart';
import '../fonts/book_font_face.dart';
import 'document_normalizer.dart';
import 'footnotes.dart';
import 'text_anchor.dart';
import 'text_book_source.dart';

/// A section ready to be laid out at any page size: its boxes, styled
/// for one [BookStyle], and the cache keys of its images.
class PreparedSection {
  const PreparedSection({
    required this.index,
    required this.href,
    required this.document,
    required this.boxes,
    required this.imageKeys,
    this.fontFaces = const [],
  });

  final int index;
  final String href;

  /// The parsed section: what CFIs, links and search resolve against.
  final ContentDocument document;
  final SectionBoxes boxes;

  /// Image sources as the section writes them, to their cache keys.
  final Map<String, String> imageKeys;

  /// The embedded fonts its style sheets declare, for `BookFontLoader`.
  final List<BookFontFace> fontFaces;
}

/// Prepares sections: markup and style sheets are read here, on the UI
/// isolate (the book's files live here), then parsing, the cascade and
/// box generation run in a short-lived isolate, so a chapter never
/// blocks a frame. Style sheet texts are kept for the book.
class SectionPreparer {
  SectionPreparer(this.source);

  final TextBookSource source;
  final _sheetTexts = <String, String?>{};

  Future<PreparedSection> prepare(int index, BookStyle style) async {
    final section = await source.section(index);
    final sheets = await _sheetsFor(section);
    final defaults = source.defaultStyleSheets;
    final language = source.language;
    final rewriteCss = source.cssRewrite;
    // The result leaves the isolate without a copy (Isolate.exit).
    final (:document, :boxes, :fontFaces) = await Isolate.run(
      () => prepareSectionBoxes(
        text: section.text,
        mediaType: section.mediaType,
        href: section.href,
        styleSheets: sheets,
        defaultStyleSheets: defaults,
        style: style,
        language: language,
        rewriteCss: rewriteCss,
      ),
      debugName: 'pagecraft section $index',
    );
    return PreparedSection(
      index: index,
      href: section.href,
      document: document,
      boxes: boxes,
      imageKeys: {
        for (final src in boxes.imageSources)
          src: source.imageKey(section.href, src),
      },
      fontFaces: fontFaces,
    );
  }

  /// The note [target] points to, ready to lay out on its own (in a
  /// popup), or null when it cannot be found. With [extract] (a link that
  /// only looks like a note reference) the note is the block around the
  /// target, as foliate-js's `extractFootnote` finds it.
  Future<PreparedFootnote?> prepareFootnote(
    TextTarget target,
    BookStyle style, {
    bool extract = false,
  }) async {
    final section = await source.section(target.index);
    final sheets = await _sheetsFor(section);
    final note = await _footnoteInIsolate(
      section,
      sheets,
      source.defaultStyleSheets,
      style,
      target.anchor,
      extract,
      source.language,
      source.cssRewrite,
    );
    if (note == null) return null;
    return PreparedFootnote(
      content: PreparedSection(
        index: target.index,
        href: section.href,
        document: note.document,
        boxes: note.boxes,
        imageKeys: {
          for (final src in note.boxes.imageSources)
            src: source.imageKey(section.href, src),
        },
        fontFaces: note.fontFaces,
      ),
      type: note.type,
    );
  }

  /// The style sheets [section] may need, by resolved href: linked ones
  /// and the ones they import, found by a quick scan of the markup (the
  /// isolate's parse decides which of them apply).
  Future<Map<String, String>> _sheetsFor(TextSection section) async {
    final out = <String, String>{};
    Future<void> load(String href, int depth) async {
      if (depth > 8 || out.containsKey(href)) return;
      final text = _sheetTexts.containsKey(href)
          ? _sheetTexts[href]
          : _sheetTexts[href] = await source.readStyleSheet(href);
      if (text == null) return;
      out[href] = text;
      for (final import in _importsIn(text)) {
        await load(resolveBookUrl(import, href), depth + 1);
      }
    }

    for (final href in _linksIn(section.text)) {
      await load(resolveBookUrl(href, section.href), 0);
    }
    for (final import in _importsIn(section.text)) {
      await load(resolveBookUrl(import, section.href), 0);
    }
    return out;
  }

  static final _linkTag = RegExp(r'<link\b[^>]*>', caseSensitive: false);
  static final _attribute = RegExp(
    r'''([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
  );
  static final _import = RegExp(
    r'''@import\s+(?:url\(\s*)?["']?([^"')\s;]+)''',
    caseSensitive: false,
  );

  static Iterable<String> _linksIn(String markup) sync* {
    for (final tag in _linkTag.allMatches(markup)) {
      String? rel;
      String? href;
      for (final a in _attribute.allMatches(tag.group(0)!)) {
        final value = a.group(2) ?? a.group(3) ?? '';
        switch (a.group(1)!.toLowerCase()) {
          case 'rel':
            rel = value.toLowerCase();
          case 'href':
            href = value;
        }
      }
      if (href != null && (rel?.contains('stylesheet') ?? false)) yield href;
    }
  }

  static Iterable<String> _importsIn(String text) =>
      _import.allMatches(text).map((m) => m.group(1)!);
}

/// Parses a section's markup: XHTML (or HTML for `text/html`), and as
/// HTML when it is not well-formed XML, so a reader shows what a strict
/// parser would refuse.
ContentDocument parseSectionDocument(String text, {String? mediaType}) {
  try {
    return ContentDocument.parse(text, mediaType: mediaType);
  } on ContentParseException {
    return ContentDocument.parseHtml(text);
  }
}

/// Parses, styles and boxes one section: what [SectionPreparer] runs in
/// an isolate. A section that is not well-formed XML is read as HTML,
/// so a reader shows what a strict parser would refuse.
Future<
  ({
    ContentDocument document,
    SectionBoxes boxes,
    List<BookFontFace> fontFaces,
  })
>
prepareSectionBoxes({
  required String text,
  required String? mediaType,
  required String href,
  required Map<String, String> styleSheets,
  required List<String> defaultStyleSheets,
  required BookStyle style,
  String? language,
  BookCssRewrite? rewriteCss,
}) async {
  final doc = parseSectionDocument(text, mediaType: mediaType);
  final (:styles, :fontFaces) = await resolveSectionStyles(
    doc,
    href: href,
    styleSheets: styleSheets,
    defaultStyleSheets: defaultStyleSheets,
    style: style,
    language: language,
    rewriteCss: rewriteCss,
  );
  return (
    document: doc,
    boxes: buildSectionBoxes(doc, styles, hyphenation: style.hyphenation),
    fontFaces: fontFaces,
  );
}

/// The cascade of [doc]: the user agent's sheet, the book's defaults and
/// the section's own sheets ([styleSheets] holds their texts by resolved
/// href), then the reader's ([readerSheetSources]); and the fonts the
/// book's sheets embed.
/// First the document gets what the WebView reader's normalizer gives a
/// loaded section: the book's [language] and direction on its root,
/// then the code block class, which needs a second cascade. With
/// [rewriteCss] the book's CSS (sheets, `<style>`, `style`) is rewritten
/// first (`TextBookSource.cssRewrite`).
Future<({ComputedStyles styles, List<BookFontFace> fontFaces})>
resolveSectionStyles(
  ContentDocument doc, {
  required String href,
  required Map<String, String> styleSheets,
  required List<String> defaultStyleSheets,
  required BookStyle style,
  String? language,
  BookCssRewrite? rewriteCss,
}) async {
  normalizeLanguageAndDirection(doc, language: language);
  final bases = <String>[];
  final media = style.media;
  final transform = rewriteCss == null
      ? null
      : (String css) => rewriteCss(
          css,
          windowWidth: media.viewportWidth,
          windowHeight: media.viewportHeight,
        );
  final sheets = await loadDocumentStyleSheets(
    doc,
    documentHref: href,
    read: (h) async {
      final text = styleSheets[h];
      return text == null || transform == null ? text : transform(text);
    },
    baseHrefs: bases,
    media: media,
    transform: transform,
  );
  final resolver = StyleResolver(media: media, [
    CssSheetSource(
      CssStyleSheet.parse(cssUserAgentStyleSheet),
      CssOrigin.userAgent,
    ),
    for (final css in defaultStyleSheets)
      CssSheetSource(CssStyleSheet.parse(css), CssOrigin.author),
    for (final (i, sheet) in sheets.indexed)
      CssSheetSource(sheet, CssOrigin.author, baseHref: bases[i]),
    ...readerSheetSources(style),
  ]);
  final options = StyleResolverOptions(
    rootFontSize: style.rootFontSize,
    viewportWidth: media.viewportWidth,
    viewportHeight: media.viewportHeight,
    inlineStyleTransform: transform,
  );
  var styles = resolver.resolve(doc, options: options);
  if (markCodeLikeBlocks(doc, styles)) {
    styles = resolver.resolve(doc, options: options);
  }
  return (styles: styles, fontFaces: bookFontFacesOf(sheets, bases));
}

/// Starts laying [section] out as a column [width] wide for pages
/// [pageHeight] tall, after probing its images' sizes into [images]; the
/// task lays out the first [firstPages] pages before returning, so the
/// page the reader opens on is ready, and the caller finishes the rest
/// between frames ([ColumnLayoutTask.complete]).
Future<ColumnLayoutTask> startSectionLayout(
  PreparedSection section, {
  required double width,
  required double pageHeight,
  required BookStyle style,
  required BookFonts fonts,
  required BookImageCache images,
  TextScaler textScaler = TextScaler.noScaling,
  int firstPages = 1,
}) async {
  await images.probe(section.imageKeys.values);
  Size? sizeOf(String src) {
    final key = section.imageKeys[src];
    return key == null ? null : images.sizeOf(key);
  }

  final task = ColumnLayoutTask(
    section.boxes,
    width: width,
    pageHeight: pageHeight,
    bookStyle: style,
    text: TextLayoutEnvironment(
      styler: InlineStyler(bookStyle: style, fonts: fonts),
      imageSize: sizeOf,
      maxImageHeight: pageHeight,
      textScaler: textScaler,
    ),
  );
  // A page is decided once the column reaches past its bottom.
  task.advance(untilHeight: pageHeight * (firstPages + 1));
  return task;
}

/// Lays [section] out as a column [width] wide for pages [pageHeight]
/// tall: probes its images' sizes into [images] first.
Future<ColumnLayout> layoutSection(
  PreparedSection section, {
  required double width,
  required double pageHeight,
  required BookStyle style,
  required BookFonts fonts,
  required BookImageCache images,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await images.probe(section.imageKeys.values);
  Size? sizeOf(String src) {
    final key = section.imageKeys[src];
    return key == null ? null : images.sizeOf(key);
  }

  return ColumnLayout.layout(
    section.boxes,
    width: width,
    pageHeight: pageHeight,
    bookStyle: style,
    text: TextLayoutEnvironment(
      styler: InlineStyler(bookStyle: style, fonts: fonts),
      imageSize: sizeOf,
      maxImageHeight: pageHeight,
      textScaler: textScaler,
    ),
  );
}

/// Top level, so the isolate's closure holds only these values.
Future<FootnoteBoxes?> _footnoteInIsolate(
  TextSection section,
  Map<String, String> sheets,
  List<String> defaults,
  BookStyle style,
  TextAnchor? anchor,
  bool extract,
  String? language,
  BookCssRewrite? rewriteCss,
) {
  final text = section.text;
  final mediaType = section.mediaType;
  final href = section.href;
  return Isolate.run(
    () => prepareFootnoteBoxes(
      text: text,
      mediaType: mediaType,
      href: href,
      styleSheets: sheets,
      defaultStyleSheets: defaults,
      style: style,
      anchor: anchor,
      extract: extract,
      language: language,
      rewriteCss: rewriteCss,
    ),
    debugName: 'pagecraft footnote',
  );
}
