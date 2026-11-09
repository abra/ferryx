import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/src/container/book_url.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  group('resolveBookUrl', () {
    test('resolves against the package document directory', () {
      expect(
        resolveBookUrl('text/ch1.xhtml', 'OEBPS/content.opf'),
        'OEBPS/text/ch1.xhtml',
      );
      expect(
        resolveBookUrl('../images/a.png', 'OEBPS/text/ch1.xhtml'),
        'OEBPS/images/a.png',
      );
      expect(resolveBookUrl('ch1.xhtml', 'content.opf'), 'ch1.xhtml');
      expect(
        resolveBookUrl('/abs/x.xhtml', 'OEBPS/content.opf'),
        'abs/x.xhtml',
      );
    });

    test('decodes escapes, keeps reserved ones, drops the query', () {
      expect(
        resolveBookUrl('chapter%201.xhtml', 'OEBPS/content.opf'),
        'OEBPS/chapter 1.xhtml',
      );
      expect(
        resolveBookUrl('ch%2C1.html', 'OPS/book.opf'),
        'OPS/ch,1.html',
        reason: 'calibre encodes commas it means raw',
      );
      expect(resolveBookUrl('a%3Ab.xhtml', 'x.opf'), 'a:b.xhtml');
      expect(resolveBookUrl('ch1.xhtml?x=1#frag', 'x.opf'), 'ch1.xhtml#frag');
      expect(
        resolveBookUrl('%D0%BA%D0%BD%D0%B8%D0%B3%D0%B0.xhtml', 'x.opf'),
        'книга.xhtml',
      );
    });

    test('an absolute URL or an absolute base resolves as a URL', () {
      expect(
        resolveBookUrl('https://example.com/a', 'OEBPS/content.opf'),
        'https://example.com/a',
      );
      expect(
        resolveBookUrl('b.css', 'https://example.com/dir/a.xhtml'),
        'https://example.com/dir/b.css',
      );
      expect(resolveBookUrl('b.css', 'OEBPS:odd/a.xhtml'), 'OEBPS:odd/b.css');
    });

    test('isExternalEpubUri sees schemes but not blobs', () {
      expect(isExternalEpubUri('https://x'), isTrue);
      expect(isExternalEpubUri('mailto:a@b'), isTrue);
      expect(isExternalEpubUri('blob:https://x'), isFalse);
      expect(isExternalEpubUri('text/ch1.xhtml'), isFalse);
      expect(isExternalEpubUri('#frag'), isFalse);
    });
  });

  group('decodeBookUri', () {
    test('matches decodeURI: reserved characters stay encoded', () {
      expect(decodeBookUri('a%20b'), 'a b');
      expect(decodeBookUri('a%2Cb'), 'a%2Cb');
      expect(decodeBookUri('a%2Fb%3Fc%23d'), 'a%2Fb%3Fc%23d');
      expect(decodeBookUri('%D0%96'), 'Ж');
      expect(decodeBookUri('100%'), '100%');
      expect(decodeBookUri('%zz'), '%zz');
      expect(decodeBookUri('plain'), 'plain');
    });
  });

  group('paths', () {
    test('dirname and relative paths', () {
      expect(epubPathDirname('OEBPS/text/a.xhtml'), 'OEBPS/text/');
      expect(epubPathDirname('a.xhtml'), '');
      expect(epubPathRelative('', 'a/b'), 'a/b');
      expect(epubPathRelative('a/b', 'a/c'), '../c');
      expect(epubPathRelative('a/b/', 'a/b'), '');
      expect(epubPathRelative('a', 'a/b/c'), 'b/c');
      expect(epubPathRelative('x/y/z', 'x/w'), '../../w');
    });
  });
}
