import 'dart:convert';
import 'dart:typed_data';

import 'package:pagecraft/testing.dart';

/// The two books the MOBI tests and the browser parity fixtures share,
/// built deterministically so the committed files can be checked
/// against the builder.
class MobiFixtureBooks {
  MobiFixtureBooks._();

  // MOBI 6: ten-digit placeholders keep every offset fixed; they are
  // filled with the byte offsets of the targets they name, in order.
  static const _template =
      '<html><head><guide><reference type="toc" title="Table of Contents" filepos="0000000000"/>'
      '<reference type="text" title="Start" filepos="0000000000"/></guide></head><body>'
      '<p>Cover page.</p><mbp:pagebreak/>'
      '<p height="2em"><a filepos="0000000000">Chapter One</a></p>'
      '<blockquote><p><a filepos="0000000000">Section 1.1</a></p></blockquote>'
      '<p><a filepos="0000000000">Chapter Two</a></p>'
      '<mbp:pagebreak />'
      '<h1>Chapter One</h1><p>First chapter text &amp; more.</p><img recindex="00001" /><p>Padding text to move offsets.</p>'
      '<h2>Section 1.1</h2><p>Section text.</p><mbp:pagebreak/>'
      '<h1>Chapter Two</h1><p>Second chapter.</p></body></html>';

  static final tocPos = _template.indexOf('<p height="2em">');
  static final onePos = _template.indexOf('<h1>Chapter One</h1>');
  static final sectionPos = _template.indexOf('<h2>Section 1.1</h2>');
  static final twoPos = _template.indexOf('<h1>Chapter Two</h1>');

  static String filepos(int offset) => offset.toString().padLeft(10, '0');

  static final String mobi6Html = () {
    final targets = [tocPos, onePos, onePos, sectionPos, twoPos];
    var filled = 0;
    return _template.replaceAllMapped(
      'filepos="0000000000"',
      (_) => 'filepos="${filepos(targets[filled++])}"',
    );
  }();

  static Uint8List mobi6() {
    final builder = MobiBuilder(
      title: 'Built MOBI',
      compress: true,
      trailingMultibyte: true,
      exth: [
        MobiExthRecord.string(100, 'Ada &amp; Grace'),
        MobiExthRecord.string(100, 'Alan'),
        MobiExthRecord.string(101, 'Press &#8212; House'),
        MobiExthRecord.string(103, 'A built book'),
        MobiExthRecord.string(105, 'Testing'),
        MobiExthRecord.string(106, '2024-01-02'),
        MobiExthRecord.string(108, 'Helper'),
        MobiExthRecord.string(109, 'CC0'),
        MobiExthRecord.string(503, 'Built MOBI &lt;Updated&gt;'),
        MobiExthRecord.string(524, 'en-GB'),
        MobiExthRecord.uint(201, 0),
      ],
    );
    builder.addText(utf8.encode(mobi6Html));
    builder.addResource([0xFF, 0xD8, 0xFF, 0xE0, 0x4A, 0x50, 0x47]);
    return builder.build();
  }

  // KF8.
  static const skeleton1 =
      '<html><head><title>One</title></head><body><div aid="A"></div></body></html>';
  static const fragment1 = '<p id="p1">First fragment.</p>';
  static const fragment2 =
      '<p aid="B">Second fragment with <a href="kindle:pos:fid:0001:off:0000000000">a link</a>.</p>';
  static const skeleton2 = '<html><body></body></html>';
  static const fragment3 = '<p name="named">Third.</p>';
  static const css = 'p { color: red; }';
  static const kf8Text =
      skeleton1 + fragment1 + fragment2 + skeleton2 + fragment3 + css;

  static Uint8List kf8() {
    final insert1 = skeleton1.indexOf('</div>') + '</div>'.length;
    const skel1Offset = 0;
    final skel2Offset = skeleton1.length + fragment1.length + fragment2.length;
    final cncx = [
      "P-//*[@aid='A']/0",
      "P-//*[@aid='A']/1",
      "P-//*[@aid='C']/0",
      'Chapter One',
      'Section',
      'Chapter Two',
      'Start here',
    ];
    final offsets = MobiBuilder.cncxOffsets(cncx);
    final builder = MobiBuilder(
      title: 'Built KF8',
      version: 8,
      exth: [
        MobiExthRecord.string(503, 'Built KF8'),
        MobiExthRecord.string(100, 'Someone'),
        MobiExthRecord.string(527, 'rtl'),
        MobiExthRecord.string(122, 'true'),
        MobiExthRecord.string(126, '1200x1600'),
      ],
    );
    builder.addText(utf8.encode(kf8Text));
    final flowEnd = skel2Offset + skeleton2.length + fragment3.length;
    builder.setFlows([(0, flowEnd), (flowEnd, kf8Text.length)]);
    builder.setSkeletons([
      (
        name: 'SKEL0000000000',
        numFragments: 2,
        offset: skel1Offset,
        length: skeleton1.length,
      ),
      (
        name: 'SKEL0000000001',
        numFragments: 1,
        offset: skel2Offset,
        length: skeleton2.length,
      ),
      (
        name: 'SKEL0000000002',
        numFragments: 0,
        offset: kf8Text.length,
        length: 0,
      ),
    ]);
    builder.setFragments([
      (
        insertOffset: insert1,
        selector: offsets[0],
        fid: 0,
        offset: 0,
        length: fragment1.length,
      ),
      (
        insertOffset: insert1 + fragment1.length,
        selector: offsets[1],
        fid: 1,
        offset: fragment1.length,
        length: fragment2.length,
      ),
      (
        insertOffset: skel2Offset + '<html><body>'.length,
        selector: offsets[2],
        fid: 2,
        offset: 0,
        length: fragment3.length,
      ),
    ], cncx: cncx);
    builder.setNcx([
      (
        name: '00',
        label: offsets[3],
        level: 0,
        fid: 0,
        off: 0,
        parent: null,
        firstChild: 1,
        lastChild: 1,
      ),
      (
        name: '01',
        label: offsets[4],
        level: 1,
        fid: 1,
        off: 0,
        parent: 0,
        firstChild: null,
        lastChild: null,
      ),
      (
        name: '02',
        label: offsets[5],
        level: 0,
        fid: 2,
        off: 0,
        parent: null,
        firstChild: null,
        lastChild: null,
      ),
    ], cncx: cncx);
    builder.setGuide([(type: 'text', label: offsets[6], fid: 0)], cncx: cncx);
    final resc = BytesBuilder()
      ..add(ascii.encode('RESC'))
      ..add(Uint8List(12))
      ..add(
        utf8.encode(
          '<?xml version="1.0"?><spine><itemref skelid="0" properties="page-spread-left"/><itemref skelid="1" properties="rendition:page-spread-center"/></spine>',
        ),
      );
    builder.addResource(resc.toBytes());
    builder.addResource([0x89, 0x50, 0x4E, 0x47]);
    return builder.build();
  }
}
