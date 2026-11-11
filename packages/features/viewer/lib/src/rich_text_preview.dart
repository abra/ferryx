import 'dart:async';
import 'dart:typed_data';

import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import 'markdown_image.dart';
import 'viewer_link.dart';
import 'viewer_source.dart';

const _tableCellTags = {'td', 'th'};

/// All document formats share one native Flutter renderer and resource policy.
class RichTextPreview extends StatefulWidget {
  const RichTextPreview({
    required this.html,
    required this.source,
    required this.generation,
    required this.fontSize,
    this.images = const {},
    super.key,
  });
  final String html;
  final ViewerSource source;
  final int generation;
  final double fontSize;
  final Map<String, Uint8List> images;
  @override
  State<RichTextPreview> createState() => _RichTextPreviewState();
}

class _RichTextPreviewState extends State<RichTextPreview> {
  final _scroll = ScrollController();
  late final _renderMode = ListViewMode(
    controller: _scroll,
    padding: const EdgeInsets.all(AppSpacing.lg),
  );
  final _htmlKey = GlobalKey<HtmlWidgetState>();
  late double _cellWidth;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _openLink(String href) {
    if (href.startsWith('#')) {
      final target = Uri.tryParse(href)?.fragment;
      if (target != null) {
        unawaited(_htmlKey.currentState?.scrollToAnchor(target));
      }
    } else {
      unawaited(showViewerLink(context, href));
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = context.metrics.typeScale;
    final style = type.editorBody.copyWith(
      fontSize: widget.fontSize,
      color: context.colors.onSurface,
    );
    final mono = [
      context.mono.fontFamily,
      ...?context.mono.fontFamilyFallback,
    ].whereType<String>().map((s) => '"$s"').join(',');
    final grid = context.appColors.controlBorder;
    final cellWidth = _cellWidth =
        AppSizes.documentTableCellWidth *
        MediaQuery.textScalerOf(context).scale(widget.fontSize) /
        type.editorBody.fontSize!;
    final border =
        '1px solid rgba(${(grid.r * 255).round()},'
        '${(grid.g * 255).round()},${(grid.b * 255).round()},${grid.a})';
    return Scrollbar(
      controller: _scroll,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.documentWideMaxWidth,
            ),
            child: SelectionArea(
              child: HtmlWidget(
                widget.html,
                key: _htmlKey,
                textStyle: style,
                factoryBuilder: () =>
                    _RepositoryWidgetFactory(() => _cellWidth),
                renderMode: _renderMode,
                enableCaching: true,
                rebuildTriggers: [
                  widget.generation,
                  widget.source,
                  grid,
                  cellWidth,
                ],
                customStylesBuilder: (element) => switch (element.localName) {
                  'table' => {
                    'border': border,
                    'border-collapse': 'collapse',
                    'border-spacing': '0',
                  },
                  'td' || 'th' => {
                    'border': border,
                    'padding': '${AppSpacing.xs}px ${AppSpacing.sm}px',
                  },
                  'p' when _tableCellTags.contains(element.parent?.localName) =>
                    {'margin': '0'},
                  'h1' => {
                    'font-size':
                        '${type.editorHeading1.fontSize! / type.editorBody.fontSize!}em',
                  },
                  'h2' => {
                    'font-size':
                        '${type.editorHeading2.fontSize! / type.editorBody.fontSize!}em',
                  },
                  'h3' => {
                    'font-size':
                        '${type.editorHeading3.fontSize! / type.editorBody.fontSize!}em',
                  },
                  'code' || 'pre' || 'kbd' || 'samp' => {'font-family': mono},
                  _ => null,
                },
                customWidgetBuilder: (element) {
                  if (element.localName == 'img') {
                    return MarkdownImage(
                      embeddedBytes: widget.images[element.attributes['src']],
                      source: widget.source,
                      reference:
                          Uri.tryParse(element.attributes['src'] ?? '') ??
                          Uri(),
                      alt: element.attributes['alt'],
                      generation: widget.generation,
                    );
                  }
                  if (element.localName == 'a' &&
                      element.attributes.containsKey('href')) {
                    final href = element.attributes['href']!;
                    final image = element.querySelector('img');
                    return InlineCustomWidget(
                      child: ViewerLink(
                        href: href,
                        label: element.text.isEmpty ? href : element.text,
                        style: style.copyWith(
                          color: context.appColors.link,
                          decoration: TextDecoration.underline,
                        ),
                        onActivate: () => _openLink(href),
                        child: image == null
                            ? null
                            : MarkdownImage(
                                embeddedBytes:
                                    widget.images[image.attributes['src']],
                                source: widget.source,
                                reference:
                                    Uri.tryParse(
                                      image.attributes['src'] ?? '',
                                    ) ??
                                    Uri(),
                                alt: image.attributes['alt'],
                                generation: widget.generation,
                              ),
                      ),
                    );
                  }
                  return null;
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// No renderer fallback may read files, data URIs, assets or the network.
class _RepositoryWidgetFactory extends WidgetFactory {
  _RepositoryWidgetFactory(this.cellWidth);

  // HtmlWidget retains the factory when its font size changes.
  final ValueGetter<double> cellWidth;

  @override
  void parse(BuildTree tree) {
    super.parse(tree);
    if (tree.element.localName != 'table') return;
    tree.register(
      BuildOp.v2(
        onRenderBlock: (tree, placeholder) => placeholder.wrapWith(
          (context, child) => _HorizontalDocumentScroll(child: child),
        ),
      ),
    );
  }

  @override
  Widget? buildPadding(
    BuildTree tree,
    Widget child,
    EdgeInsetsGeometry padding,
  ) {
    final padded = super.buildPadding(tree, child, padding);
    if (padded == null || !_tableCellTags.contains(tree.element.localName)) {
      return padded;
    }
    // Use a readable width for the initial measurement and honor the tight
    // width the renderer allocates across merged columns on its final pass.
    return ConstrainedBox(
      constraints: BoxConstraints.tightFor(width: cellWidth()),
      child: padded,
    );
  }

  @override
  InlineSpan? buildTextSpan({
    List<InlineSpan>? children,
    GestureRecognizer? recognizer,
    TextStyle? style,
    String? text,
  }) => super.buildTextSpan(
    children: children,
    recognizer: recognizer,
    text: text,
    style: style?.fontWeight == null ? style : style!.weight(style.fontWeight!),
  );

  @override
  Widget? buildTooltip(BuildTree tree, Widget child, String message) =>
      AppTooltip(message: message, child: child);

  @override
  ImageProvider? imageProviderFromAsset(String url) => null;
  @override
  ImageProvider? imageProviderFromDataUri(String url) => null;
  @override
  ImageProvider? imageProviderFromFileUri(String url) => null;
  @override
  ImageProvider? imageProviderFromNetwork(String url) => null;
}

class _HorizontalDocumentScroll extends StatefulWidget {
  const _HorizontalDocumentScroll({
    required this.child,
  });

  final Widget child;

  @override
  State<_HorizontalDocumentScroll> createState() =>
      _HorizontalDocumentScrollState();
}

class _HorizontalDocumentScrollState extends State<_HorizontalDocumentScroll> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _scroll,
    thumbVisibility: true,
    // Lay out the table at its cell widths before clipping it to the pane.
    child: SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: widget.child,
    ),
  );
}
