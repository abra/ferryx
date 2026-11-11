import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

enum TextPreviewFailure { limit, malformed }

sealed class TextPreviewData {
  const TextPreviewData();
}

class HtmlPreviewData extends TextPreviewData {
  const HtmlPreviewData(this.html, {this.images = const {}});
  final String html;
  final Map<String, Uint8List> images;
}

class TablePreviewData extends TextPreviewData {
  const TablePreviewData(this.rows, this.columns);
  final List<List<String>> rows;
  final int columns;
}

class FailedTextPreview extends TextPreviewData {
  const FailedTextPreview(this.reason);
  final TextPreviewFailure reason;
}

/// Parsing stays outside the UI isolate. Renderer-owned resource loading is
/// removed here; images are supplied by the repository-backed widget.
Future<TextPreviewData> prepareHtml(
  String source, {
  bool embeddedImages = false,
}) => compute(_cleanHtml, (source, embeddedImages));

TextPreviewData _cleanHtml((String, bool) input) {
  final (source, embeddedImages) = input;
  // Native Office conversion includes base64 images. They are removed from
  // the markup and decoded into the separate image map before rendering.
  final maxSourceLength = (embeddedImages ? 32 : 8) * 1024 * 1024;
  if (source.length > maxSourceLength) {
    return const FailedTextPreview(TextPreviewFailure.limit);
  }
  final document = html.parse(source);
  const excluded = {
    'script',
    'style',
    'iframe',
    'object',
    'embed',
    'link',
    'meta',
    'base',
    'svg',
    'canvas',
    'audio',
    'video',
    'form',
    'input',
    'button',
    'textarea',
    'select',
    'template',
  };
  const attributes = {
    'href',
    'src',
    'alt',
    'title',
    'id',
    'name',
    'rowspan',
    'colspan',
    'start',
    'reversed',
    'align',
    'dir',
  };
  final nodes = document.body?.querySelectorAll('*') ?? <dom.Element>[];
  if (nodes.length > 20000) {
    return const FailedTextPreview(TextPreviewFailure.limit);
  }
  final images = <String, Uint8List>{};
  for (final element in nodes) {
    if (excluded.contains(element.localName)) {
      element.remove();
      continue;
    }
    final style = element.attributes['style'];
    element.attributes.removeWhere((key, _) => !attributes.contains(key));
    if (embeddedImages && element.localName == 'img') {
      final reference = element.attributes.remove('src') ?? '';
      try {
        final data = Uri.parse(reference).data;
        if (data != null &&
            data.isBase64 &&
            const {
              'image/png',
              'image/jpeg',
              'image/gif',
              'image/webp',
              'image/bmp',
            }.contains(data.mimeType)) {
          final bytes = data.contentAsBytes();
          if (bytes.isNotEmpty && bytes.length <= 8 * 1024 * 1024) {
            final id = 'ferryx-embedded:${images.length}';
            images[id] = bytes;
            element.attributes['src'] = id;
          }
        }
      } on FormatException {
        // A broken/unsupported picture keeps its alt text without loading a URL.
      }
    }
    if (style != null) {
      final safe = style
          .split(';')
          .where((declaration) {
            final colon = declaration.indexOf(':');
            if (colon < 0) return false;
            final key = declaration.substring(0, colon).trim().toLowerCase();
            final value = declaration.substring(colon + 1).trim().toLowerCase();
            return switch (key) {
              'font-weight' => RegExp(
                r'^(normal|bold|[1-9]00)$',
              ).hasMatch(value),
              'font-style' => const {
                'normal',
                'italic',
                'oblique',
              }.contains(value),
              'text-decoration' => RegExp(
                r'^(none|underline|line-through)( (underline|line-through))?$',
              ).hasMatch(value),
              'text-align' => const {
                'left',
                'right',
                'center',
                'justify',
                'start',
                'end',
              }.contains(value),
              'white-space' => const {
                'pre',
                'pre-wrap',
                'normal',
              }.contains(value),
              _ => false,
            };
          })
          .join(';');
      if (safe.isNotEmpty) element.attributes['style'] = safe;
    }
    for (final key in ['rowspan', 'colspan']) {
      final value = int.tryParse(element.attributes[key] ?? '');
      if (value != null) {
        element.attributes[key] = value.clamp(1, 64).toString();
      }
    }
  }
  final cleaned = document.body?.innerHtml ?? '';
  if (cleaned.length > 8 * 1024 * 1024) {
    return const FailedTextPreview(TextPreviewFailure.limit);
  }
  return HtmlPreviewData(
    cleaned,
    images: Map.unmodifiable(images),
  );
}

Future<TextPreviewData> prepareTable(String source, {required bool tsv}) =>
    compute(_parseTable, (source, tsv));

TextPreviewData _parseTable((String, bool) input) {
  try {
    List<List<dynamic>>? data;
    var bestScore = -1;
    // Validate candidates with the CSV parser: a comma inside a quoted
    // field must not win delimiter detection for a semicolon-separated file.
    for (final delimiter in input.$2 ? ['\t'] : [',', ';']) {
      try {
        final candidate = CsvToListConverter(
          shouldParseNumbers: false,
          allowInvalid: false,
          fieldDelimiter: delimiter,
          eol: input.$1.contains('\r\n') ? '\r\n' : '\n',
        ).convert(input.$1);
        final columns = candidate.firstOrNull?.length ?? 0;
        final consistent = candidate
            .take(32)
            .where((row) => row.length == columns)
            .length;
        final score = (columns > 1 ? 1000 : 0) + consistent * 100 + columns;
        if (score > bestScore) {
          data = candidate;
          bestScore = score;
        }
      } on FormatException {
        /* Try the other delimiter. */
      }
    }
    if (data == null) {
      return const FailedTextPreview(TextPreviewFailure.malformed);
    }
    if (data.length > 5000) {
      return const FailedTextPreview(TextPreviewFailure.limit);
    }
    var columns = 0;
    var cells = 0;
    final rows = <List<String>>[];
    for (final row in data) {
      if (row.length > columns) columns = row.length;
      cells += row.length;
      if (columns > 64 || cells > 50000) {
        return const FailedTextPreview(TextPreviewFailure.limit);
      }
      final values = [for (final cell in row) cell?.toString() ?? ''];
      if (values.any((s) => s.length > 16384)) {
        return const FailedTextPreview(TextPreviewFailure.limit);
      }
      rows.add(List.unmodifiable(values));
    }
    return TablePreviewData(List.unmodifiable(rows), columns);
  } on FormatException {
    return const FailedTextPreview(TextPreviewFailure.malformed);
  }
}
