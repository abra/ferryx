enum DocumentFormat { epub, fb2, mobi, cbz, pdf, djvu }

DocumentFormat? documentFormatOf(String name) {
  final lower = name.toLowerCase();
  if (!lower.contains('.')) return null;
  if (lower.endsWith('.fb2.zip')) return DocumentFormat.fb2;
  return switch (lower.split('.').last) {
    'epub' => DocumentFormat.epub,
    'fb2' || 'fbz' => DocumentFormat.fb2,
    'mobi' || 'azw3' => DocumentFormat.mobi,
    'cbz' => DocumentFormat.cbz,
    'pdf' => DocumentFormat.pdf,
    'djvu' || 'djv' => DocumentFormat.djvu,
    _ => null,
  };
}

bool isDocumentName(String name) => documentFormatOf(name) != null;
