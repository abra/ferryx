import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'mobi_fixture_books.dart';

/// The committed fixture files are the builder's output: this keeps them
/// in step. Set `UPDATE_MOBI_FIXTURES=1` to rewrite them after a builder
/// change, then regenerate `expected.json` in the browser.
void main() {
  const dir = 'test/fixtures/mobi';
  final update = Platform.environment['UPDATE_MOBI_FIXTURES'] == '1';

  for (final (name, bytes) in [
    ('six.mobi', MobiFixtureBooks.mobi6()),
    ('eight.azw3', MobiFixtureBooks.kf8()),
  ]) {
    test('$name matches the builder', () {
      final file = File('$dir/$name');
      if (update || !file.existsSync()) {
        file.createSync(recursive: true);
        file.writeAsBytesSync(bytes);
      }
      expect(
        file.readAsBytesSync(),
        bytes,
        reason: 'rerun with UPDATE_MOBI_FIXTURES=1 after changing the builder',
      );
    });
  }
}
