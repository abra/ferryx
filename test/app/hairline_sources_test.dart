import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A border, a shape or a divider of Flutter's own: its hairline lands
/// wherever layout puts it, between two pixels as often as not. The
/// component library's (`AppBorder`, `AppRoundedRectangleBorder`,
/// `AppDivider`, …) snap to the screen's pixels.
final _plain = RegExp(
  r'(?<![A-Za-z_.])(Border|BorderDirectional|RoundedRectangleBorder|'
  r'StadiumBorder|OutlineInputBorder|Divider|VerticalDivider)'
  r'(\.all|\.symmetric|\.fromBorderSide)?\(',
);

/// Where the snapping borders are defined over Flutter's.
const _definitions = [
  'hairlines.dart',
  'fluent_borders.dart',
  'app_divider.dart',
];

/// The app's and the features' Dart files, and the component library's.
Iterable<File> _sources() sync* {
  final roots = [
    Directory('lib'),
    ...Directory('packages/features').listSync().whereType<Directory>().map(
      (d) => Directory('${d.path}/lib'),
    ),
    Directory('packages/component_library/lib'),
  ];
  for (final root in roots.where((d) => d.existsSync())) {
    for (final file in root.listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith('.dart')) yield file;
    }
  }
}

/// The call that opens at [start] in [code], to its closing parenthesis.
String _call(String code, int start) {
  var depth = 0;
  for (var i = code.indexOf('(', start); i < code.length; i++) {
    final c = code[i];
    if (c == '(') depth++;
    if (c == ')' && --depth == 0) return code.substring(start, i + 1);
  }
  return code.substring(start);
}

void main() {
  test('no border, shape or divider of Flutter\'s own: hairlines go '
      'through the snapping ones of the component library', () {
    final offenders = <String>[];
    for (final file in _sources()) {
      if (_definitions.any(file.path.endsWith)) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first;
        if (_plain.hasMatch(code)) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('a Tooltip built directly places its tip on the screen\'s pixels '
      '(AppTooltip.placeOnPixels), as AppTooltip does', () {
    final tooltip = RegExp(r'(?<![A-Za-z_])Tooltip\(');
    final offenders = <String>[];
    for (final file in _sources()) {
      final code = file.readAsStringSync();
      for (final match in tooltip.allMatches(code)) {
        if (!_call(code, match.start).contains('positionDelegate:')) {
          final line = '\n'.allMatches(code.substring(0, match.start)).length;
          offenders.add('${file.path}:${line + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
