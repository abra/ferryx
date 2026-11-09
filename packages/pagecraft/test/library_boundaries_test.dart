import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The libraries an app imports decide what lands in its build: a format
/// it does not import must not be reachable from the ones it does. These
/// tests walk the `import`/`export`/`part` graph from each public library
/// and check that it stays within the core and that library's format.
void main() {
  final graph = _SourceGraph.load(Directory('lib'));

  const modules = {
    'article.dart': 'src/article/',
    'comic.dart': 'src/formats/comic/',
    'djvu.dart': 'src/formats/djvu/',
    'epub.dart': 'src/formats/epub/',
    'fb2.dart': 'src/formats/fb2/',
    'mobi.dart': 'src/formats/mobi/',
    'pdf.dart': 'src/formats/pdf/',
  };
  bool isModule(String path) => modules.values.any(path.startsWith);
  bool isGlue(String path) => path == 'src/formats/text_book_sources.dart';
  bool isTesting(String path) => path.startsWith('src/testing/');

  test('the core reaches no format', () {
    final reached = graph.reachableFrom('pagecraft.dart');
    expect(reached.where(isModule), isEmpty);
    expect(reached.where(isGlue), isEmpty);
  });

  for (final MapEntry(key: library, value: own) in modules.entries) {
    test('$library reaches the core and its own format only', () {
      final reached = graph.reachableFrom(library);
      expect(
        reached.where((p) => isModule(p) && !p.startsWith(own)),
        isEmpty,
      );
      expect(reached.where(isGlue), isEmpty);
      expect(reached, contains('pagecraft.dart'));
      expect(reached.where((p) => p.startsWith(own)), isNotEmpty);
    });
  }

  test('only the all-formats glue imports more than one format', () {
    for (final file in graph.files.where(
      (p) => !isGlue(p) && !isTesting(p) && p.startsWith('src/'),
    )) {
      final own = modules.values.where(file.startsWith).firstOrNull;
      final others = graph
          .dependenciesOf(file)
          .where((p) => isModule(p) && (own == null || !p.startsWith(own)));
      expect(others, isEmpty, reason: '$file imports another format');
    }
  });

  test('every source file is reachable from all_formats.dart or testing', () {
    final reached = {
      ...graph.reachableFrom('all_formats.dart'),
      ...graph.reachableFrom('testing.dart'),
    };
    expect(graph.files.where((p) => !reached.contains(p)), isEmpty);
  });
}

/// Dart files under `lib/` by their path relative to it, with the files
/// each one names in its directives.
class _SourceGraph {
  _SourceGraph(this._edges);

  factory _SourceGraph.load(Directory lib) {
    final root = lib.absolute.path;
    final edges = <String, Set<String>>{};
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.absolute.path.substring(root.length + 1);
      final here = Uri.file('$root/$path');
      edges[path] = {
        for (final match in _directive.allMatches(entity.readAsStringSync()))
          ?_resolve(match[1]!, here, root),
      };
    }
    return _SourceGraph(edges);
  }

  static final _directive = RegExp(
    r'''^\s*(?:import|export|part)\s+'([^']+)'(?!\s*of)''',
    multiLine: true,
  );

  static String? _resolve(String uri, Uri here, String root) {
    if (uri.startsWith('package:pagecraft/')) {
      return uri.substring('package:pagecraft/'.length);
    }
    if (uri.contains(':')) return null;
    final path = here.resolve(uri).toFilePath();
    return path.startsWith('$root/') ? path.substring(root.length + 1) : null;
  }

  final Map<String, Set<String>> _edges;

  Iterable<String> get files => _edges.keys;

  Set<String> dependenciesOf(String file) => _edges[file] ?? const {};

  Set<String> reachableFrom(String file) {
    final seen = <String>{file};
    final queue = [file];
    while (queue.isNotEmpty) {
      for (final next in dependenciesOf(queue.removeLast())) {
        if (seen.add(next)) queue.add(next);
      }
    }
    return seen;
  }
}
