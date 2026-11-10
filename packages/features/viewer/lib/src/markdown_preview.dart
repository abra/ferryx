import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'markdown_format.dart';
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
            child: Markdown(
              key: ValueKey((widget.source, widget.generation)),
              data: widget.data,
              selectable: true,
              controller: _scroll,
              padding: const EdgeInsets.all(AppSpacing.lg),
              styleSheet: _style,
              builders: {'a': _LinkBuilder(widget.source, widget.generation)},
              checkboxBuilder: (value) =>
                  AppCheckbox(value: value, onChanged: null),
              imageBuilder: (uri, title, alt) => MarkdownImage(
                source: widget.source,
                reference: uri,
                alt: alt,
                generation: widget.generation,
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
