/// Font obfuscation (`META-INF/encryption.xml`): the IDPF and Adobe
/// schemes, which XOR the first bytes of a resource with a key derived
/// from the package identifier. Other algorithms (DRM) are left as they
/// are, as `epub.js` leaves them.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import 'epub_metadata.dart';
import 'epub_xml.dart';

/// The resources the container obfuscates and how to undo it.
class EpubEncryption {
  EpubEncryption._(this._algorithmByUri, this._keys);

  /// Reads [encryption] (null when the container has none) against the
  /// package document [opf] the keys derive from.
  factory EpubEncryption.parse(XmlDocument? encryption, XmlDocument opf) {
    final byUri = <String, String>{};
    final keys = <String, Uint8List>{};
    if (encryption == null) return EpubEncryption._(byUri, keys);
    for (final data in encryption.findAllElements(
      'EncryptedData',
      namespace: EpubNamespace.enc,
    )) {
      final algorithm = data
          .findAllElements('EncryptionMethod', namespace: EpubNamespace.enc)
          .firstOrNull
          ?.getAttribute('Algorithm');
      final uri = data
          .findAllElements('CipherReference', namespace: EpubNamespace.enc)
          .firstOrNull
          ?.getAttribute('URI');
      if (algorithm == null || uri == null) continue;
      if (!keys.containsKey(algorithm)) {
        final key = switch (algorithm) {
          idpfAlgorithm => _idpfKey(opf),
          adobeAlgorithm => _adobeKey(opf),
          _ => null,
        };
        // Unknown algorithms stay listed but cannot be decoded.
        if (key == null) continue;
        keys[algorithm] = key;
      }
      byUri[uri] = algorithm;
    }
    return EpubEncryption._(byUri, keys);
  }

  static const idpfAlgorithm = 'http://www.idpf.org/2008/embedding';
  static const adobeAlgorithm = 'http://ns.adobe.com/pdf/enc#RC';

  final Map<String, String> _algorithmByUri;
  final Map<String, Uint8List> _keys;

  /// Whether the container obfuscates anything this can undo.
  bool get isEmpty => _algorithmByUri.isEmpty;

  /// Whether the resource at [uri] is obfuscated with a known scheme.
  bool isObfuscated(String uri) => _algorithmByUri.containsKey(uri);

  /// [bytes] of the resource at [uri], deobfuscated when needed. The
  /// bytes are modified in place when they are obfuscated.
  Uint8List decode(String uri, Uint8List bytes) {
    final algorithm = _algorithmByUri[uri];
    if (algorithm == null) return bytes;
    final key = _keys[algorithm]!;
    final length = algorithm == idpfAlgorithm ? 1040 : 1024;
    final count = length < bytes.length ? length : bytes.length;
    for (var i = 0; i < count; i++) {
      bytes[i] ^= key[i % key.length];
    }
    return bytes;
  }

  /// IDPF: SHA-1 of the unique identifier with whitespace removed.
  static Uint8List _idpfKey(XmlDocument opf) {
    final identifier = epubIdentifier(opf).replaceAll(RegExp('[ \t\r\n]'), '');
    return Uint8List.fromList(sha1.convert(utf8.encode(identifier)).bytes);
  }

  /// Adobe: the 16 bytes of the first UUID identifier.
  static Uint8List? _adobeKey(XmlDocument opf) {
    final uuid = epubUuid(opf).replaceAll('-', '');
    if (uuid.length < 32) return null;
    return Uint8List.fromList([
      for (var i = 0; i < 16; i++)
        int.parse(uuid.substring(i * 2, i * 2 + 2), radix: 16),
    ]);
  }
}
