import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:html/parser.dart' as html;

import 'markdown_format.dart';
import 'preview_search.dart';
import 'rich_text_preview.dart';
import 'text_preview_data.dart';

import 'markdown_image.dart';
import 'viewer_source.dart';
import 'viewer_link.dart';

/// Rendered Markdown shares the viewer's placement, scroll keys and text size.
class MarkdownPreview extends StatefulWidget {
  const MarkdownPreview({
    required this.source,
    required this.data,
    required this.size,
    required this.generation,
    required this.fontSize,
    super.key,
  });

  final ViewerSource source;
  final String data;
  final int size;
  final int generation;
  final double fontSize;

  @override
  State<MarkdownPreview> createState() => _MarkdownPreviewState();
}

class _MarkdownPreviewState extends State<MarkdownPreview> {
  final _scroll = ScrollController();
  ThemeData? _theme;
  double? _fontSize;
  late MarkdownStyleSheet _style;
  Future<TextPreviewData>? _searchHtml;
  Object? _searchKey;
  bool _usingSearchRenderer = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (widget.size > maxMarkdownPreviewBytes) {
      return AppEmptyState(
        title: l10n.markdownTooLarge(l10n.fileSize(maxMarkdownPreviewBytes)),
        icon: AppIcons.file,
      );
    }
    if (widget.data.trim().isEmpty) {
      return AppEmptyState(title: l10n.viewerEmptyFile, icon: AppIcons.file);
    }
    final theme = Theme.of(context);
    // The renderer reparses when its stylesheet changes. Keep it stable
    // across placement and unrelated viewer-state updates.
    if (_theme != theme || _fontSize != widget.fontSize) {
      _theme = theme;
      _fontSize = widget.fontSize;
      _style = _markdownStyle(context, widget.fontSize);
    }
    final search = PreviewSearchScope.maybeOf(context);
    if (search != null) {
      return ListenableBuilder(
        listenable: search,
        child: _MarkdownBody(
          scroll: _scroll,
          source: widget.source,
          generation: widget.generation,
          data: widget.data,
          style: _style,
        ),
        builder: (context, child) {
          // Keep the found passage in place when Find closes. Opening the
          // empty field alone does not replace the renderer or move the page.
          _usingSearchRenderer =
              _usingSearchRenderer || search.query.isNotEmpty;
          if (!_usingSearchRenderer) return child!;
          final key = (widget.source, widget.generation, widget.data);
          if (_searchKey != key) {
            _searchKey = key;
            _searchHtml = _prepareSearchMarkdown(widget.data);
          }
          return FutureBuilder(
            future: _searchHtml,
            builder: (context, snapshot) {
              final data = snapshot.data;
              if (data is HtmlPreviewData) {
                return RichTextPreview(
                  html: data.html,
                  source: widget.source,
                  generation: widget.generation,
                  fontSize: widget.fontSize,
                );
              }
              return child!;
            },
          );
        },
      );
    }
    return _MarkdownBody(
      scroll: _scroll,
      source: widget.source,
      generation: widget.generation,
      data: widget.data,
      style: _style,
    );
  }
}

Future<TextPreviewData> _prepareSearchMarkdown(String data) async =>
    prepareHtml(await compute(_markdownHtml, data));

String _markdownHtml(String data) {
  final document = html.parseFragment(
    md.markdownToHtml(data, extensionSet: md.ExtensionSet.gitHubFlavored),
  );
  for (final input in document.querySelectorAll('input[type=checkbox]')) {
    final replacement = html
        .parseFragment(
          '<ferryx-checkbox checked="${input.attributes.containsKey('checked')}"></ferryx-checkbox>',
        )
        .nodes
        .single;
    input.replaceWith(replacement);
  }
  return document.outerHtml;
}

class _MarkdownBody extends StatelessWidget {
  const _MarkdownBody({
    required this.scroll,
    required this.source,
    required this.generation,
    required this.data,
    required this.style,
  });
  final ScrollController scroll;
  final ViewerSource source;
  final int generation;
  final String data;
  final MarkdownStyleSheet style;
  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: scroll,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.documentWideMaxWidth,
            ),
            child: Markdown(
              key: ValueKey((source, generation)),
              data: data,
              selectable: true,
              controller: scroll,
              padding: const EdgeInsets.all(AppSpacing.lg),
              styleSheet: style,
              builders: {'a': _LinkBuilder(source, generation)},
              checkboxBuilder: (value) =>
                  AppCheckbox(value: value, onChanged: null),
              imageBuilder: (uri, title, alt) => MarkdownImage(
                source: source,
                reference: uri,
                alt: alt,
                generation: generation,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared editor typography and surface roles, including variable font axes.
MarkdownStyleSheet _markdownStyle(BuildContext context, double fontSize) {
  final colors = context.appColors;
  final type = context.metrics.typeScale;
  final scale = fontSize / type.editorBody.fontSize!;
  TextStyle sized(TextStyle style) => style.copyWith(
    fontSize: style.fontSize! * scale,
    color: context.colors.onSurface,
  );
  final body = sized(type.editorBody);
  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: body,
    h1: sized(type.editorHeading1),
    h2: sized(type.editorHeading2),
    h3: sized(type.editorHeading3),
    h4: body.weight(FontWeight.w600),
    h5: body.weight(FontWeight.w600),
    h6: body.weight(FontWeight.w600),
    strong: const TextStyle().weight(FontWeight.w600),
    a: body.copyWith(
      color: colors.accent,
      decoration: TextDecoration.underline,
    ),
    code: sized(type.editorCode)
        .copyWith(backgroundColor: colors.surfaceSunken),
    listBullet: body,
    blockSpacing: AppSpacing.sm,
    listIndent: AppSpacing.xl,
    blockquote: body,
    blockquoteDecoration: BoxDecoration(
      color: colors.surfaceSunken,
      border: AppBorder(
        left: BorderSide(
          color: colors.controlBorder,
        ),
      ),
    ),
    blockquotePadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xs,
    ),
    codeblockPadding: const EdgeInsets.all(AppSpacing.sm),
    codeblockDecoration: BoxDecoration(
      color: colors.surfaceSunken,
      borderRadius: BorderRadius.circular(context.metrics.radius.control),
    ),
    tableHead: body.weight(FontWeight.w600),
    tableBody: body,
    tableBorder: TableBorder.all(color: colors.line),
    tableCellsPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: AppBorder(top: BorderSide(color: colors.line)),
    ),
  );
}

/// Inline links retain keyboard activation, focus rings and hint labels.
class _LinkBuilder extends MarkdownElementBuilder {
  _LinkBuilder(this.source, this.generation);
  final ViewerSource source;
  final int generation;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final href = element.attributes['href'];
    if (href == null) return null;
    final image = element.children
        ?.whereType<md.Element>()
        .where((child) => child.tag == 'img')
        .firstOrNull;
    final reference = Uri.tryParse(image?.attributes['src'] ?? '');
    return ViewerLink(
      href: href,
      label: element.textContent.isEmpty ? href : element.textContent,
      style: parentStyle?.merge(preferredStyle) ?? preferredStyle,
      child: image == null || reference == null
          ? null
          : MarkdownImage(
              source: source,
              reference: reference,
              alt: image.attributes['alt'],
              generation: generation,
            ),
    );
  }
}
