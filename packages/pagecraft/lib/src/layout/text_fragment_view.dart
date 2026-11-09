import 'package:flutter/widgets.dart';

import '../document/content_document.dart';
import 'book_image_cache.dart';
import 'book_style.dart';
import 'box_tree.dart';
import 'column_layout.dart';
import 'column_pages.dart';
import 'inline_styler.dart';
import 'paragraph_layout.dart';
import 'text_page.dart';
import 'text_page_highlights.dart';

/// A short piece of a book laid out at the width it gets and shown whole,
/// scrolling when it is taller than its space: a note over the page.
///
/// It lays [boxes] out again only when they, the style, the width or the
/// text scale change. Text is selectable inside a selection area, as on
/// pages. Images show once [images] has probed their keys.
class TextFragmentView extends StatefulWidget {
  const TextFragmentView({
    super.key,
    required this.boxes,
    required this.bookStyle,
    required this.styler,
    required this.images,
    required this.imageKey,
    this.document,
    this.highlights = const [],
    this.padding = EdgeInsets.zero,
    this.maxImageHeight = 400,
  });

  final SectionBoxes boxes;
  final BookStyle bookStyle;
  final InlineStyler styler;
  final BookImageCache images;
  final ImageKeyOf imageKey;
  final ContentDocument? document;
  final List<TextHighlight> highlights;
  final EdgeInsets padding;
  final double maxImageHeight;

  @override
  State<TextFragmentView> createState() => _TextFragmentViewState();
}

class _TextFragmentViewState extends State<TextFragmentView> {
  ColumnLayout? _column;
  double _width = -1;
  TextScaler _scaler = TextScaler.noScaling;

  @override
  void didUpdateWidget(TextFragmentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.boxes, widget.boxes) ||
        oldWidget.bookStyle != widget.bookStyle ||
        !identical(oldWidget.styler, widget.styler) ||
        oldWidget.maxImageHeight != widget.maxImageHeight) {
      _dropLayout();
    }
  }

  @override
  void dispose() {
    _dropLayout();
    super.dispose();
  }

  void _dropLayout() {
    final column = _column;
    _column = null;
    // A page may still paint it this frame.
    if (column != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => column.dispose());
    }
  }

  ColumnLayout _layout(double width) {
    final scaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    if (_column == null || width != _width || scaler != _scaler) {
      _dropLayout();
      _width = width;
      _scaler = scaler;
      _column = ColumnLayout.layout(
        widget.boxes,
        width: width,
        pageHeight: widget.maxImageHeight,
        bookStyle: widget.bookStyle,
        text: TextLayoutEnvironment(
          styler: widget.styler,
          imageSize: (src) {
            final key = widget.imageKey(src);
            return key == null ? null : widget.images.sizeOf(key);
          },
          maxImageHeight: widget.maxImageHeight,
          textScaler: scaler,
        ),
      );
    }
    return _column!;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - widget.padding.horizontal).clamp(
        1.0,
        double.infinity,
      );
      final column = _layout(width);
      return SingleChildScrollView(
        child: TextColumnPage(
          column: column,
          page: ColumnPage(0, column.height),
          images: widget.images,
          imageKey: widget.imageKey,
          padding: widget.padding,
          document: widget.document,
          highlights: widget.highlights,
        ),
      );
    },
  );
}
