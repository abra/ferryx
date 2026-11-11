import 'dart:convert';
import 'dart:typed_data';

import 'package:pagecraft/testing.dart';

const smokeText = 'Ferryx document smoke';

Uint8List epubFixture({bool fixed = false, bool vertical = false}) {
  final archive = ZipBuilder()
    ..add('mimetype', ascii.encode('application/epub+zip'))
    ..add(
      'META-INF/container.xml',
      utf8.encode('''
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
  <rootfiles><rootfile full-path="book.opf"
    media-type="application/oebps-package+xml"/></rootfiles>
</container>'''),
    )
    ..add(
      'book.opf',
      utf8.encode('''
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Ferryx smoke</dc:title><dc:language>en</dc:language>
    ${fixed ? '<meta property="rendition:layout">pre-paginated</meta>' : ''}
  </metadata>
  <manifest>
    <item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>
    <item id="two" href="two.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="one"/><itemref idref="two"/></spine>
</package>'''),
    );
  for (final chapter in ['one', 'two']) {
    archive.add(
      '$chapter.xhtml',
      utf8.encode('''
<html xmlns="http://www.w3.org/1999/xhtml"><head>
  <title>$chapter</title>
  ${vertical ? '<style>body { writing-mode: vertical-rl; }</style>' : ''}
</head><body><p>$smokeText $chapter.</p></body></html>'''),
    );
  }
  return archive.build();
}

Uint8List fb2Fixture({bool notes = false}) => Uint8List.fromList(
  utf8.encode('''
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
  <description><title-info><book-title>Ferryx smoke</book-title>
    <lang>en</lang></title-info></description>
  <body><section><p>$smokeText one.</p></section>
    <section><p>$smokeText two.</p></section></body>
  ${notes ? '<body name="notes"><section id="note"><p>Footnote.</p></section></body>' : ''}
</FictionBook>'''),
);

Uint8List epubReadingOrderFixture(List<bool> readingOrder) {
  final archive = ZipBuilder()
    ..add('mimetype', ascii.encode('application/epub+zip'))
    ..add(
      'META-INF/container.xml',
      utf8.encode('''
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
  <rootfiles><rootfile full-path="book.opf"
    media-type="application/oebps-package+xml"/></rootfiles>
</container>'''),
    )
    ..add(
      'book.opf',
      utf8.encode('''
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Reading order</dc:title><dc:language>en</dc:language>
  </metadata>
  <manifest>
    ${[for (var i = 0; i < readingOrder.length; i++) '<item id="s$i" href="$i.xhtml" media-type="application/xhtml+xml"/>'].join()}
  </manifest>
  <spine>
    ${[for (var i = 0; i < readingOrder.length; i++) '<itemref idref="s$i" linear="${readingOrder[i] ? 'yes' : 'no'}"/>'].join()}
  </spine>
</package>'''),
    );
  for (var i = 0; i < readingOrder.length; i++) {
    archive.add(
      '$i.xhtml',
      utf8.encode('''
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Section $i</title></head>
<body><p>$smokeText section $i.</p></body></html>'''),
    );
  }
  return archive.build();
}

Uint8List zippedFb2Fixture() =>
    (ZipBuilder()..add('book.fb2', fb2Fixture(), deflate: true)).build();

Uint8List mobiFixture({bool kf8 = false}) {
  if (!kf8) {
    return (MobiBuilder(title: 'Ferryx smoke', compress: true)..addText(
          utf8.encode(
            '<html><body><p>$smokeText one.</p><mbp:pagebreak/>'
            '<p>$smokeText two.</p></body></html>',
          ),
        ))
        .build();
  }
  const skeleton = '<html><body><div aid="A"></div></body></html>';
  const fragment = '<p>$smokeText KF8.</p>';
  const text = skeleton + fragment;
  final builder = MobiBuilder(title: 'Ferryx smoke KF8', version: 8)
    ..addText(utf8.encode(text))
    ..setFlows([(0, text.length)])
    ..setSkeletons([
      (
        name: 'SKEL0000000000',
        numFragments: 1,
        offset: 0,
        length: skeleton.length,
      ),
    ])
    ..setFragments(
      [
        (
          insertOffset: skeleton.indexOf('</div>') + '</div>'.length,
          selector: 0,
          fid: 0,
          offset: 0,
          length: fragment.length,
        ),
      ],
      cncx: ["P-//*[@aid='A']/0"],
    );
  return builder.build();
}

Uint8List comicFixture() => buildComicArchive([
  (name: '001.png', width: 40, height: 60),
  (name: '002.png', width: 60, height: 40),
]);

/// A PDF with two pages of original rectangle artwork and a real xref table.
Uint8List pdfFixture({bool searchable = false}) {
  final stream =
      '0 0 0 rg 20 20 120 200 re f\n${searchable ? 'BT /F1 12 Tf 20 220 Td (Ferryx searchable text) Tj ET\n' : ''}';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    for (var page = 0; page < 2; page++)
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 160 240] '
          '/Resources << /Font << /F1 6 0 R >> >> /Contents 5 0 R >>',
    '<< /Length ${stream.length} >>\nstream\n${stream}endstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(ascii.encode(out.toString()));
}

/// The original black rectangle page from Pagecraft's generated DjVu fixture.
/// No third-party book. Provenance and generator at the dependency's pinned
/// commit: packages/pagecraft/test/formats/djvu/generate_fixture.py,
/// https://github.com/abra/readflex/tree/99bedcfdd246d8570f89744034f098dec7312063
Uint8List djvuFixture() => base64Decode(
  'QVQmVEZPUk0AAABuREpWVUlORk8AAAAKAlgDhBgALAEWAVNqYnoAAABQgDpukFa1KuoAyWu8ie+4'
  'x5JdMNoBVCr4o8L//5TUl//8B5P79tgpDCbf//6c52w1RhYn9gQVi4Gw4jORPxLkmQ2/+j4/5RT'
  '5mgyYzQzRr6s=',
);
