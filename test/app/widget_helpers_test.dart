import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// A piece of the interface is a widget of its own, never a method or a
// function that builds it. A helper's widgets are rebuilt with all of its
// caller's, can't be const, and look things up in the caller's context,
// past a Theme or a Builder put between them; a widget has an element of
// its own, rebuilds alone, and shows in the inspector and to
// `find.byType`. Flutter's own API that hands a widget back (`build`,
// `createState`, a route's `buildPage`) is overridden and stays, and so
// does a lookup that returns a widget the tree has (`AssetScope.maybeOf`):
// it builds none.

/// Every case the check tells apart, with the names it must report.
const _sample = '''
import 'package:flutter/widgets.dart';

class Page extends StatelessWidget {
  const Page({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox();

  Widget _title() => const Text('t');
  Widget get _icon => const SizedBox();
  static Text label(String s) => Text(s);
  Iterable<Widget> _rows() sync* {
    yield const SizedBox();
  }

  Widget? _maybe(bool b) => b ? const SizedBox() : null;

  void _local() {
    Widget cell(String s) => Text(s);
    final plate = (Widget child) => Center(child: child);
  }

  static Page? maybeOf(BuildContext context) =>
      context.findAncestorWidgetOfExactType<Page>();
}

Widget pane() => const Page();

TransitionBuilder framed() => (context, child) => Center(child: child);

class Wrapped extends StatelessWidget {
  const Wrapped({required this.child, super.key});

  factory Wrapped.of(Widget child) => Wrapped(key: child.key, child: child);

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

abstract class Tile {
  Widget buildTile();
}
''';

const _sampleHelpers = [
  '_title',
  '_icon',
  'label',
  '_rows',
  '_maybe',
  'cell',
  'plate',
  'pane',
  'buildTile',
];

/// The Dart files of the app and of every package under `packages/`.
List<String> _sources() => [
  for (final pubspec in [
    File('pubspec.yaml'),
    ...Directory('packages')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => p.basename(f.path) == 'pubspec.yaml'),
  ])
    for (final lib in [Directory(p.join(p.dirname(pubspec.path), 'lib'))])
      if (lib.existsSync())
        for (final file in lib.listSync(recursive: true).whereType<File>())
          if (file.path.endsWith('.dart')) p.normalize(file.absolute.path),
];

/// Whether [type] is a widget, or a collection of widgets.
bool _isWidget(DartType type) {
  if (type is! InterfaceType) return false;
  for (final t in [type, ...type.allSupertypes]) {
    final library = t.element.library.uri.toString();
    if (t.element.name == 'Widget' &&
        library == 'package:flutter/src/widgets/framework.dart') {
      return true;
    }
    if (t.element.name == 'Iterable' && t.element.library.isDartCore) {
      return _isWidget(t.typeArguments.single);
    }
  }
  return false;
}

/// Whether [body] creates a widget.
bool _createsWidget(AstNode body) {
  final creations = _Creations();
  body.accept(creations);
  return creations.found;
}

class _Creations extends RecursiveAstVisitor<void> {
  var found = false;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.staticType;
    if (type != null && _isWidget(type)) found = true;
    super.visitInstanceCreationExpression(node);
  }
}

/// Reports, by name and offset, the declarations in a unit that return
/// widgets they build.
class _Helpers extends RecursiveAstVisitor<void> {
  _Helpers(this.report);

  final void Function(String name, int offset) report;

  void _check(Token name, DartType? returns, FunctionBody body) {
    if (returns == null || !_isWidget(returns)) return;
    // A body that builds nothing hands back a widget it was given or
    // found; one with no body at all asks every override to build.
    if (body is EmptyFunctionBody || _createsWidget(body)) {
      report(name.lexeme, name.offset);
    }
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final overrides = node.metadata.any((a) => a.name.name == 'override');
    if (!overrides) {
      _check(node.name, node.declaredFragment?.element.returnType, node.body);
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _check(
      node.name,
      node.declaredFragment?.element.returnType,
      node.functionExpression.body,
    );
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final function = node.initializer;
    final type = node.declaredFragment?.element.type;
    if (function is FunctionExpression && type is FunctionType) {
      _check(node.name, type.returnType, function.body);
    }
    super.visitVariableDeclaration(node);
  }
}

void main() {
  final files = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
  final samplePath = p.join(
    Directory('test/app').absolute.path,
    'widget_helpers_sample.dart',
  );
  late AnalysisSession session;

  setUpAll(() {
    final flutter = Platform.environment['FLUTTER_ROOT'];
    if (flutter == null) {
      fail('FLUTTER_ROOT is unset: run through flutter test');
    }
    files.setOverlay(samplePath, content: _sample, modificationStamp: 0);
    // The app's package config reaches every package, so one context
    // resolves them all and reads Flutter once. Were Flutter not resolved,
    // nothing would be a widget and the sources would pass: the sample's
    // test fails then.
    session = AnalysisContextCollection(
      includedPaths: [Directory('lib').absolute.path],
      resourceProvider: files,
      sdkPath: p.join(flutter, 'bin', 'cache', 'dart-sdk'),
    ).contexts.single.currentSession;
  });

  /// The helpers in the file at [path], as `path:line: name`.
  Future<List<String>> helpersIn(String path) async {
    final result = await session.getResolvedUnit(path);
    if (result is! ResolvedUnitResult) fail('$path did not resolve: $result');
    final found = <String>[];
    result.unit.accept(
      _Helpers((name, offset) {
        final line = result.lineInfo.getLocation(offset).lineNumber;
        found.add('${p.relative(path)}:$line: $name');
      }),
    );
    return found;
  }

  test('the check reports every kind of helper and spares Flutter\'s '
      'overrides, lookups, constructors and builders', () async {
    final found = await helpersIn(samplePath);
    expect(found.map((h) => h.split(': ').last), _sampleHelpers);
  });

  test('no method or function builds a widget: a piece of the interface '
      'is a widget of its own', () async {
    final sources = _sources();
    expect(sources, isNotEmpty);
    final helpers = [for (final path in sources) ...await helpersIn(path)];
    expect(helpers, isEmpty, reason: helpers.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
