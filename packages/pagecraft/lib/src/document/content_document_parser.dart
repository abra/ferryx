part of 'content_document.dart';

final _lineBreaks = RegExp(r'\r\n?');

/// XML line-end normalization: CRLF and a lone CR become LF.
String _foldLineBreaks(String text) => text.replaceAll(_lineBreaks, '\n');

const _entities = XmlDefaultEntityMapping.html5();

final _attributeWhitespace = RegExp('[\n\t]');

/// XML attribute-value normalization (XML 1.0 §3.3.3) of a value as
/// written: its line breaks (a CRLF one LF first) and tabs become
/// spaces, then references are decoded, so `&#xD;&#xA;` keeps its two
/// characters, as browsers keep them.
String _attributeValue(String raw) => _entities.decode(
  _foldLineBreaks(raw).replaceAll(_attributeWhitespace, ' '),
);

bool _isNamespaceDeclaration(String name) =>
    name == 'xmlns' || name.startsWith('xmlns:');

ContentDocument _parseXml(String source) {
  final builder = _ContentDocumentBuilder();
  try {
    // Values come raw: attribute values are normalized before their
    // references are decoded, text after.
    for (final event in xml_events.parseEvents(
      source,
      entityMapping: const XmlNullEntityMapping(),
      validateNesting: true,
    )) {
      switch (event) {
        case xml_events.XmlStartElementEvent():
          if (!builder.isOpen && builder.hasRoot) {
            throw const ContentParseException(
              'Content after the root element',
            );
          }
          builder.startElement(event.name, [
            for (final a in event.attributes)
              if (!_isNamespaceDeclaration(a.name))
                (a.name, _attributeValue(a.value)),
          ]);
          if (event.isSelfClosing) builder.endElement();
        case xml_events.XmlEndElementEvent():
          builder.endElement();
        case xml_events.XmlTextEvent():
          builder.text(_foldLineBreaks(_entities.decode(event.value)));
        case xml_events.XmlCDATAEvent():
          builder.text(_foldLineBreaks(event.value), cdata: true);
        default:
          // Comments, processing instructions, the declaration and the
          // doctype: not part of the tree CFIs see.
          break;
      }
    }
  } on XmlException catch (e) {
    throw ContentParseException(e.message);
  }
  if (!builder.hasRoot) {
    throw const ContentParseException('No root element');
  }
  if (builder.isOpen) {
    throw const ContentParseException('Unclosed element');
  }
  return builder.build();
}

ContentDocument _parseHtml(String source) {
  final document = html_parser.parse(source);
  final builder = _ContentDocumentBuilder();
  void walk(html_dom.Node node) {
    switch (node) {
      case html_dom.Element():
        builder.startElement(node.localName ?? '', [
          for (final entry in node.attributes.entries)
            if (!_isNamespaceDeclaration(entry.key.toString()))
              (entry.key.toString(), entry.value),
        ]);
        node.nodes.forEach(walk);
        builder.endElement();
      case html_dom.Text():
        builder.text(_foldLineBreaks(node.data));
      default:
        break;
    }
  }

  walk(document.documentElement!);
  return builder.build();
}
