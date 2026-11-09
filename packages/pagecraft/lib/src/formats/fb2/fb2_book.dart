/// FictionBook 2: the port of `fb2.js`. The FB2 tree is converted to the
/// same XHTML `fb2.js` built in the browser, one document per top-level
/// element of the first body and one per further body (notes), so the
/// CFIs the WebView reader saved for FB2 books resolve in the same
/// elements here.
///
/// The conversion is a table of element rules (`STYLE`, `SECTION`,
/// `POEM`, `TABLE`, `BODY` in `fb2.js`): each FB2 element becomes an
/// XHTML element with its original name as a class, its `id` kept, a few
/// attributes copied, and its children converted by the rule's child
/// table. Images become `img` with `data:` URIs for inline binaries.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

import '../../container/zip_archive.dart';
import '../../text/charsets.dart';
import '../../pagecraft_exception.dart';
import '../book_navigation.dart';
import '../../text/whitespace.dart';

/// A person from `title-info` or `document-info`.
@immutable
class Fb2Person {
  const Fb2Person({required this.name, this.sortAs, this.role});

  final String name;

  /// `Last, First Middle`, or null without a last name or for nicknames.
  final String? sortAs;

  /// `bkp` for document-info contributors, as `fb2.js` marks them.
  final String? role;

  @override
  bool operator ==(Object other) =>
      other is Fb2Person &&
      other.name == name &&
      other.sortAs == sortAs &&
      other.role == role;

  @override
  int get hashCode => Object.hash(name, sortAs, role);

  @override
  String toString() => 'Fb2Person($name, $sortAs, $role)';
}

/// What `fb2.js` reports as `book.metadata`.
@immutable
class Fb2Metadata {
  const Fb2Metadata({
    required this.title,
    required this.identifier,
    required this.language,
    required this.authors,
    required this.translators,
    required this.contributors,
    required this.publisher,
    required this.published,
    required this.modified,
    required this.description,
    required this.subjects,
  });

  final String title;
  final String identifier;
  final String language;
  final List<Fb2Person> authors;
  final List<Fb2Person> translators;
  final List<Fb2Person> contributors;
  final String publisher;
  final String published;
  final String modified;

  /// The annotation as XHTML (the inner markup of a converted `div`), or
  /// null without one.
  final String? description;
  final List<String> subjects;
}

/// Cover image bytes with their media type.
@immutable
class Fb2Cover {
  const Fb2Cover({required this.bytes, required this.mediaType});

  final Uint8List bytes;
  final String? mediaType;
}

/// One reading unit: a top-level element of the first body, or a whole
/// further body (notes, comments), which is not linear.
class Fb2Section {
  Fb2Section._({
    required this.index,
    required XmlElement element,
    required this.ids,
    required this.title,
    required this.titles,
    required this.size,
    required this.isLinear,
  }) : _element = element;

  final int index;
  final XmlElement _element;

  /// The ids of the elements in this section, for links.
  final List<String> ids;

  /// The label the table of contents shows.
  final String title;

  /// Titles of the direct subsections, numbered for `index#n` links.
  final List<String> titles;

  /// The XHTML document's size in bytes without image data, the weight
  /// the progress model uses.
  final int size;
  final bool isLinear;

  /// The converted element, inside the body of the document [xhtml]
  /// wraps it in.
  XmlElement get element => _element;

  /// The section as a complete XHTML document, as the WebView reader
  /// loaded it (without its stylesheet link, which styles supply).
  String get xhtml => _wrap(_element.toXmlString());

  static String _wrap(String body) =>
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml">\n'
      '    <head></head>\n'
      '    <body>$body</body>\n'
      '</html>';

  @override
  String toString() => 'Fb2Section($index, "$title", $size bytes)';
}

/// Where a link points inside an FB2 book.
@immutable
sealed class Fb2HrefTarget {
  const Fb2HrefTarget(this.index);

  /// The section index, or -1 for an id no section has.
  final int index;
}

/// A table-of-contents link `index#n`: the n-th subsection title,
/// marked `data-foliate-id="n"` in the section's XHTML.
class Fb2TocTarget extends Fb2HrefTarget {
  const Fb2TocTarget(super.index, this.titleIndex);

  final int? titleIndex;
}

/// A link `#id` from the text: the element with that id.
class Fb2IdTarget extends Fb2HrefTarget {
  const Fb2IdTarget(super.index, this.id);

  final String id;
}

/// The attribute `fb2.js` numbers subsection titles with.
const fb2DataIdAttribute = 'data-foliate-id';

const _xlink = 'http://www.w3.org/1999/xlink';

/// An opened FB2 book.
class Fb2Book {
  Fb2Book._({
    required this.metadata,
    required this.sections,
    required this.toc,
    required Map<String, XmlElement> binaries,
    required XmlElement? coverImage,
    required Map<String, int> idMap,
  }) : _binaries = binaries,
       _coverImage = coverImage,
       _idMap = idMap;

  /// Opens [path]: a `.fb2` file, or a ZIP (`.fb2.zip`, `.fbz`) whose
  /// first `.fb2` entry is the book, as the WebView reader opened them.
  static Future<Fb2Book> open(String path) async {
    final archive = await _tryOpenZip(path);
    if (archive != null) {
      try {
        final entry = archive.entries
            .where((e) => e.name.toLowerCase().endsWith('.fb2'))
            .firstOrNull;
        if (entry == null) {
          throw const PagecraftException('No .fb2 entry in the archive');
        }
        return Fb2Book.parse(await archive.read(entry));
      } finally {
        await archive.close();
      }
    }
    final file = await _readFile(path);
    return Fb2Book.parse(file);
  }

  /// Parses the bytes of an FB2 file, honouring the XML declaration's
  /// encoding (`windows-1251` and friends are common).
  factory Fb2Book.parse(Uint8List bytes) {
    final text = decodeFb2Text(bytes);
    final XmlDocument document;
    try {
      document = XmlDocument.parse(text);
    } on XmlException catch (error) {
      throw PagecraftException('FB2 parsing error: ${error.message}');
    }
    return Fb2Book.fromDocument(document);
  }

  /// Converts a parsed FB2 document.
  factory Fb2Book.fromDocument(XmlDocument document) {
    final root = document.rootElement;
    final binaries = <String, XmlElement>{
      for (final binary in root.findAllElements('binary'))
        ?binary.getAttribute('id'): binary,
    };
    final converter = _Fb2Converter(binaries);

    XmlElement? find(List<String> path) => _find(root, path);
    List<XmlElement> findAll(List<String> path) => _findAll(root, path);

    final titleInfo = find(['description', 'title-info']);
    final documentInfo = find(['description', 'document-info']);
    final publishInfo = find(['description', 'publish-info']);
    String text(List<String> path, [XmlElement? from]) =>
        _text(from == null ? find(path) : _find(from, path));
    String date(XmlElement? element) =>
        element?.getAttribute('value') ?? _text(element);
    final annotation = titleInfo == null
        ? null
        : _find(titleInfo, ['annotation']);
    final metadata = Fb2Metadata(
      title: titleInfo == null ? '' : text(['book-title'], titleInfo),
      identifier: documentInfo == null ? '' : text(['id'], documentInfo),
      language: titleInfo == null ? '' : text(['lang'], titleInfo),
      authors: [
        if (titleInfo != null)
          for (final author in _findAll(titleInfo, ['author'])) _person(author),
      ],
      translators: [
        if (titleInfo != null)
          for (final translator in _findAll(titleInfo, ['translator']))
            _person(translator),
      ],
      contributors: [
        if (documentInfo != null) ...[
          for (final author in _findAll(documentInfo, ['author']))
            _person(author, role: 'bkp'),
          // Not strictly a producer, but calibre writes it so (fb2.js).
          for (final program in _findAll(documentInfo, ['program-used']))
            Fb2Person(name: _text(program), role: 'bkp'),
        ],
      ],
      publisher: publishInfo == null ? '' : text(['publisher'], publishInfo),
      published: titleInfo == null ? '' : date(_find(titleInfo, ['date'])),
      modified: documentInfo == null ? '' : date(_find(documentInfo, ['date'])),
      description: annotation == null
          ? null
          : (converter.convert(annotation, {
                      'annotation': _Rule('div', _section),
                    })!
                    as XmlElement)
                .children
                .map((n) => n.toXmlString())
                .join(),
      subjects: [
        if (titleInfo != null)
          for (final genre in _findAll(titleInfo, ['genre'])) _text(genre),
      ],
    );
    final coverImage = titleInfo == null
        ? null
        : _find(titleInfo, ['coverpage', 'image']);

    // Convert each body; the first body's children are sections, every
    // further body is one non-linear section of notes.
    final bodies = findAll(['body']);
    final sections = <Fb2Section>[];
    final idMap = <String, int>{};
    XmlElement? firstBody;
    for (var b = 0; b < bodies.length; b++) {
      final converted =
          converter.convert(bodies[b], {'body': _Rule('body', _body)})!
              as XmlElement;
      if (b == 0) {
        firstBody = converted;
        for (final child in converted.childElements.toList()) {
          final titles = <String>[];
          for (final section in child.childElements) {
            if (section.name.local != 'section') continue;
            for (final title in section.childElements) {
              if (_hasClass(title, 'title')) {
                title.setAttribute(fb2DataIdAttribute, '${titles.length}');
                titles.add(_text(title));
              }
            }
          }
          sections.add(
            _makeSection(child, sections.length, titles, isLinear: true),
          );
        }
      } else {
        converted.setAttribute('class', 'body notesBodyType');
        sections.add(
          _makeSection(converted, sections.length, const [], isLinear: false),
        );
      }
    }
    for (final section in sections) {
      for (final id in section.ids) {
        idMap[id] = section.index;
      }
    }
    // Sections are detached from their body so each is its own document.
    firstBody?.children.clear();

    final toc = <BookNavItem>[
      for (final section in sections)
        BookNavItem(
          label: section.title,
          href: '${section.index}',
          subitems: section.titles.isEmpty
              ? null
              : [
                  for (var i = 0; i < section.titles.length; i++)
                    BookNavItem(
                      label: section.titles[i],
                      href: '${section.index}#$i',
                    ),
                ],
        ),
    ];

    return Fb2Book._(
      metadata: metadata,
      sections: sections,
      toc: toc,
      binaries: binaries,
      coverImage: coverImage,
      idMap: idMap,
    );
  }

  final Fb2Metadata metadata;
  final List<Fb2Section> sections;
  final List<BookNavItem> toc;
  final Map<String, XmlElement> _binaries;
  final XmlElement? _coverImage;
  final Map<String, int> _idMap;

  /// The cover from `coverpage`, or null.
  Fb2Cover? readCover() {
    final image = _coverImage;
    if (image == null) return null;
    final href = _attributeNs(image, _xlink, 'href');
    if (href == null) return null;
    final hash = href.indexOf('#');
    if (hash < 0) return null;
    final binary = _binaries[href.substring(hash + 1)];
    if (binary == null) return null;
    final bytes = readBinary(href.substring(hash + 1));
    if (bytes == null) return null;
    return Fb2Cover(
      bytes: bytes,
      mediaType: binary.getAttribute('content-type'),
    );
  }

  /// The decoded bytes of the `binary` with [id], or null.
  Uint8List? readBinary(String id) {
    final binary = _binaries[id];
    if (binary == null) return null;
    try {
      return base64.decode(binary.innerText.replaceAll(RegExp(r'\s'), ''));
    } on FormatException {
      return null;
    }
  }

  /// Where [href] points: `index#n` from the table of contents, or `#id`
  /// from the text (`resolveHref`).
  Fb2HrefTarget resolveHref(String href) {
    final hash = href.indexOf('#');
    final a = hash < 0 ? href : href.substring(0, hash);
    final b = hash < 0 ? null : href.substring(hash + 1);
    if (a.isNotEmpty) {
      return Fb2TocTarget(
        int.tryParse(a) ?? -1,
        b == null ? null : int.tryParse(b),
      );
    }
    final id = b ?? '';
    return Fb2IdTarget(_idMap[id] ?? -1, id);
  }

  /// Whether [uri] has a scheme (`isExternal`).
  bool isExternal(String uri) =>
      RegExp(r'^\w+:', caseSensitive: false).hasMatch(uri);

  static Fb2Section _makeSection(
    XmlElement element,
    int index,
    List<String> titles, {
    required bool isLinear,
  }) {
    final ids = <String>[
      ?element.getAttribute('id'),
      for (final descendant in element.descendantElements)
        ?descendant.getAttribute('id'),
    ];
    // The label: the first title, subtitle or paragraph in document
    // order, or the element's own text when it is a title.
    XmlElement? labelSource;
    for (final descendant in element.descendantElements) {
      if (_hasClass(descendant, 'title') ||
          _hasClass(descendant, 'subtitle') ||
          descendant.name.local == 'p') {
        labelSource = descendant;
        break;
      }
    }
    final title = normalizeWhitespace(
      labelSource?.innerText ??
          (_hasClass(element, 'title') ? element.innerText : ''),
    );
    final xhtml = Fb2Section._wrap(element.toXmlString());
    var srcLength = 0;
    for (final descendant in element.descendantElements) {
      srcLength += descendant.getAttribute('src')?.length ?? 0;
    }
    return Fb2Section._(
      index: index,
      element: element,
      ids: ids,
      title: title,
      titles: titles,
      size: utf8.encode(xhtml).length - srcLength,
      isLinear: isLinear,
    );
  }

  static Fb2Person _person(XmlElement element, {String? role}) {
    final nick = _text(_find(element, ['nickname']));
    if (nick.isNotEmpty) return Fb2Person(name: nick, role: role);
    final first = _text(_find(element, ['first-name']));
    final middle = _text(_find(element, ['middle-name']));
    final last = _text(_find(element, ['last-name']));
    final name = [first, middle, last].where((x) => x.isNotEmpty).join(' ');
    final sortAs = last.isEmpty
        ? null
        : [
            last,
            [first, middle].where((x) => x.isNotEmpty).join(' '),
          ].join(', ');
    return Fb2Person(name: name, sortAs: sortAs, role: role);
  }

  static Future<ZipArchive?> _tryOpenZip(String path) async {
    final head = await _readHead(path, 4);
    if (head.length < 4 || head[0] != 0x50 || head[1] != 0x4B) return null;
    return ZipArchive.open(path);
  }
}

/// Decodes FB2 bytes by their XML declaration, as `fb2.js` re-decodes a
/// file whose declaration names another charset than UTF-8.
String decodeFb2Text(Uint8List bytes) {
  final head = utf8.decode(
    Uint8List.sublistView(bytes, 0, bytes.length < 256 ? bytes.length : 256),
    allowMalformed: true,
  );
  final declared = _declaration.firstMatch(head)?.group(1);
  if (declared == null || declared.toLowerCase() == 'utf-8') {
    return _stripBom(utf8.decode(bytes, allowMalformed: true));
  }
  return _stripBom(decodeCharset(bytes, declared));
}

final _declaration = RegExp(
  '''^<\\?xml\\s+version\\s*=\\s*["']1\\.\\d+["']\\s+encoding\\s*=\\s*["']([A-Za-z0-9._-]*)["']''',
);

String _stripBom(String text) =>
    text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF ? text.substring(1) : text;

// The conversion rules of fb2.js as data.

/// How one FB2 element converts: the XHTML tag, the rules for its
/// children (or [self] to reuse the current table) and the attributes
/// copied over. A [handler] names a special conversion instead.
class _Rule {
  const _Rule(this.tag, [this.children, this.attributes]) : handler = null;

  const _Rule.special(this.handler)
    : tag = '',
      children = null,
      attributes = null;

  final String tag;
  final Object? children;
  final List<String>? attributes;
  final String? handler;

  static const self = 'self';
}

const _style = <String, _Rule>{
  'strong': _Rule('strong', _Rule.self),
  'emphasis': _Rule('em', _Rule.self),
  'style': _Rule('span', _Rule.self),
  'a': _Rule.special('anchor'),
  'strikethrough': _Rule('s', _Rule.self),
  'sub': _Rule('sub', _Rule.self),
  'sup': _Rule('sup', _Rule.self),
  'code': _Rule('code', _Rule.self),
  'image': _Rule.special('image'),
};

const _cellAttributes = ['colspan', 'rowspan', 'align', 'valign'];

const _table = <String, _Rule>{
  'tr': _Rule(
    'tr',
    <String, _Rule>{
      'th': _Rule('th', _style, _cellAttributes),
      'td': _Rule('td', _style, _cellAttributes),
    },
    ['align'],
  ),
};

const _titleChildren = <String, _Rule>{
  'p': _Rule('h1', _style),
  'empty-line': _Rule('br'),
};

// POEM['epigraph'] gets SECTION appended in fb2.js, a cycle between the
// two tables; `_poemEpigraph` stands for that entry.
const _poem = <String, _Rule>{
  'epigraph': _Rule('blockquote', _poemEpigraph),
  'subtitle': _Rule('h2', _style),
  'text-author': _Rule('p', _style),
  'date': _Rule('p', _style),
  'stanza': _Rule.special('stanza'),
};

const _poemEpigraph = '\$section';

const _section = <String, _Rule>{
  'title': _Rule('header', _titleChildren),
  'epigraph': _Rule('blockquote', _Rule.self),
  'image': _Rule.special('image'),
  'annotation': _Rule('aside'),
  'section': _Rule('section', _Rule.self),
  'p': _Rule('p', _style),
  'poem': _Rule('blockquote', _poem),
  'subtitle': _Rule('h2', _style),
  'cite': _Rule('blockquote', _Rule.self),
  'empty-line': _Rule('br'),
  'table': _Rule('table', _table),
  'text-author': _Rule('p', _style),
};

const _body = <String, _Rule>{
  'image': _Rule.special('image'),
  'title': _Rule('section', _titleChildren),
  'epigraph': _Rule('section', _section),
  'section': _Rule('section', _section),
};

const _stanzaRules = <String, _Rule>{
  'stanza': _Rule('p', <String, _Rule>{
    'title': _Rule('header', <String, _Rule>{
      'p': _Rule('strong', _style),
      'empty-line': _Rule('br'),
    }),
    'subtitle': _Rule('p', _style),
  }),
};

const _anchorRules = <String, _Rule>{'a': _Rule('a', _style)};

class _Fb2Converter {
  _Fb2Converter(this.binaries);

  final Map<String, XmlElement> binaries;

  /// The `src` for an FB2 image: a data URI for an inline binary, the
  /// href itself for anything else, `data:,` without an href.
  String imageSource(XmlElement node) {
    final href = _attributeNs(node, _xlink, 'href');
    if (href == null) return 'data:,';
    final hash = href.indexOf('#');
    if (hash < 0) return href;
    final id = href.substring(hash + 1);
    if (id.isEmpty) return href;
    final binary = binaries[id];
    if (binary == null) return href;
    return 'data:${binary.getAttribute('content-type')};base64,${binary.innerText}';
  }

  XmlElement image(XmlElement node) {
    final element = XmlElement(XmlName('img'));
    // fb2.js sets `el.alt = node.getAttribute('alt')`, which writes the
    // string "null" when the attribute is missing; the attribute is
    // simply omitted here.
    final alt = node.getAttribute('alt');
    if (alt != null) element.setAttribute('alt', alt);
    final title = node.getAttribute('title');
    if (title != null) element.setAttribute('title', title);
    element.setAttribute('src', imageSource(node));
    return element;
  }

  XmlElement anchor(XmlElement node) {
    final element = convert(node, _anchorRules)! as XmlElement;
    final href = _attributeNs(node, _xlink, 'href');
    if (href != null) element.setAttribute('href', href);
    if (node.getAttribute('type') == 'note') {
      element.attributes.add(
        XmlAttribute(XmlName('type', 'epub'), 'noteref'),
      );
    }
    return element;
  }

  XmlElement stanza(XmlElement node) {
    final element = convert(node, _stanzaRules)! as XmlElement;
    for (final child in node.childElements) {
      if (child.name.local == 'v') {
        element.children.add(XmlText(child.innerText));
        element.children.add(XmlElement(XmlName('br')));
      }
    }
    return element;
  }

  /// Converts [node] by [rules], or returns null for an element the
  /// rules do not know (dropped with its subtree, as in `fb2.js`).
  XmlNode? convert(XmlNode node, Map<String, _Rule> rules) {
    switch (node) {
      case XmlText():
        return XmlText(node.value);
      case XmlCDATA():
        return XmlCDATA(node.value);
      case XmlComment():
        return XmlComment(node.value);
      case XmlElement():
        break;
      default:
        return null;
    }
    final rule = rules[node.name.local];
    if (rule == null) return null;
    switch (rule.handler) {
      case 'image':
        return image(node);
      case 'anchor':
        return anchor(node);
      case 'stanza':
        return stanza(node);
    }
    final element = XmlElement(XmlName(rule.tag));
    if (node.getAttribute('id') case final id? when id.isNotEmpty) {
      element.setAttribute('id', id);
    }
    element.setAttribute('class', node.name.local);
    for (final attribute in rule.attributes ?? const <String>[]) {
      final value = node.getAttribute(attribute);
      if (value != null && value.isNotEmpty) {
        element.setAttribute(attribute, value);
      }
    }
    final Map<String, _Rule> childRules = switch (rule.children) {
      _Rule.self => rules,
      _poemEpigraph => {..._section, ..._poem},
      final Map<String, _Rule> map => map,
      _ => const {},
    };
    for (final child in node.children) {
      final converted = convert(child, childRules);
      if (converted != null) element.children.add(converted);
    }
    return element;
  }
}

bool _hasClass(XmlElement element, String name) =>
    element.getAttribute('class')?.split(' ').contains(name) ?? false;

String _text(XmlElement? element) => normalizeWhitespace(element?.innerText);

/// `querySelector('a b')`: the first descendant chain by local names,
/// whatever prefix the file uses.
XmlElement? _find(XmlElement from, List<String> path) =>
    _findAll(from, path).firstOrNull;

/// `querySelectorAll('a b')`: every descendant chain by local names.
List<XmlElement> _findAll(XmlElement from, List<String> path) {
  var current = <XmlElement>[from];
  for (final name in path) {
    current = [
      for (final element in current)
        for (final descendant in element.descendantElements)
          if (descendant.name.local == name) descendant,
    ];
  }
  return current;
}

String? _attributeNs(XmlElement element, String namespace, String name) {
  for (final attribute in element.attributes) {
    if (attribute.name.local == name &&
        (attribute.name.namespaceUri == namespace ||
            attribute.name.prefix == 'l' ||
            attribute.name.prefix == 'xlink')) {
      return attribute.value;
    }
  }
  return null;
}

Future<Uint8List> _readFile(String path) => File(path).readAsBytes();

Future<Uint8List> _readHead(String path, int count) async {
  final file = await File(path).open();
  try {
    return await file.read(count);
  } finally {
    await file.close();
  }
}
