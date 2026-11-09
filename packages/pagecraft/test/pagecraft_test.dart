import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  test('the public API is exported', () {
    expect(const PagecraftException('x').toString(), 'PagecraftException: x');
    expect(ZipCompression.values, hasLength(3));
  });
}
