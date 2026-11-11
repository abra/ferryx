import 'package:domain_models/domain_models.dart';

import 'markdown_format.dart';

const maxTextPreviewBytes = maxMarkdownPreviewBytes;
const maxOfficePreviewBytes = 32 * 1024 * 1024;

enum TextPreviewFormat {
  markdown,
  html,
  rtf,
  asciiDoc,
  reStructuredText,
  csv,
  tsv,
  docx,
  xlsx,
  pptx,
  doc,
  xls,
  ppt;

  bool get office => switch (this) {
    docx || xlsx || pptx || doc || xls || ppt => true,
    _ => false,
  };

  int get maxInputBytes => office ? maxOfficePreviewBytes : maxTextPreviewBytes;

  TextDocumentFormat? get converter => switch (this) {
    rtf => TextDocumentFormat.rtf,
    asciiDoc => TextDocumentFormat.asciiDoc,
    reStructuredText => TextDocumentFormat.reStructuredText,
    docx => TextDocumentFormat.docx,
    xlsx => TextDocumentFormat.xlsx,
    pptx => TextDocumentFormat.pptx,
    doc => TextDocumentFormat.doc,
    xls => TextDocumentFormat.xls,
    ppt => TextDocumentFormat.ppt,
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
    'docx' || 'docm' || 'dotx' || 'dotm' => TextPreviewFormat.docx,
    'xlsx' || 'xlsm' || 'xltx' || 'xltm' => TextPreviewFormat.xlsx,
    'pptx' ||
    'pptm' ||
    'ppsx' ||
    'ppsm' ||
    'potx' ||
    'potm' => TextPreviewFormat.pptx,
    'doc' || 'dot' => TextPreviewFormat.doc,
    'xls' || 'xlt' => TextPreviewFormat.xls,
    'ppt' || 'pps' || 'pot' => TextPreviewFormat.ppt,
    _ => null,
  };
}
