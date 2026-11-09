import 'dart:isolate';
import 'dart:math' as math;

import '../document/content_document.dart';
import 'reading_direction.dart';
import 'text_book_source.dart';

const _sectionLimit = 12;
const _windowLength = 5000;
const _maxSectionBytes = 512 * 1024;
const _maxBookBytes = 2 * 1024 * 1024;

/// Resolves page progression once, independently of paragraph text direction.
///
/// Mirrors the former reader: declared RTL wins, then RTL language, then a
/// bounded sample of linear sections. Latin metadata and spine direction may
/// describe front matter, so they do not override predominantly RTL content.
/// Fixed-layout sources retain their printed order. No UI locale is consulted.
Future<bool> resolvePageProgressionRtl(TextBookSource source) async {
  if (source.rtl) return true;
  if (source.isFixedLayout) return false;
  if (isRtlLanguage(source.language)) return true;

  var remainingBytes = _maxBookBytes;
  var rtl = 0;
  var ltr = 0;
  for (final index in _sampleSections(source)) {
    final size = source.sectionSize(index);
    if (size <= 0 || size > _maxSectionBytes || size > remainingBytes) continue;
    remainingBytes -= size;
    try {
      // Stateful formats share a read cursor: keep these reads sequential.
      final section = await source.section(index);
      final budget = math.min(_maxSectionBytes, remainingBytes + size);
      final sample = await Isolate.run(
        () => _sampleSection(section, budget),
        debugName: 'pagecraft page direction $index',
      );
      if (sample.bytes > budget) break;
      // EPUB sizes are exact; other formats may use character counts as weights.
      remainingBytes -= math.max(0, sample.bytes - size);
      rtl += sample.rtl;
      ltr += sample.ltr;
    } catch (_) {
      // Direction fallback must not prevent opening the remaining readable book.
    }
  }
  return rtl > ltr;
}

List<int> _sampleSections(TextBookSource source) {
  final linear = [
    for (var index = 0; index < source.sectionCount; index++)
      if (source.isLinear(index)) index,
  ];
  final count = linear.length;
  if (count <= _sectionLimit) return linear;
  final selected = <int>{0, 1, 2, (count - 1) ~/ 2, count - 1};
  for (var slot = 0; selected.length < _sectionLimit; slot++) {
    selected.add((slot * (count - 1) / (_sectionLimit - 1)).round());
  }
  return (selected.toList()..sort()).map((index) => linear[index]).toList();
}

({int bytes, int rtl, int ltr}) _sampleSection(
  TextSection section,
  int budget,
) {
  final bytes = _utf8SizeUpTo(section.text, budget);
  if (bytes > budget) return (bytes: bytes, rtl: 0, ltr: 0);
  ContentDocument doc;
  try {
    doc = ContentDocument.parse(section.text, mediaType: section.mediaType);
  } on ContentParseException {
    doc = ContentDocument.parseHtml(section.text);
  }
  var body = _bodyOf(doc);
  if (body == null) {
    doc = ContentDocument.parseHtml(section.text);
    body = _bodyOf(doc);
  }
  if (body == null) return (bytes: bytes, rtl: 0, ltr: 0);
  final text = _bodyText(doc, body).replaceAll(RegExp(r'\s+'), ' ');
  var rtl = 0;
  var ltr = 0;
  final maxStart = math.max(0, text.length - _windowLength);
  for (final start in <int>{0, maxStart ~/ 2, maxStart}) {
    final end = math.min(start + _windowLength, text.length);
    final counts = directionCharacterCounts(text.substring(start, end));
    rtl += counts.rtl;
    ltr += counts.ltr;
  }
  return (bytes: bytes, rtl: rtl, ltr: ltr);
}

int? _bodyOf(ContentDocument doc) {
  for (final node in doc.descendantsOf(ContentDocument.rootIndex)) {
    if (doc.isElement(node) && doc.localNameOf(node).toLowerCase() == 'body') {
      return node;
    }
  }
  return null;
}

String _bodyText(ContentDocument doc, int body) {
  final text = StringBuffer();
  final end = doc.subtreeEndOf(body);
  var node = body;
  while (node < end) {
    if (doc.isText(node)) {
      text.write(doc.textOf(node));
    } else if (const {'head', 'script', 'style'}.contains(
      doc.localNameOf(node).toLowerCase(),
    )) {
      node = doc.subtreeEndOf(node);
      continue;
    }
    node++;
  }
  return text.toString();
}

/// Counts without allocating an encoded copy, stopping as soon as it exceeds
/// the parse budget if a format underreported its section's size.
int _utf8SizeUpTo(String text, int limit) {
  var bytes = 0;
  for (final rune in text.runes) {
    bytes += rune <= 0x7F
        ? 1
        : rune <= 0x7FF
        ? 2
        : rune <= 0xFFFF
        ? 3
        : 4;
    if (bytes > limit) break;
  }
  return bytes;
}
