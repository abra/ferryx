# pagecraft

The native Flutter reader engine used by Ferryx. One package opens a book
file, understands its format,
lays its pages out and draws them, and
reports positions, selections and taps back. The app embeds
its views (`TextPagesView`, `TextScrollView`, `FixedPagesView`); `pagecraft`
knows nothing about the app's domain models, repositories or blocs.

## Source in Ferryx

This directory is a source copy of `packages/pagecraft` from Readflex at
commit `99bedcfdd246d8570f89744034f098dec7312063`, copied from the local
Readflex project on 2026-11-09. Ferryx uses this package through
`path: ../../pagecraft` in `packages/features/viewer/pubspec.yaml`.
Its companion `native_text_selection` is kept in the neighboring directory.
Both packages can be edited and built here without a Readflex checkout.
The original tests, native sources, generated bindings and license notices
are included; build outputs and local caches are not source dependencies.
The local maintenance generators under `tool/` were copied as well.

The engine originally replaced Readflex's WebView and foliate-js reader.

foliate-js stays reference code, not a standard: the fork the app used is in
Readflex's history (the last revision with it is `fb4b4e5c`, under
`packages/reader_webview/assets/foliate-js/src`). The fixture recordings
below were made from it in Chromium and Node before it was removed; the
scripts that made them are in that revision too. Those JavaScript filenames
record historical fixture provenance, not commands required by the current
Dart/Flutter tests.

## Libraries

An app imports the formats it reads; release builds can drop unreachable
Dart code:

| Library | What it brings |
|---|---|
| `package:pagecraft/pagecraft.dart` | the core every format shares: ZIP, document model, CSS, layout, `TextBookSource` and the text page and scroll views, `FixedPageSource` and `FixedPagesView`, CFIs, search, progress, cover thumbnails |
| `package:pagecraft/epub.dart` | the core and EPUB: `EpubBook`, `EpubTextSource`, `readEpubMetadata` |
| `package:pagecraft/fb2.dart` | the core and FB2: `Fb2Book`, `Fb2TextSource`, `readFb2Metadata` |
| `package:pagecraft/mobi.dart` | the core and MOBI 6/KF8: `MobiBook`, `mobiTextSource`, `readMobiMetadata` |
| `package:pagecraft/comic.dart` | the core and CBZ: `ComicBook`, `ComicPages`, `readComicMetadata` |
| `package:pagecraft/pdf.dart` | the core and PDF: `PdfBook`, `PdfPages`, the text layer, `readPdfMetadata` |
| `package:pagecraft/djvu.dart` | the core and DjVu: `DjvuBook`, `DjvuPages`, hidden-text search/selection and `readDjvuMetadata` |
| `package:pagecraft/article.dart` | the core and saved articles: `ArticleTextSource`, anchors, search |
| `package:pagecraft/all_formats.dart` | all of them and `textBookSourceOf`, which picks a reflowable book's source by its type |
| `package:pagecraft/testing.dart` | fixtures for tests: archives, comics, MOBI files, PDFs built in memory |

Each format lives in one folder (`src/formats/<format>/`, articles in
`src/article/`) with its parser, its `TextBookSource` or page source and
its import metadata; the core imports no format and no format imports
another. `test/library_boundaries_test.dart` walks the import graph from
every library to keep it so. PDFium, the internal MOBI Rust backend and the
DjVuLibre C++ decoder are built/bundled even when a consumer imports only another
format. The DjVu native component has its own GPLv2-or-later license; see its
[upstream notice](native/djvu/upstream/COPYRIGHT) before distributing a build.
The Rust crate and library retain the name `pagecraft_mobi_native`; the MOBI
backend has no separate Dart package. See [native backend setup and maintenance](doc/mobi_native.md).

## Maintainer reading path

Read the public library for the format being changed, then follow its adapter
into the shared engine. The main paths are:

| Concern | Entry points and checks |
|---|---|
| Container and parser | [ZIP](lib/src/container/zip_archive.dart), `lib/src/formats/<format>/`; [container tests](test/container/) and [format tests](test/formats/) |
| Reflowable rendering | [TextBookSource](lib/src/text_book/text_book_source.dart) → [TextBookLayout](lib/src/text_book/text_book_layout.dart) → [TextPagesController](lib/src/text_book/text_pages_controller.dart) / [TextScrollController](lib/src/text_book/text_scroll_controller.dart) → their Flutter views; [text-book tests](test/text_book/) |
| Image pages | [FixedPageSource](lib/src/fixed_layout/fixed_page_source.dart) → [FixedPagesController](lib/src/fixed_layout/fixed_pages_controller.dart) / [FixedPagesView](lib/src/fixed_layout/fixed_pages_view.dart); [fixed-layout tests](test/fixed_layout/) |
| Public dependency boundaries | [Library graph test](test/library_boundaries_test.dart); format-specific imports must not pull in sibling formats |
| Native maintenance | [MOBI backend guide](doc/mobi_native.md), [build hook](hook/build.dart), [native/Dart parity tests](test/formats/mobi/mobi_native_reader_test.dart); PDF uses PDFium through `pdfrx_engine` |

Opening is format-specific, not a promise to stream every book: EPUB/CBZ read ZIP
entries on demand, MOBI reads records by offset (MOBI 6 then assembles the full
text stream), and FB2 reads and parses the complete XML file or ZIP entry.
Articles read and normalize their saved HTML in an isolate. PDF opening reads
page sizes and navigation; page bitmaps and text layers are requested later.
DjVu opens its self-contained document on a worker isolate, reads page headers
and navigation, and decodes page images and hidden text only when requested.
The host owns opened sources and controllers and must close/dispose them;
Pagecraft does not persist app reading history or preferences.

The text renderer currently accepts horizontal, reflowable content. Fixed-layout
EPUB/KF8 and vertical writing raise
[UnsupportedTextBookException](lib/src/text_book/text_book_support.dart).
`FixedPagesView` supports PDF/comic/DjVu page sources; it does not provide a
fixed-layout EPUB renderer. Pagecraft reports unsupported content to the host
and does not choose another engine. The CSS section below describes the
implemented subset rather than browser-complete CSS support.

## Modules

The former reader's modules map to these Pagecraft responsibilities; recorded
fixtures preserve the behavior that saved positions and content depend on.

| foliate-js | pagecraft | Responsibility |
|---|---|---|
| `vendor/zip.js` | `src/container/zip_archive.dart` | ZIP read in place: central directory once, entries on demand; ZIP64; stored and deflate |
| `comic-book.js` | `src/formats/comic/` | CBZ pages in the reader's order (`pageOrderVersion`), cover, title |
| (browser `naturalWidth`) | `src/image/image_dimensions.dart` | image size from PNG/JPEG/GIF/BMP/WebP headers, EXIF-rotated, without decoding |
| `readflex_page_content.js`, `readflex_page_geometry.js`, `readflex_page_colors.js` | `src/image/page_content.dart`, `src/formats/pdf/pdf_page_content.dart`, `src/fixed_layout/page_colors.dart` | ink box of a page sample, margin crop, theme colours for image pages |
| `pdf.js` (pdf.js) | `src/formats/pdf/` | `PdfBook` over pdfium (`pdfrx_engine`): page sizes, outline, Info dictionary, password; `PdfPageImage`/`PdfPageTile`/`PdfPageThumbnail`; `initializePdfEngine` |
| `epub.js`, `fb2.js`, `mobi.js` | `src/formats/epub/`, `fb2/`, `mobi/` | sections, table of contents, metadata, `resolveHref`, the format's `TextBookSource` |
| `getMetadata` in `book.js` | `src/metadata/`, each format's `*_metadata.dart` | `BookMetadata` for the library's import: title, author, cover as a small JPEG (`readEpubMetadata` … `readPdfMetadata`, `encodeCoverThumbnail`) |
| `epubcfi.js` | `src/epubcfi/`, `src/formats/pdf/pdf_anchor.dart` | CFI parse, range ↔ CFI, compare, fake CFIs, PDF text anchors |
| browser DOM and CSS | `src/document/`, `src/css/` | node tree with DOM child indices, CSS subset, cascade |
| browser layout | `src/layout/` | paragraph `TextSpan` trees laid out by `TextPainter`; blocks, images and tables as `RenderBox`es |
| `paginator.js`, `readflex_page_columns.js`, `view.js` navigation | `src/text_book/text_page_geometry.dart`, `text_book_layout.dart`, `text_pages_controller.dart`, `text_pages_view.dart` | column geometry, sections laid out near the reader, spreads, turns and jumps, positions, the page view |
| `fixed-layout.js`, `readflex_page_zoom.js`, image areas in `book.js` | `src/fixed_layout/` | spreads, orientation, RTL, `FixedPagesView` with zoom and tap arbitration, `FixedPagesController`, image areas, thumbnails |
| `overlayer.js` | `src/layout/text_page_highlights.dart`, `src/fixed_layout/` | highlights under text pages; highlights and image areas over fixed-layout pages |
| `search.js`, `text-walker.js` | `src/search/text_node_search.dart`, `src/text_book/text_book_search.dart`, `src/search/text_search.dart` | book search with the same folding, offsets and excerpts (`searchTextNodes`, `searchTextBook`); PDF text-layer search (`searchText`) |
| text layer of `pdf.js` | `src/formats/pdf/pdf_text_layer.dart` | `PdfTextLayer`: a box per character, words, sentences, search and text anchors on a page |
| `readflex_selection_normalizer.js`, `readflex_selection_context.js`, `readflex_range.js` | `src/text/selection_normalizer.dart`, `src/text_book/selection_context.dart`, `src/text_book/highlight_merge.dart`, `src/text_book/text_selection_details.dart` | a selection's whole words, sentence context and highlight merge: the payload text actions get |
| (browser `Intl.Segmenter`) | `src/text/sentence_breaks.dart` | Unicode sentence boundaries (UAX #29), as ICU gives them |
| (browser `hyphens: auto`) | `src/text/hyphenator.dart`, `hyphenation_patterns*.dart` | Liang's hyphenation over the TeX patterns (hyph-utf8) Android's hyphenator is built from: en (US, GB), ru, uk, de, fr, es, it, pt |
| `readflex_document_normalizer.js` | `src/text_book/document_normalizer.dart` | missing language/direction from metadata and text, the code block class |
| `progress.js` | `src/progress/` | section fractions, locations, time left, table of contents position |
| `footnotes.js`, link handling in `view.js` | `src/text_book/footnotes.dart`, `src/text_book/text_links.dart`, `src/layout/text_fragment_view.dart` | note references, note extraction and popups, internal and external links |
| `article-html/index.html`, `readflex_content_security.js` (the article shell) | `src/article/`, `src/text_book/text_scroll_controller.dart`, `text_scroll_view.dart` | a saved article: its markup cleaned, contents, sentence anchors, selection payloads and search; one scrolling column |

## Layers

`container`, `epubcfi`, `document` and the Dart EPUB/FB2/MOBI/comic parsers have no
`dart:ui` dependency: they run in isolates and are tested without a Flutter
binding. MOBI text-record I/O and decoding use the internal Rust crate in
`rust/`, through private bindings in `src/formats/mobi/native/`;
`formats/pdf/pdf_book.dart` talks to pdfium through `pdfrx_engine` and one
FFI call of its own; `formats/pdf/pdf_engine.dart` is the Flutter side of
that (loading the library the app bundles). DjVu's worker calls its bundled C++
decoder through Dart FFI; its text-layer model uses Flutter rectangles, as the
PDF text layer does. `metadata`, `layout`,
`text_book`, `fixed_layout` and the page views are Flutter and use the
framework's own primitives:
`TextPainter` metrics, `RenderBox` layout, `PageView` physics,
`SelectableRegion` handles, `ImageProvider`/`ImageCache`, `ChangeNotifier`
controllers. Layout and painting use Flutter directly, without an embedded
WebView or browser runtime.

## Containers

`ZipArchive.open(path)` parses the end-of-central-directory record (with
a trailing comment and ZIP64) and the central directory; `entries` are
plain data. `read(entry, maxBytes:)` inflates through `dart:io` zlib and
checks the inflated size against the directory; `readDetached(path, entry)`
does the same through a fresh handle for `Isolate.run`. Reads on one
archive are serialized because `RandomAccessFile` allows one pending
operation. Encrypted entries and methods other than stored/deflate are
listed but refused on read with `PagecraftException`. CRCs are not verified:
a damaged image fails to decode and a damaged chapter fails to parse, and
both are reported where they are used. Names use UTF-8 when the archive
flags it, otherwise UTF-8 if the bytes decode and CP437 if not.

## CFIs (`src/epubcfi`)

`cfi.dart` is the port of `epubcfi.js`: the same grammar, canonical
strings and ordering, so every anchor one reader saved resolves in the
other. `Cfi.parse` reads a string with or without the `epubcfi(...)`
wrapper in one pass over its code units into an immutable model:
`CfiLocation` (paths after each `!` indirection) or `CfiRange` (a shared
parent, then the start and the end), each path a list of `CfiStep`s with
index, id assertion, character offset, temporal and spatial offsets, text
assertions and side bias. `toString` writes the canonical form back
(offsets only on odd, character-data steps; reserved characters escaped
with `^`), `collapse` turns a range into its start or end, `compareTo`
orders anchors as `epubcfi.js` does (step by step, a missing step first,
offsets only at the last step, ranges by start then end) and
`buildCfiRange` joins two points into a range sharing their common steps.
Malformed strings throw `CfiFormatException`; `Cfi.tryParse` returns null.
Ten thousand saved anchors parse and sort in well under a second (test).

`cfi_resolve.dart` maps CFIs to positions in a document and back
(`cfiFromRange`, `cfiFromPoint`, `cfiToRange`, `cfiToElement`,
`cfisFromElements`) through `CfiNode`/`CfiDocument` (`cfi_node.dart`), the
slice of a tree CFIs need: elements and character data with children,
parent, id and attributes. Any format's tree implements it; the reader's
own `ContentDocument` does, and `XmlCfiDocument` wraps a `package:xml` tree
for XHTML, FB2 and package documents (one wrapper per node, ids indexed
once). Resolution follows the spec's indexing the way the browser did:
a parent's children read as `[element, text, element, ..., element]`, so
adjacent text nodes merge into one odd-numbered chunk with their offsets
summed, a missing chunk between two elements still takes a number, index
0 and n+2 are the virtual positions before and after the children, and
the last step's id assertion wins when the document has that element. A
`CfiNodeFilter` makes nodes transparent (`skip`: their children count as
the parent's, foliate-js#100) or invisible (`reject`), both for the path
and for the merged offsets. A step past the children throws
`CfiResolveException`. Points are `CfiPoint(node, offset)` as DOM range
boundaries: a character offset in text, a child index in an element.

Parity is recorded, not assumed: `test/fixtures/cfi/expected.json` holds
what `epubcfi.js` produced in Chromium for the fixture documents (every
text node at three offsets, ranges across neighbouring text nodes,
every element, `fromElements` over the body or spine, with and without a
filter), recorded by `cfi_fixtures.mjs` (see above).
The Dart tests replay the same positions and must match string for
string and node for node. Two things the browser does that the port does
not copy: a DOM `Range` whose end lands before its start collapses (the
fixtures record each end on its own), and `epubcfi.js` cannot address the
root's own children (head, body).

`fake_cfi.dart` keeps the fast path for sections without a spine
(`epubcfi(/6/N)`: comics, PDF pages), `pdf_anchor.dart` the PDF text
anchors described under PDF.

## EPUB (`src/formats/epub`)

`EpubBook` is the port of the `EPUB` class in `epub.js` without the
browser parts (blob URLs, media overlay playback). `EpubBook.open(path)`
reads the ZIP through `ZipEpubFiles`; `EpubBook.load(files)` takes any
`EpubFiles` (`MemoryEpubFiles` in tests). A file is looked up by its path
as `decodeURI` leaves it, then fully decoded (`fullyDecodedPath`): Calibre
writes `%26` in the manifest for a file named with `&`, and `epub.js`,
which stops at the first lookup, reads nothing for such sections. Opening follows `init()` step
by step: `META-INF/container.xml` names the first package document;
`META-INF/encryption.xml` lists obfuscated resources (`EpubEncryption`:
IDPF keys are the SHA-1 of the unique identifier without whitespace over
the first 1040 bytes, Adobe keys the first UUID identifier over 1024;
other algorithms are left encoded); `EpubResources` reads the manifest,
spine (`page-progression-direction`, `linear`, `properties`), guide and
the cover (the `cover-image` property, else the EPUB 2 `meta name="cover"`,
else the guide's cover page) and gives every itemref its spine CFI
through `cfisFromElements`; spine entries without a manifest item are
skipped but keep their CFI numbering. `sections` carry the container
path, uncompressed size, CFI, linearity, page spread and media overlay
item. The navigation document (`parseEpubNav`: toc, page-list,
landmarks, other navs with their headings; `a` or `span` labels with the
`title` fallback) wins over the NCX (`parseEpubNcx`: navMap, pageList,
navLists; a navPoint without a target takes the first one below); a
malformed navigation document is ignored, a malformed package or
container document fails the open. Landmarks fall back to the guide.
`parseEpubMetadata` reads Dublin Core elements and EPUB 3 `meta`
properties with `refines` (title types, file-as, alternate scripts,
roles with schemes, identifier types, subjects' terms and authorities,
collections), the EPUB 2 `opf:role`/`opf:file-as`/`opf:scheme`
attributes, `rendition:*` and `media:*` metas (durations as SMIL clock
values), and summarises them as `EpubMetadata` with contributors grouped
by MARC relator (`author`, `translator`, `illustrator`, ...). The
iBooks/Kobo display options set `rendition.layout` to `pre-paginated`
and give the first linear section a page spread when the book does not
open to a spread.

Hrefs are container paths resolved as `resolveURL` resolves them
(`resolveBookUrl`, `src/container/book_url.dart`, which every format's links and sheets resolve through): relative to the package document, the navigation
document or the section, with Calibre's `%2C`/`%3A` put back, the query
dropped and escapes decoded as JavaScript's `decodeURI` decodes them
(`decodeBookUri`: reserved characters stay encoded, so `ch%2C1.html` does
not find `ch,1.html`, as in the browser). `resolveHref` maps a path with
a fragment to a section index, `resolveCfi` maps a CFI to the section
its first path names (dropping an id assertion that is not an itemref,
the Epub.js bug `epub.js` works around), `readSectionText` and
`readResource` read on demand with fonts deobfuscated, `readCover`
returns the cover bytes, following a cover page to its image.

Parity is recorded as for CFIs: `test/fixtures/epub/expected.json` holds
what `epub.js` in Chromium made of the fixture publications under
`test/fixtures/epub/` (an EPUB 3 with refines, obfuscated fonts, a DRM
entry, a nested package directory, an encoded href, a non-linear item, a
ghost spine entry and media overlays; an EPUB 2 with NCX, guide cover and
legacy attributes; a fixed-layout book with display options), generated
by `epub_fixtures.mjs`.
The Dart tests replay the same files and compare sections, navigation,
metadata, manifest, cover and resolutions. One difference by design:
`epub.js` keeps `dc:publisher` under the same key a publisher role would
use; pagecraft keeps the string in `metadata.publisher` and roles in
`metadata.contributors`.

## FB2 (`src/formats/fb2`, `src/text/charsets.dart`)

`Fb2Book` is the port of `fb2.js`. `Fb2Book.open(path)` reads a `.fb2`
file or the first `.fb2` entry of a `.fb2.zip`/`.fbz` archive;
`Fb2Book.parse(bytes)` decodes by the XML declaration's encoding
(`decodeFb2Text`: UTF-8 by default, UTF-16 by byte order mark, and the
single-byte charsets FB2 files declare through `decodeCharset`:
windows-1251, windows-1252, koi8-r, cp866, iso-8859-5, latin1, as
tables generated from Python's codecs). The FB2 tree is converted into
the same XHTML `fb2.js` built: the conversion tables (`STYLE`, `SECTION`,
`POEM`, `TABLE`, `BODY`) are `_Rule` maps keyed by FB2 element name, each
giving the XHTML tag, the child table (or the current one) and the
attributes copied; every converted element keeps its `id` and gets the
FB2 name as its class, `a` becomes an anchor with the XLink href (and
`epub:type="noteref"` for notes), `image` becomes `img` whose `src` is a
`data:` URI for an inline `binary`, `stanza` lines become text and
`br`s. Elements the tables do not know are dropped with their subtrees,
as in the browser; prefixed FB2 names are matched by local name.

Opening reads the whole XML input and builds its tree in Dart, including inline
binaries. Sections serialize from that tree when requested; this is not
record-offset loading or Rust parsing.

The first body's top-level elements each become a section, every further
body one non-linear section with the `notesBodyType` class, each wrapped
in the former WebView reader's XHTML template (`Fb2Section.xhtml`, without the
stylesheet link) so saved CFIs resolve in the same elements. A section's
label is the first title, subtitle or paragraph, its direct subsections'
titles are numbered with `data-foliate-id` for `index#n` links, its size
is the document's bytes without image data. `metadata` follows
`book.metadata` (people as `Fb2Person` with `Last, First` sort names,
document-info people and `program-used` as `bkp` contributors, the
annotation as XHTML); `readCover` decodes the `coverpage` binary;
`resolveHref` returns `Fb2TocTarget` for `index#n` or `Fb2IdTarget` for
`#id`.

Parity is recorded as for EPUB: `test/fixtures/fb2/expected.json` holds
the browser's converted XHTML, metadata, sizes, table of contents and
resolutions for `rich.fb2` (every rule, nested sections, notes and
comments bodies, binaries, external and missing images) and
`cp1251.fb2`, recorded by `fb2_fixtures.mjs`. The Dart tests compare the XHTML as trees. Differences
by design: `fb2.js` loses `img` `alt`/`title` (its XML document does not
reflect the properties) and returns a nickname as a bare string, pagecraft
keeps the attributes and always a person; sizes differ by the stylesheet
link and serializer whitespace (checked within 200 bytes).

## MOBI and KF8 (`src/formats/mobi`)

`MobiBook.open(path)` is the port of `mobi.js`: `PdbFile` reads the Palm
database header and record offsets and serves records on demand from
the file (a 40 MB book costs its record table until a record is read);
`MobiContainer` parses record 0 (`MobiHeaders`: PalmDOC, MOBI, KF8 and
EXTH headers, as offset tables), moves to the KF8 part of a combined
file through the EXTH boundary record, and decodes text records: trailing
entries stripped by the trailing flags (read only when the MOBI header is
long enough to hold them: an old MOBI 3 header ends at 0xD0 and the bytes
at the flags' offset are its title, as Calibre reads it; a size past the
start leaves nothing, a size of 0 leaves the record whole, where
`mobi.js`'s `subarray(0, -0)` empties it), then PalmDOC or Huffman/CDIC
decompression in the [internal Rust backend](doc/mobi_native.md).
The native reader is opened lazily on the first text request, owns one file
handle and dictionary cache, and runs I/O/decoding on the FRB worker pool.
HUFF's 64 MiB dictionary budget covers packed and decoded entry payloads,
entry metadata and temporary recursive output. Each copied CDIC entry counts
even when offsets repeat; exceeding the budget reports a decoding error.
MOBI 6 uses `loadAllText()` for one batch; KF8 retains individual `loadText`
requests. `MobiContainer.close()` drains accepted reads and releases both
native and PDB resources, including when book opening fails. Resources come back deobfuscated and
inflated for fonts (`FONT` records, `dart:io` zlib) and without their
header for audio and video. Metadata is EXTH first, then the header's
title and locale language, with HTML character references decoded
(`unescapeHtml`, `src/text/html_entities.dart`); the cover is the EXTH
cover or thumbnail resource. The result is a `Mobi6Book` for version 6
files or a `Kf8Book` for version 8 and combined files.

The Dart `decompressPalmDoc` and `HuffCdicDecoder` implementations remain the
reference. `MobiContainer.open(pdb, useDartTextReader: true)` selects it for
parity/benchmarks; `--dart-define=PAGECRAFT_MOBI_USE_DART=true` selects it for a
diagnostic build. This is not an app-facing engine preference. The regular
`MobiBook.open(path)` API and source/UI contracts are unchanged. Rust is limited
to MOBI text bytes: XML/HTML parsing, EPUB/CBZ ZIP, FB2 and layout remain Dart;
PDF remains PDFium. Pagecraft's Flutter/Dart build hook bundles the Rust library;
development requires rustup with the toolchain pinned in `rust/rust-toolchain.toml`.

`Mobi6Book` reads all text records into one stream (as `mobi.js` must,
`filepos` offsets count bytes of the whole), splits it at
`<mbp:pagebreak>` tags into sections (the tags and the `filepos` values
are found by byte scans in `mobi6_markup.dart` that match `mobi.js`'s
regular expressions exactly; a Dart RegExp over a few megabytes of
Latin-1 text took most of the opening time), and gives each section's HTML with
an `<a id="filepos<n>">` anchor inserted at every referenced offset, the
offset string kept as written; an offset inside a tag anchors before the
tag (`mobiAnchorOffset`, as KindleUnpack does), where `mobi.js` breaks
the tag. A `filepos` is read as JavaScript's `Number` reads it, so a guide
reference without one (`filepos:null`) opens no section. The guide comes from the first section's
`<reference>` tags, the table of contents from the guide's `toc` page
nested by the indentation of `p` and `blockquote` ancestors, both parsed
with `package:html`. `Kf8Book` reads the FDST flow table and the skeleton
and fragment indexes (`readMobiIndex`: INDX/TAGX tag tables with control
bytes and CNCX strings), builds sections as skeletons with fragments
inserted at their offsets, loads raw text from whichever end of the
stream is nearer (`loadRaw`), serves `kindle:flow:`/`kindle:embed:`
resources, maps `kindle:pos:fid:X:off:Y` links to sections and to a
selector for the element at that position, reads the NCX index into the
table of contents, the guide index into landmarks, and the RESC record's
spine into page spreads; direction, fixed layout and the original
resolution come from EXTH.

Fixtures are built, not collected: `MobiBuilder` (`package:pagecraft/testing.dart`)
writes MOBI 6 and KF8 files record by record, including a PalmDOC
compressor, EXTH, trailing entries, INDX/TAGX index records and FDST,
and `test/fixtures/mobi/` holds its output (`mobi_fixtures_test` keeps
the files in step with the builder). `expected.json` records what
`mobi.js` made of them in Chromium (recorded by `mobi_fixtures.mjs`),
and the parity test compares metadata, every section's
document tree, sizes, navigation and link targets. Differences by
design: `mobi.js` gives the header's locale language as a bare string,
pagecraft always a list.

## Document tree (`src/document`)

`ContentDocument` is what the browser's DOM was to foliate-js: the
parsed section that layout, CFIs, search and highlights walk. It is an
arena, one index per node into parallel typed arrays (kind, parent,
first and last child, next sibling, child count, name, attribute
range), with names interned and attributes in two flat lists, so a
chapter costs a few hundred kilobytes and a walk allocates nothing;
`ContentNode` views (the `CfiNode` the CFI code needs) are created on
demand and cached, one per node, so identity holds for `CfiPoint`.
`parseXml` streams `package:xml` events (HTML5 entity mapping for
XHTML's `&nbsp;`, nesting validated, `ContentParseException` on bad
markup); `parseHtml` runs `package:html` for `text/html` sections and
MOBI 6 text, implied `html`/`head`/`body` included; `parse` picks by
media type. The tree keeps what CFIs see and what the browser kept:
elements and character data, text and CDATA as separate nodes, text
split by a comment as two nodes, no comments, no namespace
declarations; line breaks fold to LF, and XML attribute values are
normalized before their references are decoded (XML 1.0 §3.3.3): a
written line break or tab becomes a space, `&#xD;&#xA;` keeps its two
characters, as browsers keep them. In an HTML section a prefixed name
(`<svg:svg>`) is read by its local part, so the SVG is drawn where a
browser sees an unknown element. The corpus test hashes every section's
`ContentDocument` against the browser's tree, and the CFI fixture test
runs on both `XmlCfiDocument` and `ContentDocument`.

## CSS (`src/css`)

The styling engine the layout reads from, written against the CSS
specs rather than a browser's behavior, in layers:

- `css_tokenizer.dart` — CSS Syntax Level 3 §4: tokens with decoded
  escapes, typed numbers, `url()`, bad-string and bad-url tokens; never
  throws.
- `css_syntax.dart` — §5: `CssStyleSheet.parse` gives qualified rules
  (prelude + declarations) and at-rules (`@media` blocks hold rules,
  `@font-face` and `@page` hold declarations), with the spec's error
  recovery: a malformed declaration is dropped, a stray `}` joins the
  next prelude, a rule cut off by the end of input is kept.
- `css_selector.dart` — Selectors Level 3 as books use them, and the
  Level 4 parts WebKit and Chromium read: type, universal, class, id,
  namespace prefixes (`epub|type`, `*|`), every attribute operator (with
  `i`), the structural pseudo-classes (`:first-child`,
  `:nth-child(an+b)`, `:nth-of-type`, `:only-of-type`, `:lang()`,
  `:root`, `:empty` …), `:not()` with a list, `:is()` and `:where()`
  (forgiving lists, `:where` without specificity), `:has()` with
  relative selectors, `:link` and `:any-link` (every `href`: nothing is
  visited), all four combinators, selector lists, specificity;
  `::before` and `::after` select generated content, the other
  pseudo-elements and dynamic pseudo-classes parse and never match, an
  unknown selector drops its rule. Matching runs on `ContentDocument`
  indices without allocating.
- `css_media.dart` — media queries (Level 4: types, `not`/`only`,
  `and`/`or`, ranges, `min-`/`max-`, the `-webkit-` ratio features) and
  `@supports` (a declaration holds when pagecraft parses it, `selector()`
  when it parses the selector), against a `CssMediaEnvironment`: the
  window as foliate-js's paginated iframe showed it to the book, wider
  than any breakpoint (`min-width` holds, `max-width` does not) and
  landscape, with the screen for the device features, the colour scheme
  and reduced motion. Unknown types (`amzn-kf8`) and features do not
  match.
- `css_values.dart` — lengths (absolute units to px at parse time, `em`,
  `rem`, `ex`, `ch` and viewport units resolved at compute time,
  percentages kept), colors (named, hex, `rgb()`, `hsl()`, alpha,
  `currentcolor`), font family lists. Math functions (`css_calc.dart`,
  CSS Values 4 §10): `calc()`, `min()`, `max()` and `clamp()`, nested,
  with numbers, type-checked as they parse (`calc(1px * 2px)` is no
  length); a length that is one (`CssLength.calc`) has its relative
  units computed with the style (`CssLength.computedIn`) and its
  percentages left for the layout (`InlineStyler.px`), `min()` and
  `max()` of them too; a height with a percentage in it is no height,
  as a percentage height is not.
- `css_custom_properties.dart` — custom properties and `var()` (CSS
  Variables 1): `--name` keeps its tokens as written and inherits
  (`ComputedStyle.customProperties`; an element without its own shares
  its parent's set); references between them resolve, a cycle or
  `initial` makes them invalid; a declaration with `var()` waits
  (`CssPendingValue`) and is parsed when the element's custom
  properties are known, a shorthand's part by its longhand, `unset`
  when it does not parse.
- `css_properties.dart` — the supported longhands with their grammar,
  inheritance and initial value (boxes, fonts, text, lists, tables,
  `position` and its offsets, `border-radius`, `box-sizing`,
  `writing-mode`, `overflow-wrap`, `word-break`, `hyphens`, `content`,
  `quotes`, counters, `font-optical-sizing`, `background-image` with its
  size, repeat and position, `overflow-x`/`overflow-y`, and `width` as
  `min-content`, `max-content` or `fit-content` (`widthKeyword`, which
  tables size by and other boxes take as `auto`), the shorthands
  (`margin`, `padding`, `border*`, `border-radius`, `inset`, `font`,
  `background`, `text-decoration`, `list-style`, `overflow`, `break-*`)
  expanded into them, and the prefixed names
  books still use (`-webkit-hyphens`, `-epub-writing-mode`,
  `word-wrap` …) read as the standard ones; an invalid value drops the
  declaration, unknown properties are ignored. Flow-relative
  properties (`margin-inline-start`, `padding-block`,
  `border-inline-start`, `max-inline-size` …) parse as their physical
  ones and land on them in the cascade by the element's direction, so
  the later of a logical and a physical declaration wins.
- `computed_style.dart` and `style_resolver.dart` — the cascade:
  user-agent, user and author origins, `!important` reversing them,
  specificity and order, inline `style` above every author rule,
  presentational attributes (`align`, `width`, `bgcolor`, `<font>`,
  Kindle's `height`/`width` on paragraphs) below; `inherit`, `initial`,
  `unset`; `em` chains, keyword sizes, `bolder`/`lighter`, `line-height`
  numbers kept as factors; `@media` and `@supports` blocks by
  `css_media.dart`; `::before` and `::after` styles beside each
  element's (`ComputedStyles.before`, `after`), with `url()`s in
  `content` and `background-image` resolved against their sheet
  (`cssImageSource`). Rules are bucketed by their
  rightmost compound (id, class, type, universal), elements
  resolve in document order with their parent finished, and identical
  computed styles are interned (`ComputedStyles.distinctStyleCount`).
- `ua_stylesheet.dart` — the HTML standard's rendering rules, trimmed to
  the supported properties.
- `stylesheet_loader.dart` — the sheets a section asks for, in cascade
  order: `<link rel="stylesheet">`, `<style>`, `@import` inlined before
  the importing sheet, `media` attributes and import media evaluated in
  the reader's environment, cycles and depth bounded, external sheets
  cached per book (`StyleSheetCache`), an optional rewrite of each text
  (EPUB's, below); `cssFontFacesOf` lists `@font-face` sources for the
  font loader.

A section's cascade, as the WebView reader built it
(`resolveSectionStyles`): the user-agent sheet, the format's defaults
(fb2.js's sheet), the book's sheets with their `<style>` and `style`
attributes, then foliate-js's `getCSS` (`foliateStyleSheet`) and the
host's `customCSS` (`BookStyle.readerStyleSheet`) last in the author
origin, where foliate-js's `<style>` was. EPUB CSS is read as
foliate-js's `epub.js` rewrote it (`rewriteEpubCss`, which
`EpubTextSource.cssRewrite` hands the preparer): `-epub-` prefixes
dropped, `vw`/`vh` fixed to the window, every `px` turned into `em` at
16 px, so publisher sizes follow the reader's text size; MOBI and FB2
sheets are read as they are (`cssRewrite` null). Before style resolution,
`normalizeLanguageAndDirection` fills missing language and direction attributes
from book metadata and section text. After the first cascade,
`markCodeLikeBlocks` marks matching `div`, `p`, `section`, `article` and `li`
blocks by their class/id or monospaced code content; blocks inside `pre` are
already treated as code. Marking a block triggers another cascade.

Tests: a table per layer in `test/css/`, a fuzz test that mutates real
stylesheets 1500 times and tokenizes random code points, and the corpus
test resolves every section of every real book with its own sheets.
`benchmarks/pagecraft_document_benchmark_test.dart` times style resolution
beside parsing.

## Boxes (`src/layout/box_*.dart`, `text_source_map.dart`, `list_markers.dart`)

`buildSectionBoxes(document, styles)` turns a styled `ContentDocument`
into `SectionBoxes`, the layout's input, following CSS 2.1 §9.2 and CSS
Text 3 §4. Pure Dart like the document and the cascade, so the three can
run together in an isolate.

- A `BlockBox` holds blocks or paragraphs; inline content beside blocks
  goes into anonymous `ParagraphBox`es, a block inside an inline splits
  it. `display: none` and media elements make no box, `display:
  contents` passes its children up, list items carry their marker text
  (`start`, `reversed` and `value` honoured, `listMarkerText` for the
  counter styles), tables keep caption, header, body and footer rows and
  spans, block-level `<img>` and SVG cover wrappers become
  `ImageBox`es.
- Floats (CSS 2.1 §9.5): an element floated before a line's first
  content (a drop cap, a picture beside the text, a sidebar) leaves the
  flow as a `FloatBox` around its own box: an image, a table, or a block
  of its content (a float is blockified, even a `<span>`). An image
  floated inside a line ends its paragraph there; any other float inside
  a line stays in it. Floats beside a paragraph's first line do not take
  its indent away.
- A paragraph is flat: its text after white-space processing (collapsing
  across inline boundaries, line-start and line-end spaces dropped,
  segment breaks between CJK characters removed, `pre`/`pre-wrap` kept
  with tabs expanded to stops, `pre-line`, a trailing `<br>` making no
  empty line), `text-transform` with Unicode special casing, style runs
  that carry the enclosing link, `<q>` quotes by language, and atomics at
  U+FFFC: `InlineImage`, and `InlineText` for text raised or lowered by
  `vertical-align` (footnote references, exponents), laid out as its own
  small paragraph because a Flutter text span cannot shift its baseline.
- Generated content: `::before` and `::after` with strings, `attr()`,
  `counter()`, `counters()`, quotes (`quotes`, nested by depth, `<q>`
  through the user-agent sheet) and `url()` images, as inline text or a
  block of its own; counters (`counter-reset`, `-increment`, `-set`, the
  list-item counter) scoped as CSS Lists 3 scopes them, across tables
  too; `list-style-position: inside` markers in the text.
- Inline boxes: an inline element's padding, border, margin and
  background (`InlineDecoration`, with `InlineSpacer`s taking the
  horizontal room in the line), `position: relative` offsets, and empty
  sized inline elements (`InlineBox`).
- Inline blocks (`display: inline-block` around inline content): an
  `InlineText` with `isInlineBlock`, its content a paragraph of its own,
  laid out at its width (or shrunk to fit the line), inside its padding,
  border and margins, its background and border painted as one box, on
  the line's baseline by its last line (CSS 2.1 §10.8.1), raised by
  `vertical-align` as text is. One around block-level content stays
  inline content. Images inside raised text and inline blocks are drawn
  too (`ParagraphLayout.images`).
- Hyphenation: text with `hyphens: auto` (foliate-js's prose rule with
  the reader's hyphenation on, or the book's own) gets U+00AD at each
  break of its words (`Hyphenator` for the language of the nearest
  `xml:lang` or `lang`, the book's on the root; words of five letters
  or more, the limits of `TextHyphenation`). The soft hyphens are not
  the document's: the source map skips them and `ParagraphBox.plainText`
  (copy, dictionary, translation) drops them.
- `TextSourceMap` maps every paragraph offset to a document node and
  offset and back, through collapsed, dropped, transformed and generated
  text: what CFIs, selection, highlights and search use.

`inline-block` around block-level content is laid out as inline
content. The corpus test checks that every visible
character of every real book reaches a paragraph through the source
maps; the census (`test/corpus/corpus_census_test.dart`) lists the CSS
and markup the corpus uses that pagecraft drops.

## Text layout (`src/layout`, `src/text_book`)

How a reflowable section reaches the screen:

1. `TextBookSource` (`EpubTextSource`, `Fb2TextSource`, `Mobi6TextSource`,
   `Kf8TextSource`, `mobiTextSource(book)`, or `textBookSourceOf(book)` from `all_formats.dart`) gives sections as
   markup, style sheets and images; FB2 gets fb2.js's built-in style
   sheet (`fb2StyleSheet`), MOBI 6 images are `recindex:N`, FB2 images
   `data:` URIs.
2. `SectionPreparer.prepare(index, bookStyle)` reads the markup and the
   style sheets it links or imports (cached for the book), then parses,
   cascades and builds boxes in a short-lived isolate
   (`prepareSectionBoxes`): nothing of it runs on the UI isolate. A
   section that is not well-formed XML is read as HTML.
3. `layoutSection` (or `ColumnLayout.layout`) probes the section's image
   sizes into a `BookImageCache` and lays the boxes out as one column of
   the page's width: CSS block layout with margin collapsing, padding,
   borders and backgrounds (`ColumnDecoration`), set widths and auto
   margins, list markers outside the content on the first baseline,
   block images fitted to the column and the page (SVG covers to the
   whole page), floats, `box-sizing`, rounded
   corners and every border style (`paintColumnDecoration`), tables by
   CSS's automatic layout (columns between their widest word and their
   content on one line, the table as wide as that, its set width or its
   intrinsic `width` keyword, within `min-width` and `max-width`;
   `rowspan` and `colspan` on the HTML grid, the separated model with
   `border-spacing` and the table's own padding and border, the
   collapsed model with CSS 2.1's border conflict resolution, captions
   on either side, row and row-group backgrounds; rows that never
   split, cells to the row's height with `vertical-align`). A table fits
   its containing block, its columns narrower than their words when they
   must, unless it scrolls (`overflow-x: auto` or `scroll`, not inside
   another table): then it is never narrower than its words and may be
   wider than the column, from the containing block's start edge, and a
   `ColumnScroller` (`src/layout/column_scroller.dart`) over its items
   and decorations scrolls it sideways inside the column, its caption
   left in place. The scroll only moves `x`: items keep their laid-out
   rects, so pages, positions, CFIs and search, which go by `y`, never
   change with it; painting, taps, highlights and selection apply it and
   clip to the scroller's viewport, and a selection edge scrolled out of
   it has no handle. The offset belongs to the column, shared by every
   page that shows it. Each paragraph is a `ParagraphLayout`: a
   `TextPainter` over the paragraph's runs (`InlineStyler` maps computed
   styles to `TextStyle`s, cached by style identity), with placeholder
   spans for images, raised text (`<sup>`, `<sub>`: their own small
   paragraph, raised by a third of the parent's font size as browsers do)
   and the first-line indent. Line tops come from full-line selection
   boxes, because `LineMetrics.height` leaves out the strut. Flutter
   breaks a line at a soft hyphen but draws nothing there, so the
   paragraph decides its hyphens line by line as a browser does, on a
   start-aligned layout whose lines keep their natural widths: a soft
   hyphen at a line end fits when its line and a hyphen (`-`, measured
   once per style) do, and becomes a hyphen with no new layout (same
   length, so offsets hold); one that does not fit gives way to the last
   soft hyphen, space or dash of the line that fits, found from the caret
   positions, and only the lines after it are laid out again. Then the
   paragraph is laid out with its own alignment and checked (a hyphen
   that no longer ends the line it was shown for is disabled, U+2060,
   and the lines after it decided again); `TextHyphenation.maxLines`
   caps hyphenated lines in a row (`-webkit-hyphenate-limit-lines`);
   `hyphens: none` text never breaks at a book's `&shy;`. Line starts
   come from the line metrics and one caret query a line
   (`getLineBoundary` computes every line's metrics on each call). In
   the benchmark's worst case (long words in a narrow column, nearly
   every line hyphenated) a hyphenated chapter lays out in 2.9× the
   time and boxes in 1.3–1.8×.
   Under `glyphLineBoxes` a line is as tall as WebKit makes it under
   foliate-js's `-webkit-line-box-contain: block glyphs replaced`: the
   union of the strut and the ink of the glyphs the line has (`FontInk`,
   each glyph's top and bottom read from the TrueType outlines, as
   Flutter does not tell them). Only styles whose line height is short of
   their font's ink pay for it (headings at 1.12, not prose): a run takes
   the height its own characters need, and a run over several lines is
   cut where they break and laid out once more, so each line holds only
   its own glyphs ("Для кого" without descenders is 2 px shorter than
   "Структура" on iOS, as in the WebView).
   A long chapter is laid out incrementally: `ColumnLayoutTask` keeps
   the open blocks on an explicit stack, so `advance(budget:,
   untilHeight:)` stops after any paragraph and resumes later, and
   `complete(slice:)` finishes between frames; `startSectionLayout`
   returns once the first page is decided (about a millisecond on a
   debug simulator, against 10–150 ms for a whole chapter).
4. `paginateColumn` cuts the column into `ColumnPage`s at its break
   opportunities: block tops, line tops within orphans and widows, rows;
   `page-break-before/after: always` force a break, headings and
   `page-break-inside: avoid` make breaks second choice. A page never
   ends inside a line or an image. At a break between blocks, forced or
   not, the margins are truncated, as CSS Fragmentation truncates them: a
   page ends with the content above (`ColumnBreak.fit`), the next starts
   at the block below, and the margins after a section's last content
   take no page of their own (`ColumnLayout.contentHeight`). On a column still being laid out it
   returns only the pages already decided, which never change.
5. `TextColumnPage` paints one page (`paintColumnPage`: the slice of the
   column, clipped, in its own layer); images are decoded by
   `BookImageCache` at the width they are drawn and repaint the page when
   ready, within a byte budget.

Positions (`src/text_book/text_locator.dart`, `src/progress`):
`TextLocator` answers, for one laid-out section, what is shown first at a
height (`pointAt`: the start of the first whole line, or a block image),
where a document point or an anchor is (`yOf`, `yOfAnchor`: the top of
its line, or of the first content inside an element), and both ways for
CFIs (`cfiAt`, `yOfCfi`): full book CFIs, the section's own (`sectionCfi`:
the spine item's, or foliate-js's fake one for FB2 and MOBI) joined with
the path in the section's `ContentDocument`, which `PreparedSection`
keeps for this. `pageAtY` finds a page by height. `SectionProgress` is
foliate-js's `progress.js` (fractions by section size, 1500-byte
locations, time left, and the inverse for `goToFraction`), checked
against values `progress.js` computes; `TocProgress` is its
`TOCProgress`, with table of contents targets resolved through the
source's `resolveHref` into `TextAnchor`s (an id, an attribute value for
FB2 titles, a selector for KF8 positions) and found in the documents.

Selection (`src/layout/text_page_selection.dart`, `src/document/text_point.dart`,
`src/text_book/selection_context.dart`): inside a `SelectionArea` or
`SelectableRegion` each paragraph shown on a `TextColumnPage` registers as
a `Selectable` (`PageParagraphSelectable`, the lines whole on that page),
so selection keeps Flutter's range, gesture and keyboard contracts, as
`Text` does: word on long press, words while dragging (the
pressed word stays selected when the drag goes back), select all,
character, word and line extension from the keyboard. After the initial pointer
releases, `TextNativeSelectionGeometry` maps visible cells and exact ranges to
system iOS/Android controls through `native_text_selection`. Native boundary
updates go through the same selection events and source maps. The application's
action menu stays Flutter; unsupported native geometry uses Flutter's handles
and magnifier. Each page is its
own `SelectionContainer` (`PageSelectionDelegate`): its paragraphs are
ordered by document, not by where they sit, and the copied text has a
line break between paragraphs. `RenderTextColumnPage.selection` gives the
selection as document points (`TextPoint`: a text node and an offset, or
before or after an element such as an image or a footnote number) and
the text as shown, raised text included and images left out;
`selectionBounds` is where a menu goes. `TextPoint`s order as DOM
boundaries do and convert to and from the DOM boundaries CFIs are made of.
`TextSelectionDetails.of` builds what the WebView reader sends for a
selection: full CFIs of the selection and of its whole-word expansion
(`normalizeTextRange`), the selection kind, the sentence around it with
the selection marked (`buildSelectionContext`, bounded to the block and
2048 characters a side), and what saving it as a highlight absorbs
(`planHighlightMerge`). Sentences come from `sentenceBreaks`, a port of
Unicode's default sentence rules; the JS gets them from ICU through
`Intl.Segmenter`, and a fixture of ICU's own answers checks them.

Highlights (`src/layout/text_page_highlights.dart`): a `TextHighlight`
is an id, a `TextPointRange` of the section's document and a colour with
its alpha. `TextColumnPage` takes them with the `document` and paints
them under the text, in list order (later on top), so the text stays as
dark and crisp as around it; for solid text on a solid background this is
what the WebView reader's translucent tint with `multiply` (light themes)
or `lighten` (dark themes) gives, without blend modes, which Impeller
does not do through layers. `placeHighlights` finds each one's part in
each paragraph the page shows (a point inside raised text takes its whole
character); `RenderTextColumnPage.highlightAt` answers which highlight a
tap is on (the topmost) and `highlightRects` where one is drawn, for its
menu. Search hits and the selection's colour preview are highlights too.

Search (`src/search/text_node_search.dart`, `src/text_book/text_book_search.dart`):
`searchTextNodes` is `search.js` as the reader calls it (`simpleSearch`,
case and diacritics ignored): each character and its combining marks
fold to a lowercase base letter (`normalizeSearchText`), matches are
found with `indexOf`, overlapping ones included, and offsets map back to
the text nodes through the folds that changed a length; excerpts keep 50
characters of the first and last matching text nodes. The committed
`search_fold_table.dart` and `test/fixtures/search_fold.json` were historically
generated from Node/ICU by `tool/search_fold_table.mjs` to preserve the original
Unicode folding behavior. The generated header records the toolchain versions;
the generator name is provenance, not a maintained development command.
Dart tests compare every code point up to U+2FFFF with the committed reference,
without running JavaScript. Turkish and
Azerbaijani documents lowercase I and İ their way. `searchTextBook`
streams a whole book as `view.search` does: each section's hits in
batches of 64 (full CFIs and excerpts), progress after each section,
then done; sections are parsed and searched in background isolates,
three at a time, and reported in order; text in `script` and `style` is
skipped. On the simulator (debug) the CSS Definitive Guide's 29 sections
give 26 999 hits for "the" in 0.48 s, the first after 17 ms.

Links and notes (`src/text_book/text_links.dart`, `footnotes.dart`):
`RenderTextColumnPage.linkAt` gives the `<a>` under a tap (glyphs take a
few pixels of slop, a raised note number answers for its link).
`resolveTextLink` resolves its `href` as the book does
(`TextBookSource.resolveLink`: relative to the section for EPUB) into an
`ExternalTextLink` (the reader asks before opening it) or an
`InternalTextLink` with its `TextTarget` and a `FootnoteReference`: `yes`
when the book declares a note reference (`epub:type` noteref, glossref,
biblioref or the ARIA roles), `maybe` when it is raised and not a back
link (`isSuper`: `sup`, or an element the box builder saw raised,
`SectionBoxes.raisedElements`), `no` otherwise. `SectionPreparer.prepareFootnote`
boxes the note alone in an isolate (`buildFragmentBoxes`): an `li` or
`aside` gives its contents, so a footnote aside the chapter hides still
shows and an endnote has no list marker; for `maybe` the note is the
block around the target (`extractFootnote`), and null means follow the
link instead. `referencedTypeOf` names the note's kind.
`TextFragmentView` lays a note out at the width it gets and scrolls when
it is long.

Embedded fonts (`src/fonts`): preparing a section collects the
`@font-face` rules of the sheets it uses (`PreparedSection.fontFaces`,
each with the href its URLs resolve against). `BookFontLoader` reads a
family's faces through the book's source (EPUB fonts de-obfuscated, KF8
font records decoded), takes the first source of each that the engine
can load (`sfntOf`: TrueType, OpenType and collections as they are,
WOFF 1.0 unpacked; WOFF2 needs Brotli and falls back), and registers the
family's files as one engine family named after their content
(`EngineFontRegistry`): Flutter cannot unregister a font, so each set of
files is registered once per process and reopening a book costs nothing.
`loader.families` goes into `BookFonts.withBookFamilies`; a family that
cannot be read is left to the fallback chain, as a browser leaves it. The
engine picks a face's weight and style from the files themselves.

Pages (`src/text_book/text_page*.dart`, `text_book_layout.dart`):
`TextPageGeometry.of` cuts a viewport as the WebView paginator does
(`pageColumnLayout`, checked against `readflex_page_columns.js` on 120
cases): the side margin share widened as foliate-js widens its gap,
columns kept at the reader's measure, Auto showing a spread only in a wide
landscape window. `TextBookLayout` prepares sections (a few kept), loads
their fonts, lays the sections near the reader out (first pages at once,
the rest in 6 ms slices between frames) and drops the others; a new
geometry, style, font or text scale lays out again.
`TextPagesController` is the model behind the view and works without
it: it shows a spread (one page per column), turns across sections
(skipping `linear="no"` ones as view.js does), jumps by CFI, fraction,
target, href or section, and reports a `TextPagePosition` (section,
spread, spread count once known, the CFI of what is shown first,
`SectionProgress` numbers with the spread as foliate-js's page, and the
table of contents entry whose anchor is not after the end of what is
shown). The position is kept as that CFI, so rotation, a style change or
newly loaded fonts land on the same text. Operations run one at a time;
neighbouring sections are laid out ahead so a turn never waits.
Before the first spread, the controller resolves page progression using the
Readflex content fallback previously added to foliate-js: declared RTL, then
an RTL book language, then the majority of RTL versus Latin letters in body
text sampled across the linear reading order. LTR metadata does not prevent
predominantly Arabic content from resolving to RTL. At most 12 sections are
sampled, with a 512 KiB section limit and a 2 MiB total budget; parsing and
counting run in an isolate. Unreadable samples are skipped. An explicit
`TextPagesController(rtl: ...)` overrides inference. The result is stable for
the session and independent of the app locale and each paragraph's CSS
direction; changing appearance does not repeat the scan.
`TextPagesView.pageTurnAnimation` selects `PageTurnAnimation.slide` or `cover`
(the default), independently of `axis`. Slide moves both spreads; Cover moves
the incoming spread over a stationary page, with an opaque background and a
shadow at its leading edge. Swipes along either axis follow the finger (a swipe
further than a quarter of the view or a fling turns); a cancelled swipe
returns the incoming spread off screen. The same transition animates the
controller's turns (not under reduced motion),
gives taps to links, then highlights, then the reader as view fractions,
and is a selection area whose taps and swipes still reach the view. Stable
clipping wrappers keep selection render objects in place; tracked
highlight rectangles are clipped to the part of the current page still visible.
Selection handles are hidden during a turn and restored when it settles,
including when a short swipe returns to the same page. Reduced motion skips
the completion animation after a swipe as well as controller turns.
A swipe that starts on a table that scrolls scrolls it, and on after a
fling with the platform's scroll friction (`ScrollerDrag`), unless the
table is already at its edge that way: then it turns the page; with
pages turning up and down, sideways drags on tables are theirs alone
(`ScrollerDragRecognizer`, which enters the gesture arena only on a
table). A selection follows the reader through the section, as the
WebView reader's did: a turn by one spread (a swipe, the controller, or
a tap `onSelectionTap` turns into, the reader's edge zones) keeps the
boundary behind the reader and takes the other edge onto the new spread,
to the end of its first line (or, turning back, the start of its last
line); turning back toward the boundary takes the spread whole, and on
the boundary's own spread the selection ends at it. The edges are moved
with the selection area's own `SelectionEdgeUpdateEvent`s, as a dragged
handle moves them (`RenderTextColumnPage.selectionEdgeAt`, `lineEdge`),
so Flutter's selection handles stay on them; the reported
`TextPagesSelection` spans every page turned over and its text has the
paragraphs' line breaks. Moving the edge the selection came in by
starts it over on the page; another tap, a jump or another section
clears it. The area drops a selection when one of the view's gestures
wins over its own tap after a finger rested (Flutter's tap-and-drag
recognizer cancels into `clearSelection`): the view defers that to the
gesture, which turns with the selection, selects it again where it was,
or clears it. On the simulator (debug) a Reynolds FB2 shows its first
spread 60 ms after the controller is created.

The reader's settings are a `BookStyle` (font scale, family, weight,
letter spacing, line height, paragraph spacing, indent, colours,
justification, the three override switches foliate-js has, and the
host's own CSS). What plain CSS carries goes into `foliateStyleSheet`
(foliate-js's `getCSS`: letter spacing, the body's margins, `pre`
wrapping, footnote asides hidden, `li > p` unindented, heading line
height, the colour override: the text colour on `html`, inherited by
everything in the body with backgrounds cleared and borders in the text
colour, at the low specificity foliate-js gives it, and what still does
not read on its background (under 4.5:1) takes the reader's colour as
the WebView's contrast guard repairs it (`contrast_guard.dart`); the
family on the
elements foliate-js's typography reset lists, so `code`, `pre`, `kbd`
and `samp` keep theirs; the body weight on `p`, `li`, `blockquote`, `dd`
and `font`);
`BookStyle.readerStyleSheet` follows it, as foliate-js's `customCSS`
follows its own rules, so the host's link, heading, quote and code
colours and sizes win. Both come after the book's sheets in the author origin
(`readerSheetSources`), where foliate-js's `<style>` was: a book's
`!important` rule of higher specificity beats them, as in the WebView. What foliate-js writes with `:has()` and
`!important` on body text is applied by the layout to prose paragraphs
(`ParagraphBox.isProse`): line height (in whole pixels, cut down, as
WebKit's, under `wholePixelLineHeights`), indent, paragraph spacing,
alignment (centred and right-aligned text keep theirs) and the weight of
a prose `div` (bold keeps its own). A font with an optical size axis
(Literata's `opsz`) is drawn at its size, as browsers draw it under
`font-optical-sizing: auto` (Flutter keeps the default instance: at
opsz 12 Literata sets 0.3 % wider than at 21 px, enough to move line
breaks against the WebView). `BookFonts` maps CSS
families to the families the host registered: generics, embedded fonts,
a symbol fallback.

A change of style, fonts or page size lays the book out again (a style
the cascade sees prepares its sections again). The old layouts are
retired, not disposed: the view keeps the page it shows until the new
spread is ready, and the controller releases them after the next frame,
so a change never flashes a blank page.

Two Flutter details the layout depends on: a paragraph is laid out with
`minWidth` equal to its width (otherwise `TextPainter` shrinks to its
text and centred, right-aligned and RTL lines move to the left edge),
and its placeholder span overrides `debugAssertIsValid` (the framework
asserts that only `WidgetSpan`s reach a painter).

Floats are placed at their side of the containing block where they were
met: as high as the next line, never above an earlier float, beside the
floats already there or below them where they do not fit; a set width,
or shrink-to-fit (the content's widest line where it fits). The lines
that start beside a float are shortened (`LineExclusions`): a paragraph
beside floats is laid out in bands, each over the rest of its text at
the width the floats leave, keeping the lines that start beside them —
the band's painter goes on past them, so a justified band stays
justified to its last line, and the rest is clipped. It stays one
`ParagraphLayout` with the paragraph's offsets, so selection, CFIs,
highlights and search do not see the bands; with nothing beside it a
paragraph is one band, as before. Less than two ems beside the floats
takes no text: the lines move below them. `clear` moves a block below
the floats it names; images and tables go below the floats over them;
the section holds its floats, and a float or a table cell lays its
content out with floats of its own. A page does not break beside a
float when it can break elsewhere.

A block's background image (`ColumnDecoration.backgroundImage`) is
drawn in its padding box under its content: `backgroundTiles` sizes it
(`cover`, `contain`, a width or height keeping the ratio), places it
(a percentage puts that point of the image at that point of the box)
and repeats it across and down from there, the visible tiles only. As
in foliate-js, the reader's colours take a book's background colours
away, not its images. Inline elements' background images are not
drawn yet.

SVG is drawn as images are: an `<img>` of an SVG file and an `<svg>` in
the markup (written out as a document of its own, a `data:` image) are
sized from their `width`, `height` and `viewBox`
(`probeImageDimensions`) and drawn by `flutter_svg` at the width they
take on the page (`BookImageCache`, sharp at any size); an `<svg>`
around one `<image>` is that image, as before.

Formulas (MathML, `math_layout.dart`): a `<math>` is an `InlineMath`
atomic of its line (`display="block"` a centred line of its own), its
elements a `MathNode` tree (annotations left out), its text the
`alttext` or its characters for copying and search. `MathLayout` sets
it as browsers do after TeX: identifiers of one letter italic, operators
spaced by kind (thick around relations, medium around binary operators,
none for a sign, thin after punctuation, none in scripts; `lspace` and
`rspace` override), fractions on the math axis with TeX's minimum
shifts, scripts one level smaller (0.71, never below 0.55 of the root)
raised and lowered apart from each other, large operators larger with
their limits above and below in display style and beside them in text,
fences stretched to what they enclose, radicals drawn as a stroke with
an index over the hook, `munder`/`mover` with accents close, `mtable`
centred on the axis, `mfenced`, `menclose`, `mphantom`, `mstyle`'s
display style, script level and size. Glyphs are the paragraph's font,
then the platform's math fonts (STIX Two Math, Cambria Math, Noto Sans
Math); bars, radicals and enclosures are drawn in the text colour. As
in foliate-js, the reader's colours leave formulas and pictures alone.

v1 leaves out negative (hanging) indents, `inline-block` around
block-level content and floats inside a line (other than images).

## Articles (`src/article`, `text_scroll_*.dart`)

A saved article is one `content.html` the import writes (blocks with an
`id` and `data-rf-block-id`, each sentence in a span with its own id and
`data-rf-sentence`, headings `section-N`, pictures under `images/`), read
as a text book of one section (`ArticleTextSource`) and shown as one
column that scrolls (`TextScrollController`, `TextScrollView`). It
replaces the WebView article shell and keeps what that shell stored:

- **Markup** — `articleDocumentHtml` cleans it as the shell's DOMPurify
  call did: its tag and attribute allow-lists (`data-*` kept), scripts,
  styles, media, SVG and MathML dropped with their content, other
  elements unwrapped, script URLs dropped, an image's `src` kept only
  for a file under `images/` (the source reads nothing else), inside
  `<main id="article-content">`. `articleStyleSheet` is the shell's
  layout for headings, pictures, figures, quotes, code and tables; the
  text's font, size, spacing and colours are the reader's `BookStyle`.
- **Anchors** — `ArticleAnchor` reads and writes
  `readflex-html-position:` and the anchor's JSON byte for byte as the
  shell did (key order, `encodeURIComponent`), verified against Chromium
  (`test/fixtures/article/anchors.json`, recorded by
  `article_anchor_fixtures.mjs`): a
  sentence's (`forSentence`), a range's with its root and match
  (`forRange`), and back to an element or a range (`elementIn`,
  `rangeIn`) by the root's text, white space collapsed, exactly or by
  the text around it.
- **Contents** — `articleToc`: headings with an id as a tree, else up to
  twelve blocks of 48 characters or more, by their first 72.
- **Index** — `ArticleIndex`: sentences in order, the sentence at a
  point, the heading before a node, minutes left at 1200 characters a
  minute from a sentence.
- **Selection** — `ArticleSelection`: the text of a range as the
  document holds it, 200 characters of context within its sentence or
  block, its anchor, and the saved highlights it merges.
- **Search** — `searchArticle`: each sentence's text, lower-cased, in
  order, a slice at a time between frames, hits (`ArticleSearchHit`)
  with the shell's excerpt and anchor, their heading and their range
  (the first 1000), in batches of 25.

`TextScrollController` lays the article out as one column the width of
the view less its margins, no wider than the measure, as far as the view
needs and the rest between frames; the position (`TextScrollPosition`)
keeps the exact requested point after opening or point navigation, even
when earlier text shares its line. Scrolling resumes reporting the first
text at the middle of the view. The position also holds the scroll share
and what moved it (`TextScrollReason`: the reader's finger, a jump, a new
layout). A new size, style or font that drops the layout lays it out
again with that text at the middle; an unchanged one keeps everything.
It opens at a point or a share, and goes to a point (centred or at the
top margin), a range (centred, or from the top when taller than the
view) or a share. `TextScrollView` shows full viewport slices in a
`SliverFixedExtentList`, followed by a shorter final slice when needed.
The scroll range ends at the content's bottom margin, without rounding
up to a full viewport; the margins already hold the safe area. It
rebuilds slices only when the layout grows or changes, and takes
taps (links, highlights, the rest as view fractions), selection across
slices, sideways drags on tables that scroll and the tracked highlight's
rectangles for markers drawn over it.

## Corpus (`test/corpus`)

The fixture tests prove the formats on books built for them; the corpus
tests prove them on real ones. `corpus_test.dart` opens every EPUB, FB2
and MOBI/AZW3 under `PAGECRAFT_CORPUS` (or expects a `PagecraftException` for a
file that is not one), reads its cover, checks that its contents and
landmarks point into the book, resolves every section's styles and checks
that no rendered character is lost on the way to a paragraph, and lays
every section out into pages at a phone's size. It times every open,
section load, style pass and layout and records the process memory growth
(`PAGECRAFT_CORPUS_REPORT` writes the Markdown table). `corpus_census_test.dart`
counts what the books ask of the engine that pagecraft does not draw yet. Both
are skipped when `PAGECRAFT_CORPUS` is unset: the corpus is not in the
repository. Before the WebView reader was removed, a browser snapshot of
foliate-js was the reference
for every section's document tree, navigation and link targets; what it
taught the document model: XHTML needs the HTML named entities
(`&nbsp;`), attribute values fold line breaks, text folds CRLF, and a
section the browser cannot parse is one pagecraft may still show.

## Import metadata (`src/metadata`)

`readComicMetadata`, `readPdfMetadata`, `readEpubMetadata`,
`readFb2Metadata` and `readMobiMetadata` give a `BookMetadata` (title,
author, description, `CoverImage`) for the library's import, the
counterpart of `book.metadata` and `getCover()` in foliate-js. Text
formats take the book's own metadata, join authors with `, `, and fall
back to the file name (`.fb2.zip` counts as one extension) when there is
no title. Every cover goes through `encodeCoverThumbnail`
(`CoverThumbnailSpec`, 480×720 by default): the engine decodes the image
straight at the target size and a short-lived isolate encodes the JPEG,
so a page scan never becomes a full-size bitmap; an image the engine
cannot decode means no cover, not a failed import.

## Comics

`ComicBook.open(path, pageOrderVersion:)` lists the archive's images in
reading order and reads a page's bytes on demand; decoding and caching
belong to the image layer. The order must match the WebView reader's for
saved positions to land on the same page: version 0 is the legacy
code-unit sort of names with a lowercase image extension; version 1
(`currentComicPageOrderVersion`) takes any extension case, skips
`__MACOSX` and `._` entries and sorts naturally. `naturalFilenameCompare`
reproduces `Intl.Collator('en', {numeric: true, sensitivity: 'variant'})`
with the collator's ties broken by code units: digit runs by value with
leading zeros ignored, punctuation before digits before letters, Latin
diacritics and Cyrillic `ё` as secondary differences, case last. The
reference is `test/fixtures/icu_natural_order.json`, a historical recording of
Node's ICU collator for every pair of 56 names, plus probes for letters outside it.
Not modelled: contractions of other languages and non-decimal numerals;
such names fall back to code-point order.

`probeImageDimensions` reads the displayed size from an image header so
spreads can be planned before the bytes are decoded.

## PDF (`src/formats/pdf/`)

pdfium is the one third-party engine in pagecraft, for PDF only, through
`pdfrx_engine` (the Dart API of pdfrx, no widgets) and `pdfium_flutter`
(the library itself: an XCFramework on iOS and macOS, a bundled native
asset on Android). `PdfBook.open(path, password:)` reads every page's
displayed size in points (a `/Rotate` page comes back turned), the outline
as `PdfOutlineEntry` trees with 0-based page indices (an entry whose
destination is missing or out of range keeps `pageIndex` null), and
`Title`/`Author` of the Info dictionary through `FPDF_GetMetaText`, which
`pdfrx_engine` does not expose; that call runs while the engine's worker
is paused, as pdfium allows one caller at a time. Page sizes are read in
one pass in the worker isolate; the cost grows with page count and does not
include rendering every page.
An encrypted file without the right password throws
`PdfPasswordRequiredException`; anything pdfium cannot read throws
`PagecraftException` with pdfium's reason. The app calls
`initializePdfEngine()` once before the first open.

Pages are drawn through `ImageProvider`s, as comic pages are, so the
framework's image cache holds the budget and `Image`, `precacheImage` and
error handling work unchanged. `PdfPageImage(book, pageIndex,
targetWidth)` renders the whole page at a width (the frame in device
pixels, `thumbnailWidth` for previews); pdfium draws in its worker
isolate into a BGRA buffer that `decodeImageFromPixels` turns into a
texture, and the buffer is freed only after that copy, since it is native
memory viewed from Dart. A width whose page would exceed
`PdfPageImage.maxPixels` (6 Mpx, the WebView reader's cap on one bitmap)
is reduced. A zoomed page gets sharp through `PdfPageTile(book, pageIndex,
fullWidth, region)`: the region of the page at the zoomed size, drawn
over the fitted page, so 4× zoom never costs a 4× page. `PdfPageThumbnail`
is the preview widget. `readPdfMetadata(path)` is the import side: Info
title (or the file name when there is none; the WebView import stored
"Unknown"), author, and the first page rendered by pdfium straight at
the cover size and JPEG-encoded through `encodeCoverFromPixels`.

`PdfTextLayer.load(book, page)` is the text layer: pdfium's reading-order
text with one `\n` per line and a `PdfBox` per character in display
points (`/Rotate` applied, origin top-left, so one factor scales it to the
drawn page). On it: `charIndexAt` and `wordAtPoint` (a tap lands on the
nearest glyph within a glyph's height; words are letters, digits and
marks with inner apostrophes and hyphens), `boxesOf` (one box per line,
for selections and highlights), `contextOf` (the sentence around a
selection with the selection in `[[…]]`, as
`readflex_selection_context.js` built it: sentences end at `.!?…` plus
closing quotes before whitespace, line breaks are whitespace, a sentence
cut by the 2048-character window falls back to the selection),
`search` and `rangeOfText`. `src/search/text_search.dart` is the shared
search: case- and diacritic-insensitive (Latin-1, Latin Extended-A,
combining marks, й/ё) with whitespace runs folded, excerpts of 50
characters per side with an ellipsis when cut, offsets mapped back to the
original text.

Anchors (`src/formats/pdf/pdf_anchor.dart`): the WebView reader anchored PDF
highlights with CFIs into the DOM text layer `pdf.js` drew, which only
that DOM resolves. pagecraft writes `epubcfi(/6/N!/2[pagecraft],/1:start,/1:end)`,
so the page step still reads in both readers (`fakeCfiToIndex`) and the
character range is exact for pagecraft; `resolvePdfTextAnchor` takes that
range when the text still matches and searches the highlight's saved
text on the page otherwise, which is how the WebView's highlights open
here.

Margin crops and page colours keep the WebView reader's rules.
`detectPdfPageContent(book, page)` has pdfium draw a sample with its long
side at 160 px and `detectContentBox` (pure) finds the ink: the paper tone
is the median of the ring inside the ignored 1 % edge, a pixel is ink 28
luminance steps away from it, rows and columns need 1 % (at least two)
inked samples so specks do not stretch the box, one sample pixel of
slack is added. `contentCrop` turns the box into the crop: 2 % padding,
pages whose ink is narrower than half the page stay whole, the height
grows to the viewport's aspect anchored at the ink top and shifts up at
the bottom edge. `pageColorsFor(themed:, background:, foreground:)` is
null for the original setting and for white paper (luminance ≥ 0.98);
themes darker than 0.4 invert. `paintPageWithColors` draws a page image
with those colours through one `ColorFilter.matrix` (`pageColorFilter`,
cached per `PageColors`): light themes map white to the background and
black to the text colour, linearly between; dark themes invert luminance
in YIQ, which keeps hues so a blue figure stays blue, then map the
inverted paper to the background and the inverted ink to the text colour.
One draw, the same cost as an unrecoloured page, and the same pixels under
Impeller and Skia. The WebView's canvas recipe (blend modes inside a
layer) is not used: Impeller renders `saveLayer` plus `difference`/`hue`
blends as a no-op, so a dark theme left pages white on iOS.

`PdfTextLayer.load` retains the engine's structured text and UTF-16 offsets,
but uses PDFium's typographic character cells for selection geometry. Tight
glyph bounds can collapse to a baseline for substituted fonts in scanned
books. Native cells include ascent and descent; an exact text alignment keeps
saved CFIs stable, while generated whitespace retains the formatter's boxes.
Metrics run on the engine's existing worker, where font substitution callbacks
belong. Metadata, metrics and disposal share a queue; closing waits for accepted
native tasks. The original Cyrillic raster/text fixture and its crop/rotation
variant reproduce this missing-font defect without including a user's book.

`PdfTextOverlay` goes into `FixedPagesView.pageOverlayBuilder` with the
page's `PdfTextLayer`: it draws saved `PdfTextHighlight`s, the search
hit and the selection held in a `PdfTextSelection` (`ChangeNotifier`) the
app owns, as `ComicImageAreaDraft` holds an image-area draft. A long
press (280 ms) on a word selects it and drags its end over the text; a
drag from either adaptive Flutter fallback handle (at least 48dp targets, kept at
screen size when zoomed) activates after 6 screen pixels and moves that end
by an insertion boundary on the nearest text line. The initial finger-to-handle
offset and the opposite
endpoint remain fixed, including when one endpoint crosses the other.
Flutter's platform magnifier shows the active boundary while dragging; a tap
outside clears the selection; a tap on a saved highlight reports it.
On supported iOS/Android hosts, releasing the initial long press hands the
range and exact text-layer geometry to `native_text_selection`. UIKit/Android
provide the handles and magnifier; the host's action menu stays in
Flutter. Geometry and source UTF-16 offsets remain Pagecraft's. The platform
view is disposed when selection clears. Unsupported geometry retains the
Flutter controls described above. Reflowable books and articles use the same
adapter through `TextNativeSelectionGeometry`, preserving source maps and CFIs.
See the [native adapter's contract and limits](../native_text_selection/README.md).

Reports carry the selection's rect as fractions of the whole view for the
app's chrome. `onSelectionDragChanged` reports active adjustment; the final
range callback precedes its `false` event so the host can hide actions while
dragging and restore them with the updated text. `handleColor` is independent
of the fill: `PdfTextSelection.setBaseColor` configures the normal fill,
`setColor` previews an annotation colour and `resetColor` restores the base.
Flutter fallback selection, search and saved-highlight fills multiply over original/light
pages to preserve black glyphs. With `darkPage: true`, fills use lightening
with limited opacity to preserve the light text instead. Hosts must
derive that flag from the rendered page, not application brightness: an
original white page in a dark application still needs the light-page policy.
While a selection is up the view's input is locked, as for image areas.
Both overlays repaint through `RepaintAfterBuild`: app-driven colour changes
may arrive while a popup builds or disposes, so a change
may arrive mid-frame, and the repaint then waits for the end of the frame
while the model keeps its call order. `PdfTextLayerCache`
keeps the layers of the last 12 pages read and tells listeners when one
arrives; `searchPdfBook` streams hits page by page through it (or loads
and drops layers without it) and stops when the subscription is
cancelled.

## DjVu (`src/formats/djvu/`)

`DjvuBook.open(path)` opens a self-contained `.djvu`/`.djv` document through
DjVuLibre's C++ decoder. Dart calls a narrow C ABI with `dart:ffi`; this format
does not use Rust or FRB. `DjvuPages` implements the core `FixedPageSource`, so
the existing view owns page turns, animations, RTL, spreads and zoom. Pagecraft
does not convert DjVu to PDF, HTML or a directory of pre-rendered pages.

Each opened book owns a worker isolate and native document handle. Requests are
serialized there, including rendering and hidden-text reads; wrapping a blocking
FFI call in a Future on the UI isolate would not provide this isolation.
`close()` refuses new work, drains accepted requests and releases the decoder
once. Page metadata stays readable after closing. Failed opening releases the
partially created native resources.

`DjvuPageImage` keys include document identity, page, render width and optional
region. Full-page rendering is bounded to six million pixels; sharp zoom tiles
render only the requested region at the full-page scale. Replies transfer owned
RGBA bytes to Flutter. The image provider uses Flutter's normal image cache;
there is no whole-document bitmap cache. Text has a separate bounded LRU.

DjVu's optional hidden text describes word zones rather than PDF-style glyph
boxes. `DjvuTextLayer` retains those zones in top-left page coordinates and uses
Dart UTF-16 text offsets. Search follows the core case/diacritic folding rules;
`searchDjvuBook` streams page hits. `DjvuTextOverlay` adapts word selection to
reader actions and saved text highlights. If a document stores only coarser
line/page zones, selection keeps that supplied granularity instead of inventing
word or glyph geometry. A page without hidden text has no
searchable/selectable text; this backend does not run OCR. Page CFIs use the
core fixed-page anchors, and text ranges add the `pagecraft-djvu` marker so they
cannot be mistaken for EPUB or PDF text positions.

The decoder accepts single-page and bundled multi-page documents. Indirect
multi-file documents and standalone external `INCL` references are refused;
the engine does not fetch document components from arbitrary paths or URLs.
The vendored release includes the documented upstream INCL nesting guard;
cyclic bundled includes fail with a typed error instead of overflowing the
decoder stack. The [native backend notes](native/djvu/README.md) record the
backport provenance and platform adaptation.
The optional JPEG-in-DjVu codec is disabled in this build; the usual JB2/IW44
DjVu encodings are decoded by the vendored library.

The native build hook compiles the committed sources under `native/djvu/` for
the target platform; a system DjVuLibre installation is not required and normal
builds do not fetch source code. Preserve its source pin, license notices and
upstream changes when updating it. The vendored DjVuLibre component is licensed
under GPLv2 or later, independently of the surrounding Dart code's notices;
distributing linked application builds requires evaluating those obligations.

The original three-page fixture in `test/formats/djvu/djvu_fixture.dart` contains
portrait/landscape pages, Unicode hidden text, a nested outline and an image-only
page. Its generator uses DjVuLibre maintenance tools and original artwork;
normal tests read the committed bytes and do not use user books or network.
Core checks cover rendering/tiles, search/anchors, malformed inputs, bounded
text caching and document disposal. The app's device smoke is
`integration_test/djvu_reader_test.dart` in the repository root.

## Metadata (`src/metadata`)

`readComicMetadata(path)` is what the app's import calls instead of the
headless WebView: the title is the file name without its extension, as
`comic-book.js` sets it, and the cover is the first page in reading order.
`encodeCoverThumbnail` turns any image the engine decodes into a JPEG that
fits `CoverThumbnailSpec` (480×720, quality 85 by default): the engine
decodes straight to the target size with EXIF orientation applied, so a
page scan never becomes a full-size bitmap, and only the JPEG encoding of
the small frame (`package:image`) runs in Dart, in a short-lived isolate.
A first page over `maxCoverBytes` (32 MiB) or one that does not decode
leaves the cover null and the import goes on without it, as it does when
foliate-js hands back no cover. A file that is not a comic throws
`PagecraftException`.

## Fixed-layout pages (`src/fixed_layout`)

`FixedPagesController` is the model (`ChangeNotifier`, like `PageController`):
pages pair into spreads as `fixed-layout.js` pairs sections without
`page-spread` hints (left then right, mirrored for right-to-left); a
viewport taller than 1.2 widths shows one page at a time; a turn moves
within the spread first, then enters the next spread from the side the
reader came from; `goToCfi` takes the fake CFIs the WebView reader saves
(`epubcfi(/6/N)`), `goToFraction` the slider's fraction; `position`
reports the numbers the app shows (`fraction = (page + 1) / pageCount`,
chapter counter = page counter, one byte-based location). Every turn,
jump or rotation resets zoom (`zoomEpoch`).

Both paginated views use `src/page_turn/`: `PageTurnFrame` describes normalized
motion, entry side and axis; its strategies resolve offsets and visible regions.
`PageTurnLayer` keeps a stable transform/clip/repaint-boundary tree, and
`PageTurnDecoration` paints above the page layers. The text viewer supplies its
gesture/controller motion; the fixed viewer compensates native `PageView`
offsets with the same resolved geometry. Highlight tracking uses those same
visible regions. An active turn keeps its selected animation until it settles;
a changed setting applies to the next turn.

Changing animation reuses layout, selection, page images and zoom. Slide and
Cover do not capture pages or own texture caches; Flutter retains its normal
paint and raster caching. A future deforming effect
such as Curl needs its own renderer at the page-layer seam, owning temporary
textures only during the turn and releasing them on settle/cancel/dispose;
offset/clip strategies alone cannot bend a page. Adding that renderer does not
change format parsers, positions or gesture arbitration. Only implemented
effects belong in the public enum and app settings.

`FixedPagesView` draws any `FixedPageSource` (`ComicPages` over a
`ComicPageSource`, `PdfPages` over a `PdfBook`, `DjvuPages` over a `DjvuBook`)
with framework parts:
`PageView` under a `Directionality` for the reading direction (its
`axis` turns pages sideways or, for the reader's vertical page turn, up
and down, where reading direction does not apply),
`PageScrollPhysics`, `allowImplicitScrolling` for neighbours,
and the same `pageTurnAnimation` choice as text pages. The scrolling viewport
retains its physics; the shared page-turn layer compensates its native offsets
as required by the selected effect, including reverse and RTL turns. Page units
retain their image and zoom widgets while the transition moves.
The view uses `InteractiveViewer` for pinch and pan (1–4×), a `CustomMultiChildLayout`
that gives facing pages one scale and a shared gutter (a PDF's known
`pageAspect` lays the spread out before anything is drawn), and a
`FixedPagePainter` per page drawing the source's `pageImage` at the frame
width in device pixels through `paintPageWithColors`. A zoom gesture
re-decodes the page denser, up to the pixel budget; when that is not
sharp enough (a zoomed PDF), the frame renders the on-screen part as a
tile after the gesture (`sharpenRegion`, `tileFor`, `tileCovers` in
`zoom_tiles.dart`, the WebView's rules: 1.1× threshold, 20 % pan margin,
6 Mpx) and drops it at fit. A tile is placed in the pixels of the page
bitmap it was planned over: a bitmap of another size (the denser decode
that follows a zoom) drops it and plans it again. `visibleRectOf` gives
each page a margin crop: the visible part is fitted and laid out, the whole
page is rendered at the density the crop is shown at (again when a crop is
measured after the page shows, through the same function), and overlays still receive the whole page's
rect (`imageRect`), which then extends past the frame. `pageColors` apply
theme colours to pages and tiles alike. Taps follow
`readflex_page_zoom.js`: edge zones (`edgeTapZoneFraction`, 0.3) fire at
once and never zoom; a centre tap waits 280 ms for a second one within
32 px, which zooms to 2.5× at the point or back to fit; zoomed pages treat
every tap as a centre tap and swipes as pans. `onTap` receives fractions
of the view, what the app's tap-zone logic takes today. Reduced motion
jumps instead of animating.

`ComicPageImage` is an `ImageProvider`: the page's bytes from a
`ComicPageSource`, decoded to a target width, cached by the framework's
image cache under (source, page, width). `ComicPageThumbnail` and
`PdfPageThumbnail` use the providers at 240 px (comics with the 16 MiB
budget of the WebView previews).

`FixedPagesView.onPageShown` reports a visible page's first image, which
is the moment a document is readable; `FixedPagesViewportScope` lets
overlays express rectangles as fractions of the whole view, the coordinate
space the app's selection chrome positions itself in.

`ComicImageAreaLayer` goes into `FixedPagesView.pageOverlayBuilder`: saved
areas in fractions of the image, and a draft held in a
`ComicImageAreaDraft` (`ChangeNotifier`) the app owns. A long press
(280 ms) starts a draft of the WebView reader's default size centred on
the finger; while it exists the view's paging, pan and zoom input is locked.
Drags inside move it; quick or held corner drags resize it down to 1.5 %.
Corner targets retain 64 screen pixels, with 48 pixels outside the crop and
16 inside, shifting into the page frame at its edges. Overlaps choose the
nearest corner in a stable order; the centre remains a move region.
The center uses the selected annotation color at 45% opacity. Four blue
triangular corner controls (`#2563EB`) contain white diagonal resize arrows,
centered halfway along each corner bisector. There are no borders or separator
strokes. Control opacity is three times the
draft opacity, capped at 100%. Blue grips use 85% of that opacity, while arrows
use the full value: by default, the grips are 85% opaque and arrows are fully
opaque. Zero draft opacity hides both. This does not change the annotation fill.
While a draft exists, a black scrim dims the rest of the image, including the
other page of a spread.
The scrim uses twice the draft opacity, capped at 65% (65% by default).
Clearing the draft restores the original page appearance.
Saved image areas use a 90% multiply tint, coloring the paper while preserving
dark ink instead of washing it out. Triangle
legs are 48 screen pixels, capped at 45% of the crop's short side; each
whole triangle resizes its corner. Tiny crops retain the same 64-pixel touch
targets and normalized minimum size, without overlapping corner decorations.
Sizes meant in screen pixels are divided by the zoom.

Visible page layers share primary-pointer ownership through the draft, so an
extra finger cannot replace or jump an edit, including across a spread. A tap
outside (also on the other page) cancels unless the app retains the draft
under a sheet; taps on outside corner targets keep it. A long press on a saved
area reports the topmost one. `onDraftAdjustmentChanged` reports only gesture
start/end, allowing the host to hide editing actions while the finger moves.
The final retained rectangle is committed before adjustment ends, including
pointer cancellation; clearing or disposing the draft balances the phase
without publishing obsolete geometry.

## Tests

`fvm flutter test` from this directory. `package:pagecraft/testing.dart` is
the test-support library, for this package and for packages that embed it:
`ZipBuilder` writes archives byte by byte so flags, methods, ZIP64 records
and damage are under the test's control (one test cross-checks an archive
written by `package:archive`); `encodeSolidPng` and `buildComicArchive`
generate deterministic comics, so goldens in `test/fixed_layout/goldens/`
are stable (regenerate with `--update-goldens` only for an intended
change); `FakeComicSource` is an in-memory page source. PDF tests call
`preparePdfEngineForTests()` first: the `pdfium_dart` build hook downloads
the host library during `flutter test`, but this Flutter records it in
`build/native_assets/<os>/native_assets.json` while the engine's loader
looks for `.dart_tool/native_assets.yaml`, so the helper reads Flutter's
manifest and points the engine at the library. PDF fixtures live in
`test/fixtures/pdf/` with their PostScript sources; `make_fixtures.sh`
regenerates them with Ghostscript (outline, rotated page and Info
dictionary through pdfmarks, a user-password file, 200 pages).
`test/fixtures/icu_sentence_breaks.json` holds ICU's sentence breaks for
curated and random strings. To regenerate this independent ICU reference with
Node.js, run from this package directory:

```sh
node test/fixtures/icu_sentence_breaks.mjs test/fixtures/icu_sentence_breaks.json
```

Normal tests read the committed JSON. `readflex_selection.json` records what
the former WebView reader's selection modules computed; `foliate_search.json`
records foliate-js's `search()` on tricky text-node lists. `search_fold.json`
records historical folds from `tool/search_fold_table.mjs`, as described above.

`test/metadata/` decodes
real covers through the engine in plain `test`s and reads the JPEG back
to check colours and the quantization table. In widget tests,
opening a real archive is a chain of file reads that complete on the real
event loop: alternate `runAsync` and `pump`, as the reader's screen test
does, and write fixtures with the synchronous file API.
