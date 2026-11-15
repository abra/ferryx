import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:material_ui/material_ui.dart';

import 'hex_format.dart';
import 'line_layout.dart';
import 'text_layout.dart';
import 'text_window.dart';
import 'source_syntax.dart';
import 'source_spans.dart';
import 'viewer_source.dart';

/// Monospace with compact leading; byte grids can supply their own height.
TextStyle contentStyle(
  BuildContext context,
  double fontSize, {
  double? height,
}) => context.mono.copyWith(
  fontSize: fontSize,
  height: height ?? AppTypography.viewerLineHeightFactor,
);

/// The width of one character of [style]: the faces are monospace.
double charWidthOf(BuildContext context, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: 'M', style: style),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

double lineHeightOf(BuildContext context, TextStyle style) =>
    MediaQuery.textScalerOf(context).scale(style.fontSize! * style.height!);

/// The horizontal inset of the content from the pane's edge.
const double _inset = AppSpacing.md;

/// The scroll behaviour without the automatic scrollbar: a scroll view
/// whose bar is drawn by a [Scrollbar] of its own, placed where the bar
/// belongs.
ScrollBehavior _bareScrolling(BuildContext context) =>
    ScrollConfiguration.of(context).copyWith(scrollbars: false);

/// The content under a vertical bar at the pane's edge and a horizontal
/// one at its bottom, whatever the content's width: the vertical list
/// sits inside the horizontal scroll view, so its own bar would scroll
/// away with the content. Neither scroll view draws a bar of its own.
class ViewerScrollFrame extends StatelessWidget {
  const ViewerScrollFrame({
    super.key,
    required this.vertical,
    required this.horizontal,
    required this.contentWidth,
    required this.child,
  });

  final ScrollController vertical;
  final ScrollController horizontal;
  final double contentWidth;

  /// The vertical list, scrolled by [vertical].
  final Widget child;

  @override
  Widget build(BuildContext context) => AppScrollbar(
    controller: vertical,
    notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
    child: AppScrollbar(
      controller: horizontal,
      notificationPredicate: (n) =>
          n.depth == 0 && n.metrics.axis == Axis.horizontal,
      child: ScrollConfiguration(
        behavior: _bareScrolling(context),
        child: SingleChildScrollView(
          controller: horizontal,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: SizedBox(width: contentWidth, child: child),
        ),
      ),
    ),
  );
}

/// Text mode: the window's lines, wrapped or clipped, matches lit, their
/// numbers in a gutter while the window starts at the file's start (the
/// number of a line further in is not known).
class TextView extends StatefulWidget {
  const TextView({
    required this.window,
    required this.matchesByLine,
    required this.current,
    required this.wrap,
    required this.fontSize,
    required this.controller,
    required this.onLayout,
    this.firstLine,
    this.syntax = const [],
    super.key,
  });

  final DecodedWindow window;
  final Map<int, List<ViewerMatch>> matchesByLine;
  final ViewerMatch? current;
  final bool wrap;
  final double fontSize;
  final ScrollController controller;
  final ValueChanged<LineLayout> onLayout;

  /// The number of the window's first line, when known.
  final int? firstLine;
  final List<List<SourceToken>> syntax;

  @override
  State<TextView> createState() => _TextViewState();
}

class _TextViewState extends State<TextView> {
  final _horizontal = ScrollController();
  TextLayout? _layout;
  double _charWidth = 1;
  double _textStart = 0;

  @override
  void didUpdateWidget(TextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedWindow = !identical(oldWidget.window, widget.window);
    if (changedWindow ||
        oldWidget.current != widget.current ||
        oldWidget.wrap != widget.wrap) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.wrap || !_horizontal.hasClients) return;
        final position = _horizontal.position;
        final match = widget.current;
        if (match == null) {
          if (changedWindow) _horizontal.jumpTo(0);
          return;
        }
        final left = _textStart + match.start * _charWidth;
        final right = _textStart + match.end * _charWidth;
        if (left < position.pixels ||
            right > position.pixels + position.viewportDimension) {
          _horizontal.jumpTo(
            (left - position.viewportDimension / 3).clamp(
              0,
              position.maxScrollExtent,
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = contentStyle(context, widget.fontSize);
    final lineHeight = lineHeightOf(context, style);
    final charWidth = charWidthOf(context, style);
    final lines = widget.window.lines;
    final firstLine = widget.firstLine;
    // The gutter: the widest number and a gap, or nothing.
    final digits = firstLine == null
        ? 0
        : (firstLine + lines.length - 1).toString().length;
    final gutter = digits == 0 ? 0.0 : digits * charWidth + AppSpacing.md;
    _charWidth = charWidth;
    _textStart = _inset + gutter;
    return LayoutBuilder(
      builder: (context, constraints) {
        final textWidth = constraints.maxWidth - _inset * 2 - gutter;
        final columns = math.max(1, (textWidth / charWidth).floor());
        var layout = _layout;
        if (layout == null ||
            !identical(layout.sourceLines, lines) ||
            layout.wrap != widget.wrap ||
            layout.columns != columns ||
            layout.lineHeight != lineHeight) {
          layout = _layout = TextLayout(
            sourceLines: lines,
            lineHeight: lineHeight,
            columns: columns,
            wrap: widget.wrap,
          );
        }
        widget.onLayout(layout);
        final currentLayout = layout;
        final contentWidth = widget.wrap
            ? constraints.maxWidth
            : (layout.maxLineLength * charWidth + _inset * 2 + gutter).clamp(
                constraints.maxWidth,
                double.infinity,
              );
        return ListenableBuilder(
          listenable: _horizontal,
          builder: (context, _) {
            final horizontalOffset = _horizontal.hasClients
                ? _horizontal.offset
                : 0.0;
            final list = ListView.builder(
              controller: widget.controller,
              physics: const ClampingScrollPhysics(),
              itemCount: currentLayout.fragmentCount,
              itemExtent: currentLayout.uniformFragments ? lineHeight : null,
              itemExtentBuilder: currentLayout.uniformFragments
                  ? null
                  : (index, dimensions) =>
                        currentLayout.heightOfFragment(index),
              padding: EdgeInsets.zero,
              itemBuilder: (context, index) {
                final fragment = currentLayout.fragmentAt(index);
                final text = lines[fragment.line];
                var start = fragment.start;
                var end = fragment.end;
                if (!widget.wrap && text.length > maxTextParagraphLength) {
                  // Overscan keeps edge glyphs intact while scrolling. The
                  // full line width remains available to the scrollbar.
                  const overscan = 32;
                  start = scalarBoundaryBefore(
                    text,
                    (((horizontalOffset - _textStart) / charWidth).floor() -
                            overscan)
                        .clamp(0, text.length),
                  );
                  end = scalarBoundaryAfter(
                    text,
                    (start + columns + overscan * 2).clamp(start, text.length),
                  );
                }
                return TextLine(
                  text: start == 0 && end == text.length
                      ? text
                      : text.substring(start, end),
                  sourceOffset: start,
                  leadingWidth: widget.wrap ? 0 : start * charWidth,
                  style: style,
                  matches: widget.matchesByLine[fragment.line],
                  current: widget.current?.line == fragment.line
                      ? widget.current
                      : null,
                  // Long logical lines are hard-wrapped into lazy visual
                  // rows; word wrapping again could clip a row's final word.
                  wrap: widget.wrap && text.length <= maxTextParagraphLength,
                  number: firstLine == null || fragment.start != 0
                      ? null
                      : firstLine + fragment.line,
                  gutterWidth: gutter,
                  syntax: fragment.line < widget.syntax.length
                      ? widget.syntax[fragment.line]
                      : const [],
                );
              },
            );
            if (widget.wrap) return list;
            return ViewerScrollFrame(
              vertical: widget.controller,
              horizontal: _horizontal,
              contentWidth: contentWidth,
              child: list,
            );
          },
        );
      },
    );
  }
}

/// One line of text with its matches lit; the current one stronger. Its
/// [number] stands right-aligned in a gutter of [gutterWidth].
class TextLine extends StatelessWidget {
  const TextLine({
    required this.text,
    required this.style,
    required this.matches,
    required this.current,
    required this.wrap,
    this.number,
    this.gutterWidth = 0,
    this.sourceOffset = 0,
    this.leadingWidth = 0,
    this.syntax = const [],
    super.key,
  });

  final String text;
  final TextStyle style;
  final List<ViewerMatch>? matches;
  final ViewerMatch? current;
  final bool wrap;
  final int? number;

  /// The number's column and the gap after it.
  final double gutterWidth;

  /// The fragment's UTF-16 offset in the logical line, for syntax and Find.
  final int sourceOffset;

  /// Offscreen columns before an unwrapped viewport fragment.
  final double leadingWidth;
  final List<SourceToken> syntax;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spans = syntax.isNotEmpty || (matches?.isNotEmpty ?? false)
        ? sourceSpans(
            context,
            text,
            style,
            syntax,
            matches ?? const [],
            current,
            sourceOffset: sourceOffset,
          )
        : TextSpan(text: text, style: style);
    final line = Padding(
      padding: EdgeInsets.only(left: leadingWidth),
      child: Text.rich(
        spans,
        softWrap: wrap,
        overflow: TextOverflow.clip,
        maxLines: wrap ? null : 1,
      ),
    );
    final number = this.number;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _inset),
      child: gutterWidth == 0
          ? line
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: gutterWidth - AppSpacing.md,
                  child: Text(
                    number?.toString() ?? '',
                    style: style.copyWith(
                      color: colors.textFaint,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: line),
              ],
            ),
    );
  }
}

/// Hex mode: sixteen bytes a row with their offset and their text.
class HexView extends StatefulWidget {
  const HexView({
    required this.bytes,
    required this.baseOffset,
    required this.matchesByLine,
    required this.current,
    required this.fontSize,
    required this.controller,
    required this.onLayout,
    super.key,
  });

  final Uint8List bytes;
  final int baseOffset;
  final Map<int, List<ViewerMatch>> matchesByLine;
  final ViewerMatch? current;
  final double fontSize;
  final ScrollController controller;
  final ValueChanged<LineLayout> onLayout;

  @override
  State<HexView> createState() => _HexViewState();
}

class _HexViewState extends State<HexView> {
  final _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = contentStyle(
      context,
      widget.fontSize,
      height: context.metrics.typeScale.editorCode.height,
    );
    final lineHeight = lineHeightOf(context, style);
    final rows = hexRowCount(widget.bytes.length);
    widget.onLayout(LineLayout.uniform(lineHeight: lineHeight, lines: rows));
    final charWidth = charWidthOf(context, style);
    // Offset, two groups, the text and the gaps between them.
    final width = charWidth * (8 + 2 + 23 + 2 + 23 + 2 + 18) + _inset * 2;
    return LayoutBuilder(
      builder: (context, constraints) => ViewerScrollFrame(
        vertical: widget.controller,
        horizontal: _horizontal,
        contentWidth: width.clamp(constraints.maxWidth, double.infinity),
        child: ListView.builder(
          controller: widget.controller,
          physics: const ClampingScrollPhysics(),
          itemCount: rows,
          itemExtent: lineHeight,
          padding: EdgeInsets.zero,
          itemBuilder: (context, index) => HexLine(
            row: hexRow(widget.bytes, index, baseOffset: widget.baseOffset),
            style: style,
            matches: widget.matchesByLine[index],
            current: widget.current?.line == index ? widget.current : null,
          ),
        ),
      ),
    );
  }
}

/// One hex row, its matched bytes lit in both columns.
class HexLine extends StatelessWidget {
  const HexLine({
    required this.row,
    required this.style,
    required this.matches,
    required this.current,
    super.key,
  });

  final HexRow row;
  final TextStyle style;
  final List<ViewerMatch>? matches;
  final ViewerMatch? current;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final muted = style.copyWith(color: colors.textMuted);
    final hex = '${row.left}  ${row.right}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _inset),
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            TextSpan(text: hexOffsetText(row.offset), style: muted),
            const TextSpan(text: '  '),
            ..._cells(
              hex,
              colors,
              (m) => (hexCellStart(m.start), hexCellStart(m.end - 1) + 2),
            ),
            const TextSpan(text: '  '),
            TextSpan(text: '|', style: muted),
            ..._cells(row.ascii, colors, (m) => (m.start, m.end)),
            TextSpan(text: '|', style: muted),
          ],
        ),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
      ),
    );
  }

  List<TextSpan> _cells(
    String text,
    AppColorsExt colors,
    (int, int) Function(ViewerMatch match) span,
  ) {
    if (matches == null || matches!.isEmpty) return [TextSpan(text: text)];
    final out = <TextSpan>[];
    var at = 0;
    for (final match in matches!) {
      final (s, e) = span(match);
      final start = s.clamp(0, text.length);
      final end = e.clamp(start, text.length);
      if (start > at) out.add(TextSpan(text: text.substring(at, start)));
      final isCurrent = current == match;
      out.add(
        TextSpan(
          text: text.substring(start, end),
          style: style.copyWith(
            backgroundColor: isCurrent ? colors.accent : colors.highlight,
            color: isCurrent ? colors.onAccent : null,
          ),
        ),
      );
      at = end;
    }
    if (at < text.length) out.add(TextSpan(text: text.substring(at)));
    return out;
  }
}

/// The platform's spinner, shown only once a wait has gone on for a
/// moment: a read that ends sooner shows nothing at all.
class DelayedSpinner extends StatefulWidget {
  const DelayedSpinner({super.key});

  @override
  State<DelayedSpinner> createState() => _DelayedSpinnerState();
}

class _DelayedSpinnerState extends State<DelayedSpinner> {
  Timer? _wait;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _wait = Timer(AppMotion.medium, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _shown ? const Center(child: AppSpinner()) : const SizedBox.shrink();
}

/// Preview mode: a picture read through the source (on disk or in an
/// archive alike), or a word that there is none.
class PreviewView extends StatefulWidget {
  const PreviewView({
    required this.source,
    required this.size,
    this.generation = 0,
    super.key,
  });

  final ViewerSource source;
  final int size;
  final int generation;

  /// Pictures are read whole, up to this.
  static const int maxBytes = 64 * 1024 * 1024;

  bool get previewable =>
      isImageName(source.displayName) && size > 0 && size <= maxBytes;

  @override
  State<PreviewView> createState() => _PreviewViewState();
}

class _PreviewViewState extends State<PreviewView> {
  Future<Uint8List>? _bytes;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(PreviewView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.size != widget.size ||
        oldWidget.generation != widget.generation) {
      _read();
    }
  }

  void _read() {
    _bytes = widget.previewable ? widget.source.read(0, widget.size) : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final none = AppEmptyState(
      title: l10n.viewerNoPreview,
      icon: AppIcons.imageOff,
    );
    final bytes = _bytes;
    if (bytes == null) return none;
    return FutureBuilder<Uint8List>(
      future: bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) return none;
        final data = snapshot.data;
        if (data == null) return const DelayedSpinner();
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Center(
            child: Image.memory(
              data,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) => none,
            ),
          ),
        );
      },
    );
  }
}
