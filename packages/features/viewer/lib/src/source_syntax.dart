import 'package:flutter/foundation.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/diff.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';

const maxSyntaxBytes = 256 * 1024;

typedef SourceHighlighter = Future<List<List<SourceToken>>> Function(
  String language,
  String text,
);

String? syntaxLanguageOf(String name) {
  final lower = name.toLowerCase();
  if (const {'.bashrc', '.zshrc', '.bash_profile'}.contains(lower)) {
    return 'bash';
  }
  if (lower == '.env' || lower.startsWith('.env.')) return 'ini';
  final dot = lower.lastIndexOf('.');
  if (dot < 0) return null;
  return switch (lower.substring(dot + 1)) {
    'json' || 'jsonl' || 'ndjson' => 'json',
    'yaml' || 'yml' => 'yaml',
    'toml' || 'ini' || 'cfg' || 'conf' || 'properties' => 'ini',
    'xml' || 'html' || 'htm' || 'xhtml' || 'svg' || 'plist' => 'xml',
    'dart' => 'dart',
    'rs' => 'rust',
    'py' || 'pyw' => 'python',
    'js' || 'jsx' || 'mjs' || 'cjs' => 'javascript',
    'ts' || 'tsx' => 'typescript',
    'css' => 'css',
    'sh' || 'bash' || 'zsh' => 'bash',
    'sql' => 'sql',
    'c' || 'h' || 'cc' || 'cpp' || 'cxx' || 'hpp' => 'cpp',
    'cs' => 'csharp',
    'java' => 'java',
    'kt' || 'kts' => 'kotlin',
    'go' => 'go',
    'swift' => 'swift',
    'diff' || 'patch' => 'diff',
    _ => null,
  };
}

class SourceToken {
  const SourceToken(this.start, this.end, this.scope);
  final int start;
  final int end;
  final String scope;
}

Future<List<List<SourceToken>>> highlightSource(String language, String text) =>
    compute(_highlight, (language, text));

List<List<SourceToken>> _highlight((String, String) input) {
  final mode = switch (input.$1) {
    'json' => langJson,
    'yaml' => langYaml,
    'ini' => langIni,
    'xml' => langXml,
    'dart' => langDart,
    'rust' => langRust,
    'python' => langPython,
    'javascript' => langJavascript,
    'typescript' => langTypescript,
    'css' => langCss,
    'bash' => langBash,
    'sql' => langSql,
    'cpp' => langCpp,
    'csharp' => langCsharp,
    'java' => langJava,
    'kotlin' => langKotlin,
    'go' => langGo,
    'swift' => langSwift,
    'diff' => langDiff,
    _ => null,
  };
  if (mode == null) return const [];
  final engine = Highlight()..registerLanguage(input.$1, mode);
  final result = engine.highlight(code: input.$2, language: input.$1);
  final renderer = _Tokens();
  result.render(renderer);
  return renderer.lines;
}

class _Tokens implements HighlightRenderer {
  final lines = <List<SourceToken>>[[]];
  final _scopes = <String>[];
  var _column = 0;

  @override
  void openNode(DataNode node) =>
      _scopes.add(node.scope ?? (_scopes.lastOrNull ?? ''));
  @override
  void closeNode(DataNode node) => _scopes.removeLast();
  @override
  void addText(String text) {
    final parts = text.split('\n');
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.isNotEmpty) {
        lines.last.add(
          SourceToken(_column, _column + part.length, _scopes.lastOrNull ?? ''),
        );
        _column += part.length;
      }
      if (i < parts.length - 1) {
        lines.add([]);
        _column = 0;
      }
    }
  }
}
