/// Bytes a text book source hands out besides its sections: images
/// written as `data:` URIs and style sheet texts.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The bytes of a `data:` URI, or null when it is not one.
Uint8List? decodeDataUri(String uri) {
  final comma = uri.indexOf(',');
  if (!uri.startsWith('data:') || comma < 0) return null;
  final meta = uri.substring(5, comma);
  final payload = uri.substring(comma + 1);
  try {
    if (meta.endsWith(';base64')) {
      return base64.decode(payload.replaceAll(RegExp(r'\s'), ''));
    }
    return Uint8List.fromList(utf8.encode(Uri.decodeComponent(payload)));
  } on FormatException {
    return null;
  }
}

String decodeStyleSheetText(Uint8List bytes) {
  // A byte order mark says UTF-16; style sheets are UTF-8 otherwise.
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return String.fromCharCodes(
      Uint16List.sublistView(Uint8List.fromList(bytes.sublist(2))),
    );
  }
  return utf8.decode(bytes, allowMalformed: true);
}
