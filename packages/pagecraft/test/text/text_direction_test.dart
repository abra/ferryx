import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/src/text/text_direction.dart';

void main() {
  test('word cells retain script direction without splitting source zones', () {
    expect(textCellIsRtl('«مرحبا»'), isTrue);
    expect(textCellIsRtl('שלום'), isTrue);
    expect(textCellIsRtl('\u{1E922}'), isTrue);
    expect(textCellIsRtl('Привет'), isFalse);
    expect(textCellIsRtl('word'), isFalse);
    expect(textCellIsRtl('١٢٣'), isFalse);
    expect(textCellIsRtl('123'), isFalse);
    expect(textCellIsRtl(' … '), isNull);
  });
}
