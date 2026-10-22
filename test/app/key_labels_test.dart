import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shortcuts/shortcuts.dart';

/// Glyphs that name keys on a Mac keyboard only.
final _macGlyphs = RegExp('[⌘⇧⌥⌃↩⌫⌦]');

/// A key named in a string literal (`'Esc'`, `'Ctrl+K'`): its label is
/// the platform's, so it comes from `Chord`.
final _keyNames = RegExp(
  r"""['"](Esc|Enter|Tab|Space|Del|Delete|Backspace|F\d+|(Ctrl|Alt|Shift)\+[^'"]*)['"]""",
);

void main() {
  test('no key is named in app or feature code, by a Mac glyph or by its '
      'name: labels come from the shortcuts package, per platform', () {
    final offenders = <String>[];
    final roots = [
      Directory('lib'),
      ...Directory('packages/features').listSync().whereType<Directory>().map(
        (d) => Directory('${d.path}/lib'),
      ),
      Directory('packages/component_library/lib'),
    ];
    for (final root in roots.where((d) => d.existsSync())) {
      for (final file in root.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        // The key cap maps the glyphs a Mac label holds to icons.
        if (file.path.endsWith('app_key_cap.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final code = lines[i].split('//').first;
          if (_macGlyphs.hasMatch(code) || _keyNames.hasMatch(code)) {
            offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('no feature branches on defaultTargetPlatform: the theme\'s '
      'platform decides, so a style shot in a test is the shipped one', () {
    final offenders = <String>[];
    final roots = [
      ...Directory('packages/features').listSync().whereType<Directory>().map(
        (d) => Directory('${d.path}/lib'),
      ),
    ];
    for (final root in roots.where((d) => d.existsSync())) {
      for (final file in root.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].split('//').first.contains('defaultTargetPlatform')) {
            offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('no translation names a key by its Mac glyph: strings take the key '
      'as a placeholder', () {
    final offenders = <String>[];
    for (final file in Directory(
      'packages/ferryx_localizations/lib/l10n',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.arb'))) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_macGlyphs.hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('the labels read as each platform writes them', () {
    const enter = Chord(LogicalKeyboardKey.enter, primary: true);
    expect(enter.label(TargetPlatform.macOS), '⌘↩');
    expect(enter.label(TargetPlatform.windows), 'Ctrl+Enter');
    expect(enter.label(TargetPlatform.linux), 'Ctrl+Enter');
    expect(Chord.deleteLabel(TargetPlatform.macOS), '⌫');
    expect(Chord.deleteLabel(TargetPlatform.windows), 'Del');
  });
}
