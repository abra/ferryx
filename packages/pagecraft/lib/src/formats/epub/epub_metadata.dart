/// Package metadata (`getMetadata` in `epub.js`): Dublin Core elements
/// and EPUB 3 `meta` properties with their `refines` sub-properties, the
/// `rendition:` and `media:` metas, then the summary the reader shows.
library;

import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

import 'epub_xml.dart';

/// A metadata value with the properties that refine it.
///
/// [value] is the element's text; [props] holds the refining properties
/// by name (`file-as`, `title-type`, `role`, `alternate-script`, ...),
/// each a list of further values; [attrs] the attributes read from the
/// element (`dir`, `xml:lang`, `scheme`).
@immutable
class EpubMetaValue {
  const EpubMetaValue(
    this.value, {
    this.props = const {},
    this.attrs = const {},
  });

  final String value;
  final Map<String, List<EpubMetaValue>> props;
  final Map<String, String?> attrs;

  /// The first value of property [name], or null.
  EpubMetaValue? prop(String name) {
    final values = props[name];
    return values == null || values.isEmpty ? null : values.first;
  }

  String? get fileAs => prop('file-as')?.value;

  String? get dir => attrs['dir'];

  String? get lang => attrs['xml:lang'];

  @override
  String toString() => 'EpubMetaValue($value, props: $props, attrs: $attrs)';
}

/// Every element of the package's `<metadata>` the reader reads, parsed
/// but not yet interpreted.
@immutable
class EpubParsedMetadata {
  const EpubParsedMetadata({
    required this.titles,
    required this.identifiers,
    required this.languages,
    required this.creators,
    required this.contributors,
    required this.publisher,
    required this.description,
    required this.rights,
    required this.date,
    required this.modified,
    required this.subjects,
    required this.sources,
    required this.collections,
  });

  final List<EpubMetaValue> titles;
  final List<EpubMetaValue> identifiers;
  final List<String> languages;
  final List<EpubMetaValue> creators;
  final List<EpubMetaValue> contributors;
  final EpubMetaValue? publisher;
  final EpubMetaValue? description;
  final EpubMetaValue? rights;
  final String? date;
  final String? modified;
  final List<EpubMetaValue> subjects;
  final List<String> sources;
  final List<EpubMetaValue> collections;
}

/// A subject with its code and scheme, from `dc:subject` and its refines.
@immutable
class EpubSubject {
  const EpubSubject({required this.name, this.code, this.scheme});

  final String name;
  final String? code;
  final String? scheme;

  @override
  bool operator ==(Object other) =>
      other is EpubSubject &&
      other.name == name &&
      other.code == code &&
      other.scheme == scheme;

  @override
  int get hashCode => Object.hash(name, code, scheme);

  @override
  String toString() => 'EpubSubject($name, $code, $scheme)';
}

/// A person named in the metadata, with the form their name sorts by.
@immutable
class EpubContributor {
  const EpubContributor({required this.name, this.sortAs});

  final String name;
  final String? sortAs;

  @override
  bool operator ==(Object other) =>
      other is EpubContributor && other.name == name && other.sortAs == sortAs;

  @override
  int get hashCode => Object.hash(name, sortAs);

  @override
  String toString() => 'EpubContributor($name, $sortAs)';
}

/// The metadata summary the reader uses (`book.metadata` in `epub.js`).
///
/// Contributors are grouped by role: `author`, `artist`, `editor`,
/// `translator`, `illustrator`, `narrator`, `colorist`, `producer`,
/// `publisher` from MARC relator codes, and `contributor` for the rest.
@immutable
class EpubMetadata {
  const EpubMetadata({
    this.title,
    this.subtitle,
    this.sortAs,
    this.language = const [],
    this.identifier = '',
    this.description,
    this.publisher,
    this.published,
    this.modified,
    this.subjects = const [],
    this.rights,
    this.contributors = const {},
  });

  final String? title;
  final String? subtitle;
  final String? sortAs;
  final List<String> language;
  final String identifier;
  final String? description;
  final String? publisher;
  final String? published;
  final String? modified;
  final List<EpubSubject> subjects;
  final String? rights;

  /// Contributors by role, in document order within a role.
  final Map<String, List<EpubContributor>> contributors;

  List<EpubContributor> get authors => contributors['author'] ?? const [];

  @override
  String toString() =>
      'EpubMetadata($title, authors: ${authors.map((a) => a.name).join(', ')})';
}

/// The result of reading a package document's metadata.
@immutable
class EpubPackageMetadata {
  const EpubPackageMetadata({
    required this.parsed,
    required this.metadata,
    required this.rendition,
    required this.media,
  });

  final EpubParsedMetadata parsed;
  final EpubMetadata metadata;

  /// `rendition:*` metas by name (`layout`, `orientation`, `spread`, ...).
  final Map<String, String> rendition;

  final EpubMediaMetadata media;
}

/// `media:*` metas for media overlays.
@immutable
class EpubMediaMetadata {
  const EpubMediaMetadata({
    this.narrators = const [],
    this.durations = const {},
    this.activeClass,
    this.playbackActiveClass,
  });

  final List<String> narrators;

  /// Durations in seconds by the refined item id (`''` for the whole book).
  final Map<String, double> durations;
  final String? activeClass;
  final String? playbackActiveClass;
}

// The descriptor table of epub.js, as data.

class _Spec {
  const _Spec(
    this.name, {
    this.meta = false,
    this.many = false,
    this.attrs = const [],
    this.props = const [],
    this.legacy,
  });

  final String name;

  /// An EPUB 3 `meta property="name"` rather than a `dc:name` element.
  final bool meta;
  final bool many;
  final List<String> attrs;
  final List<_Prop> props;

  /// EPUB 2 attributes in the OPF namespace that stand in for refines.
  final void Function(Map<String, List<EpubMetaValue>> props, XmlElement el)?
  legacy;
}

class _Prop {
  const _Prop(
    this.name, {
    this.many = false,
    this.attrs = const [],
    this.props = const [],
    this.recursive = false,
  });

  final String name;
  final bool many;
  final List<String> attrs;
  final List<_Prop> props;

  /// The property nests its own kind (`belongs-to-collection`).
  final bool recursive;
}

const _langs = ['dir', 'xml:lang'];
const _alts = _Prop(
  'alternate-script',
  many: true,
  attrs: _langs,
  props: [_Prop('file-as')],
);
const _contributorProps = [
  _Prop('role', many: true, attrs: ['scheme']),
  _Prop('file-as'),
  _alts,
];

void _contributorLegacy(
  Map<String, List<EpubMetaValue>> props,
  XmlElement el,
) {
  if (props['role']?.isEmpty ?? true) {
    final role = attributeNs(el, EpubNamespace.opf, 'role');
    if (role != null) props['role'] = [EpubMetaValue(role)];
  }
  if (props['file-as'] == null) {
    final fileAs = attributeNs(el, EpubNamespace.opf, 'file-as');
    if (fileAs != null) props['file-as'] = [EpubMetaValue(fileAs)];
  }
}

final _specs = <_Spec>[
  const _Spec(
    'title',
    many: true,
    attrs: _langs,
    props: [_Prop('title-type'), _Prop('display-seq'), _Prop('file-as'), _alts],
  ),
  _Spec(
    'identifier',
    many: true,
    props: const [
      _Prop('identifier-type', attrs: ['scheme']),
    ],
    legacy: (props, el) {
      if (props['identifier-type'] == null) {
        final scheme = attributeNs(el, EpubNamespace.opf, 'scheme');
        if (scheme != null) props['identifier-type'] = [EpubMetaValue(scheme)];
      }
    },
  ),
  const _Spec('language', many: true),
  _Spec(
    'creator',
    many: true,
    attrs: _langs,
    props: _contributorProps,
    legacy: _contributorLegacy,
  ),
  _Spec(
    'contributor',
    many: true,
    attrs: _langs,
    props: _contributorProps,
    legacy: _contributorLegacy,
  ),
  const _Spec('publisher', attrs: _langs, props: [_Prop('file-as'), _alts]),
  const _Spec('description', attrs: _langs, props: [_alts]),
  const _Spec('rights', attrs: _langs, props: [_alts]),
  const _Spec('date'),
  const _Spec('dcterms:modified', meta: true),
  _Spec(
    'subject',
    many: true,
    attrs: _langs,
    props: const [_Prop('term'), _Prop('authority'), _alts],
    legacy: (props, el) {
      for (final name in ['term', 'authority']) {
        if (props[name] == null) {
          final value = attributeNs(el, EpubNamespace.opf, name);
          if (value != null) props[name] = [EpubMetaValue(value)];
        }
      }
    },
  ),
  const _Spec('source', many: true),
  const _Spec(
    'belongs-to-collection',
    meta: true,
    many: true,
    attrs: _langs,
    props: [
      _Prop('collection-type'),
      _Prop('group-position'),
      _Prop('dcterms:identifier'),
      _Prop('file-as'),
      _alts,
      _Prop('belongs-to-collection', recursive: true),
    ],
  ),
];

/// Reads the `<metadata>` of [opf] (`getMetadata`).
EpubPackageMetadata parseEpubMetadata(XmlDocument opf) {
  final query = EpubXmlQuery(opf, EpubNamespace.opf);
  final metadata = query.child(opf.rootElement, 'metadata');
  final elements = metadata?.childElements.toList() ?? const <XmlElement>[];

  bool isDc(XmlElement el, String name) =>
      el.namespaceUri == EpubNamespace.dc && el.name.local == name;
  bool isMeta(XmlElement el, String name) =>
      el.namespaceUri == EpubNamespace.opf &&
      el.getAttribute('property') == name;

  EpubMetaValue? read(
    XmlElement? el, {
    required List<String> attrs,
    required List<_Prop> props,
    void Function(Map<String, List<EpubMetaValue>>, XmlElement)? legacy,
  }) {
    if (el == null) return null;
    final value = elementText(el);
    if (attrs.isEmpty && props.isEmpty) return EpubMetaValue(value);
    final id = el.getAttribute('id');
    final refines = id == null
        ? const <XmlElement>[]
        : [
            for (final e in elements)
              if (e.getAttribute('refines') == '#$id') e,
          ];
    final readProps = <String, List<EpubMetaValue>>{};
    for (final prop in props) {
      final matching = [
        for (final e in refines)
          if (e.getAttribute('property') == prop.name) e,
      ];
      final subAttrs = prop.recursive ? attrs : prop.attrs;
      final subProps = prop.recursive ? props : prop.props;
      final values = <EpubMetaValue>[];
      for (final e in prop.many ? matching : matching.take(1)) {
        final v = read(e, attrs: subAttrs, props: subProps);
        if (v != null) values.add(v);
      }
      if (values.isNotEmpty || prop.many) readProps[prop.name] = values;
    }
    final readAttrs = {for (final a in attrs) a: el.getAttribute(a)};
    legacy?.call(readProps, el);
    return EpubMetaValue(value, props: readProps, attrs: readAttrs);
  }

  final primary = [
    for (final e in elements)
      if (e.getAttribute('refines') == null) e,
  ];
  final bySpec = <String, List<EpubMetaValue>>{};
  for (final spec in _specs) {
    final matching = [
      for (final e in primary)
        if (spec.meta ? isMeta(e, spec.name) : isDc(e, spec.name)) e,
    ];
    bySpec[spec.name] = [
      for (final e in spec.many ? matching : matching.take(1))
        ?read(e, attrs: spec.attrs, props: spec.props, legacy: spec.legacy),
    ];
  }
  List<EpubMetaValue> many(String name) => bySpec[name] ?? const [];
  EpubMetaValue? one(String name) => many(name).firstOrNull;

  final parsed = EpubParsedMetadata(
    titles: many('title'),
    identifiers: many('identifier'),
    languages: many('language').map((v) => v.value).toList(growable: false),
    creators: many('creator'),
    contributors: many('contributor'),
    publisher: one('publisher'),
    description: one('description'),
    rights: one('rights'),
    date: one('date')?.value,
    modified: one('dcterms:modified')?.value,
    subjects: many('subject'),
    sources: many('source').map((v) => v.value).toList(growable: false),
    collections: many('belongs-to-collection'),
  );

  final metas = metadata == null
      ? const <XmlElement>[]
      : query.children(metadata, 'meta');
  final rendition = <String, String>{};
  var media = const EpubMediaMetadata();
  final narrators = <String>[];
  final durations = <String, double>{};
  String? activeClass;
  String? playbackActiveClass;
  for (final meta in metas) {
    final property = meta.getAttribute('property');
    if (property == null) continue;
    if (property.startsWith('rendition:')) {
      rendition[property.substring('rendition:'.length)] = elementText(meta);
    } else if (property.startsWith('media:')) {
      final key = property.substring('media:'.length);
      final value = elementText(meta);
      switch (key) {
        case 'duration':
          final refines = meta.getAttribute('refines');
          final id = refines == null ? '' : refines.split('#').skip(1).join();
          final seconds = parseEpubClock(value);
          if (seconds != null) durations[id] = seconds;
        case 'active-class':
          activeClass = value;
        case 'narrator':
          narrators.add(value);
        case 'playback-active-class':
          playbackActiveClass = value;
      }
    }
  }
  media = EpubMediaMetadata(
    narrators: narrators,
    durations: durations,
    activeClass: activeClass,
    playbackActiveClass: playbackActiveClass,
  );

  return EpubPackageMetadata(
    parsed: parsed,
    metadata: _summarize(parsed, opf),
    rendition: rendition,
    media: media,
  );
}

const _relators = {
  'art': 'artist',
  'aut': 'author',
  'bkp': 'producer',
  'clr': 'colorist',
  'edt': 'editor',
  'ill': 'illustrator',
  'nrt': 'narrator',
  'trl': 'translator',
  'pbl': 'publisher',
};

EpubMetadata _summarize(EpubParsedMetadata parsed, XmlDocument opf) {
  final title = parsed.titles.firstOrNull;
  final subtitle = parsed.titles
      .where((t) => t.prop('title-type')?.value == 'subtitle')
      .firstOrNull;
  final contributors = <String, List<EpubContributor>>{};
  void add(List<EpubMetaValue> people, String defaultRole) {
    for (final person in people) {
      final roles = <String>{};
      for (final role in person.props['role'] ?? const <EpubMetaValue>[]) {
        final scheme = role.attrs['scheme'];
        final mapped = scheme == null || scheme == 'marc:relators'
            ? _relators[role.value]
            : null;
        roles.add(mapped ?? defaultRole);
      }
      if (roles.isEmpty) roles.add(defaultRole);
      final value = EpubContributor(name: person.value, sortAs: person.fileAs);
      for (final role in roles) {
        (contributors[role] ??= []).add(value);
      }
    }
  }

  add(parsed.creators, 'author');
  add(parsed.contributors, 'contributor');

  return EpubMetadata(
    title: title?.value,
    subtitle: subtitle?.value,
    sortAs: title?.fileAs,
    language: parsed.languages,
    identifier: epubIdentifier(opf),
    description: parsed.description?.value,
    publisher: parsed.publisher?.value,
    published: parsed.date,
    modified: parsed.modified,
    subjects: [
      for (final subject in parsed.subjects)
        if (subject.value.isNotEmpty || subject.prop('term') != null)
          EpubSubject(
            name: subject.value,
            code: subject.prop('term')?.value,
            scheme: subject.prop('authority')?.value,
          ),
    ],
    rights: parsed.rights?.value,
    contributors: {
      for (final entry in contributors.entries)
        entry.key: List.unmodifiable(entry.value),
    },
  );
}

/// The package's unique identifier (`getIdentifier`): the element the
/// `unique-identifier` attribute names, else the first `dc:identifier`.
String epubIdentifier(XmlDocument opf) {
  final uniqueId = opf.rootElement.getAttribute('unique-identifier');
  XmlElement? element;
  if (uniqueId != null) {
    for (final e in opf.descendantElements) {
      if (e.getAttribute('id') == uniqueId) {
        element = e;
        break;
      }
    }
  }
  element ??= opf
      .findAllElements('identifier', namespace: EpubNamespace.dc)
      .firstOrNull;
  return elementText(element);
}

/// The first UUID among the identifiers (`getUUID`), for Adobe font
/// obfuscation, or empty.
String epubUuid(XmlDocument opf) {
  for (final e in opf.findAllElements(
    'identifier',
    namespace: EpubNamespace.dc,
  )) {
    final id = elementText(e).split(':').last;
    if (_uuid.hasMatch(id)) return _uuid.firstMatch(id)!.group(0)!;
  }
  return '';
}

final _uuid = RegExp(
  r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
);

/// A SMIL clock value in seconds (`parseClock`): `h:m:s`, `m:s`, or a
/// number with `h`, `min`, `s` or `ms`.
double? parseEpubClock(String? text) {
  if (text == null || text.isEmpty) return null;
  final parts = text.split(':');
  if (parts.length == 3) {
    final values = parts.map(double.tryParse).toList();
    if (values.any((v) => v == null)) return null;
    return values[0]! * 3600 + values[1]! * 60 + values[2]!;
  }
  if (parts.length == 2) {
    final values = parts.map(double.tryParse).toList();
    if (values.any((v) => v == null)) return null;
    return values[0]! * 60 + values[1]!;
  }
  final match = RegExp(r'^([\d.]+)\s*(h|min|ms|s)?$').firstMatch(text.trim());
  if (match == null) return null;
  final number = double.tryParse(match.group(1)!);
  if (number == null) return null;
  return switch (match.group(2)) {
    'h' => number * 3600,
    'min' => number * 60,
    'ms' => number * 0.001,
    _ => number,
  };
}
