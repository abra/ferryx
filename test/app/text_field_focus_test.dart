import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Return in a one-line Material or Cupertino field runs `onSubmitted`.
/// Without `onEditingComplete`, Flutter then takes the focus away from
/// it. A dialog that stays open after Return (a wrong password, a name
/// already taken, a search started) is then left without the keys, and
/// they go to whatever is behind it. So a field that submits says what
/// happens to its focus: `onEditingComplete: () {}` keeps it.
final _field = RegExp(
  r'(?<![A-Za-z_.])(TextField|TextFormField|CupertinoTextField)\(',
);

/// The app's Dart files, the features' and the component library's.
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
  test('a text field that submits on Return keeps or hands on the keys: '
      'it has an onEditingComplete', () {
    final offenders = <String>[];
    for (final file in _sources()) {
      final code = file.readAsStringSync();
      for (final match in _field.allMatches(code)) {
        final call = _call(code, match.start);
        if (call.contains('onSubmitted:') &&
            !call.contains('onEditingComplete:')) {
          final line = '\n'.allMatches(code.substring(0, match.start)).length;
          offenders.add('${file.path}:${line + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
