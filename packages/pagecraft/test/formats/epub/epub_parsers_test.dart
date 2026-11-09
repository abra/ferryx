import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/src/container/book_url.dart';
import 'package:pagecraft/all_formats.dart';
import 'package:xml/xml.dart';

void main() {
  group('normalizeWhitespace', () {
    test('strips and collapses ASCII whitespace only', () {
      expect(normalizeWhitespace('  a \n\t b  '), 'a b');
      expect(normalizeWhitespace('a b'), 'a b');
      expect(normalizeWhitespace(null), '');
      expect(normalizeWhitespace(''), '');
    });
  });

  group('parseEpubClock', () {
    test('reads SMIL clock values in seconds', () {
      expect(parseEpubClock('0:01:30'), 90);
      expect(parseEpubClock('1:30'), 90);
      expect(parseEpubClock('45.5s'), 45.5);
      expect(parseEpubClock('2min'), 120);
      expect(parseEpubClock('1h'), 3600);
      expect(parseEpubClock('500ms'), closeTo(0.5, 1e-9));
      expect(parseEpubClock('12'), 12);
      expect(parseEpubClock(''), isNull);
      expect(parseEpubClock('x'), isNull);
    });
  });

  group('parseEpubNav', () {
    test(
      'reads a nav without the XHTML namespace and uses title fallbacks',
      () {
        final doc = XmlDocument.parse('''
<html><body>
<nav epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops"><ol>
  <li><a href="a.xhtml" title="Titled"><img src="x.png"/></a></li>
  <li><span>Heading</span><ol><li><a href="b.xhtml#x">  B  </a></li></ol></li>
</ol></nav>
</body></html>''');
        final nav = parseEpubNav(doc, resolve: (h) => 'OEBPS/$h');
        expect(nav.toc, [
          const BookNavItem(label: 'Titled', href: 'OEBPS/a.xhtml'),
          const BookNavItem(
            label: 'Heading',
            href: null,
            subitems: [BookNavItem(label: 'B', href: 'OEBPS/b.xhtml#x')],
          ),
        ]);
        expect(nav.pageList, isNull);
        expect(nav.landmarks, isNull);
      },
    );

    test('the first toc wins and other navs are kept with their headings', () {
      final doc = XmlDocument.parse('''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
<nav epub:type="toc"><ol><li><a href="one.xhtml">One</a></li></ol></nav>
<nav epub:type="toc"><ol><li><a href="two.xhtml">Two</a></li></ol></nav>
<nav epub:type="loi"><h2>Illustrations</h2><ol><li><a href="one.xhtml#fig">Fig</a></li></ol></nav>
</body></html>''');
      final nav = parseEpubNav(doc);
      expect(nav.toc!.single.label, 'One');
      expect(nav.others.single.label, 'Illustrations');
      expect(nav.others.single.type, ['loi']);
      expect(nav.others.single.list!.single.href, 'one.xhtml#fig');
    });
  });

  group('parseEpubNcx', () {
    test('a navPoint without a target takes the first target below', () {
      final doc = XmlDocument.parse('''
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/">
<navMap>
  <navPoint><navLabel><text>Part</text></navLabel>
    <navPoint><navLabel><text>Empty</text></navLabel></navPoint>
    <navPoint><navLabel><text>Ch</text></navLabel><content src="c.html"/></navPoint>
  </navPoint>
</navMap>
</ncx>''');
      final ncx = parseEpubNcx(doc);
      final part = ncx.toc!.single;
      expect(part.href, 'c.html');
      expect(part.subitems!.first.href, isNull);
      expect(part.subitems!.last.href, 'c.html');
      expect(ncx.pageList, isNull);
      expect(ncx.others, isEmpty);
    });

    test('an empty src is no target either, as in epub.js', () {
      // Seen in the wild: `<content src=""/>` on a part heading.
      final doc = XmlDocument.parse('''
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/">
<navMap>
  <navPoint><navLabel><text>Part</text></navLabel><content src=""/>
    <navPoint><navLabel><text>Ch</text></navLabel><content src="Text/c.html#p1"/></navPoint>
  </navPoint>
</navMap>
</ncx>''');
      final ncx = parseEpubNcx(
        doc,
        resolve: (href) => resolveBookUrl(href, 'OEBPS/toc.ncx'),
      );
      final part = ncx.toc!.single;
      expect(part.href, 'OEBPS/Text/c.html#p1');
      expect(part.subitems!.single.href, 'OEBPS/Text/c.html#p1');
    });
  });

  group('parseEpubMetadata', () {
    test('a package without metadata gives empty values', () {
      final doc = XmlDocument.parse(
        '<package xmlns="http://www.idpf.org/2007/opf"><manifest/><spine/></package>',
      );
      final metadata = parseEpubMetadata(doc);
      expect(metadata.metadata.title, isNull);
      expect(metadata.metadata.identifier, '');
      expect(metadata.metadata.contributors, isEmpty);
      expect(metadata.rendition, isEmpty);
    });

    test('a UUID anywhere in an identifier is found for Adobe keys', () {
      final doc = XmlDocument.parse('''
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="a"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="a">isbn:1</dc:identifier>
<dc:identifier>urn:uuid:A1B2C3D4-E5F6-7890-ABCD-EF1234567890</dc:identifier>
<dc:identifier>urn:uuid:a1b2c3d4-e5f6-7890-abcd-ef1234567890</dc:identifier>
</metadata></package>''');
      expect(epubIdentifier(doc), 'isbn:1');
      expect(
        epubUuid(doc),
        'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        reason: 'uppercase is not a UUID for epub.js either',
      );
    });
  });

  group('EpubEncryption', () {
    final opf = XmlDocument.parse('''
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="a"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="a"> id with spaces </dc:identifier>
</metadata></package>''');

    test('without encryption nothing is obfuscated', () {
      final encryption = EpubEncryption.parse(null, opf);
      expect(encryption.isEmpty, isTrue);
      final bytes = Uint8List.fromList([1, 2, 3]);
      expect(encryption.decode('x', bytes), same(bytes));
    });

    test('Adobe obfuscation without a UUID cannot be decoded', () {
      final encryption = EpubEncryption.parse(
        XmlDocument.parse('''
<encryption xmlns:enc="http://www.w3.org/2001/04/xmlenc#"><enc:EncryptedData>
<enc:EncryptionMethod Algorithm="http://ns.adobe.com/pdf/enc#RC"/>
<enc:CipherData><enc:CipherReference URI="f.ttf"/></enc:CipherData>
</enc:EncryptedData></encryption>'''),
        opf,
      );
      expect(encryption.isObfuscated('f.ttf'), isFalse);
    });

    test(
      'IDPF keys ignore whitespace in the identifier and XOR 1040 bytes',
      () {
        final encryption = EpubEncryption.parse(
          XmlDocument.parse('''
<encryption xmlns:enc="http://www.w3.org/2001/04/xmlenc#"><enc:EncryptedData>
<enc:EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>
<enc:CipherData><enc:CipherReference URI="f.ttf"/></enc:CipherData>
</enc:EncryptedData></encryption>'''),
          opf,
        );
        expect(encryption.isObfuscated('f.ttf'), isTrue);
        final plain = Uint8List.fromList(List.generate(1100, (i) => i % 256));
        final obfuscated = encryption.decode(
          'f.ttf',
          Uint8List.fromList(plain),
        );
        expect(
          obfuscated.sublist(1040),
          plain.sublist(1040),
          reason: 'bytes past 1040 are untouched',
        );
        expect(obfuscated.sublist(0, 1040), isNot(plain.sublist(0, 1040)));
        // XOR is its own inverse: decoding again restores the bytes.
        expect(encryption.decode('f.ttf', obfuscated), plain);
      },
    );
  });
}
