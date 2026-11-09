/// Pagecraft: the native reader engine, the Flutter analogue of foliate-js.
///
/// This library is the core every format shares: ZIP containers, the
/// document model, CSS, layout, the text and fixed-layout page views,
/// CFIs, search, progress and the library's cover thumbnails. Formats
/// have libraries of their own, each exporting this one: `epub.dart`,
/// `fb2.dart`, `mobi.dart`, `comic.dart`, `pdf.dart`, `djvu.dart` and `article.dart`;
/// `all_formats.dart` exports them all. An app imports the formats it
/// reads; release builds can drop unreachable Dart code. PDFium, MOBI and
/// DjVu native assets remain package dependencies for every consumer.
/// Nothing here knows about the app's domain models or storage.
library;

export 'src/container/zip_archive.dart';
export 'src/container/zip_entry.dart';
export 'src/pagecraft_exception.dart';
export 'src/fonts/book_font_face.dart';
export 'src/fonts/book_font_loader.dart';
export 'src/fonts/font_data.dart';
export 'src/fonts/font_ink.dart';
export 'src/formats/book_navigation.dart';
export 'src/search/text_node_search.dart';
export 'src/search/text_search.dart';
export 'src/text/charsets.dart';
export 'src/text/html_entities.dart';
export 'src/text/hyphenation_patterns.dart'
    show HyphenationPatterns, hyphenationPatternsFor;
export 'src/text/hyphenator.dart';
export 'src/text/selection_normalizer.dart';
export 'src/text/sentence_breaks.dart';
export 'src/text/whitespace.dart';
export 'src/image/image_dimensions.dart';
export 'src/image/page_content.dart';
export 'src/page_turn/page_turn_animation.dart';
export 'src/css/computed_style.dart';
export 'src/css/css_custom_properties.dart' show CssCustomProperties;
export 'src/css/css_media.dart';
export 'src/css/css_properties.dart';
export 'src/css/css_selector.dart';
export 'src/css/css_syntax.dart';
export 'src/css/css_tokenizer.dart';
export 'src/css/css_values.dart';
export 'src/css/style_resolver.dart';
export 'src/css/stylesheet_loader.dart';
export 'src/css/ua_stylesheet.dart';
export 'src/document/content_document.dart';
export 'src/document/text_point.dart';
export 'src/layout/book_fonts.dart';
export 'src/layout/book_image_cache.dart';
export 'src/layout/book_style.dart';
export 'src/layout/box_builder.dart';
export 'src/layout/box_tree.dart';
export 'src/layout/column_layout.dart';
export 'src/layout/column_pages.dart';
export 'src/layout/inline_styler.dart';
export 'src/layout/list_markers.dart';
export 'src/layout/paragraph_layout.dart';
export 'src/layout/text_fragment_view.dart';
export 'src/layout/text_page.dart';
export 'src/layout/text_page_highlights.dart';
export 'src/layout/text_page_selection.dart';
export 'src/layout/text_source_map.dart';
export 'src/progress/section_progress.dart';
export 'src/progress/toc_progress.dart';
export 'src/text_book/footnotes.dart';
export 'src/text_book/highlight_merge.dart';
export 'src/text_book/page_progression.dart';
export 'src/text_book/section_preparer.dart';
export 'src/text_book/selection_context.dart';
export 'src/text_book/text_anchor.dart';
export 'src/text_book/text_book_search.dart';
export 'src/text_book/text_locator.dart';
export 'src/text_book/text_page_geometry.dart';
export 'src/text_book/text_pages_controller.dart';
export 'src/text_book/text_pages_view.dart';
export 'src/text_book/text_scroll_controller.dart';
export 'src/text_book/text_scroll_view.dart';
export 'src/text_book/text_selection_details.dart';
export 'src/text_book/text_book_layout.dart';
export 'src/text_book/text_book_support.dart';
export 'src/text_book/text_book_source.dart';
export 'src/text_book/text_links.dart';
export 'src/epubcfi/cfi.dart';
export 'src/epubcfi/cfi_node.dart';
export 'src/epubcfi/cfi_resolve.dart';
export 'src/epubcfi/fake_cfi.dart';
export 'src/epubcfi/xml_cfi_document.dart';
export 'src/metadata/book_metadata.dart';
export 'src/metadata/cover_thumbnail.dart';
export 'src/fixed_layout/spread_layout.dart';
export 'src/fixed_layout/fixed_pages_controller.dart';
export 'src/fixed_layout/fixed_page_source.dart';
export 'src/fixed_layout/fixed_pages_view.dart';
export 'src/fixed_layout/comic_image_area.dart';
export 'src/fixed_layout/comic_image_area_layer.dart';
export 'src/fixed_layout/page_colors.dart';
export 'src/fixed_layout/zoom_tiles.dart';
