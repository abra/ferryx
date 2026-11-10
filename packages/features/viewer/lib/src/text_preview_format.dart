import 'package:domain_models/domain_models.dart';

import 'markdown_format.dart';

const maxTextPreviewBytes = maxMarkdownPreviewBytes;

enum TextPreviewFormat {
  markdown,
  html,
  rtf,
  asciiDoc,
  reStructuredText,
  csv,
  tsv;

  TextDocumentFormat? get converter => switch (this) {
    rtf => TextDocumentFormat.rtf,
    asciiDoc => TextDocumentFormat.asciiDoc,
    reStructuredText => TextDocumentFormat.reStructuredText,
    _ => null,
  };
}

TextPreviewFormat? textPreviewFormatOf(String name) {
  if (isMarkdownName(name)) return TextPreviewFormat.markdown;
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  return switch (name.substring(dot + 1).toLowerCase()) {
    'html' || 'htm' || 'xhtml' => TextPreviewFormat.html,
    'rtf' => TextPreviewFormat.rtf,
    'adoc' || 'asciidoc' => TextPreviewFormat.asciiDoc,
    'rst' || 'rest' => TextPreviewFormat.reStructuredText,
    'csv' => TextPreviewFormat.csv,
    'tsv' => TextPreviewFormat.tsv,
    _ => null,
  };
}
