import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import 'markdown_image.dart';
import 'viewer_link.dart';
import 'viewer_source.dart';

/// All document formats share one native Flutter renderer and resource policy.
class RichTextPreview extends StatefulWidget {
  const RichTextPreview({
    required this.html,
    required this.source,
    required this.generation,
    required this.fontSize,
    super.key,
  });
  final String html;
  final ViewerSource source;
  final int generation;
  final double fontSize;
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
                factoryBuilder: _RepositoryWidgetFactory.new,
                renderMode: _renderMode,
                enableCaching: true,
                rebuildTriggers: [widget.generation, widget.source],
                customStylesBuilder: (element) => switch (element.localName) {
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
