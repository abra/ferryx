import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';

void main() {
  test('round-trips section indices the way foliate-js writes them', () {
    expect(fakeCfiFromIndex(0), 'epubcfi(/6/2)');
    expect(fakeCfiFromIndex(1), 'epubcfi(/6/4)');
    expect(fakeCfiFromIndex(41), 'epubcfi(/6/84)');
    for (var index = 0; index <= 10000; index++) {
      expect(fakeCfiToIndex(fakeCfiFromIndex(index)), index);
    }
  });

  test('reads the section step and ignores what follows it', () {
    expect(fakeCfiToIndex('epubcfi(/6/4!/4/2/1:0)'), 1);
    expect(fakeCfiToIndex('epubcfi(/6/4[page],/4/2:0,/4/2:5)'), 1);
    expect(fakeCfiToIndex('epubcfi(/6/2)'), 0);
  });

  test('rejects strings that are not fake CFIs', () {
    expect(fakeCfiToIndex(''), isNull);
    expect(fakeCfiToIndex('epubcfi(/4/2)'), isNull);
    expect(fakeCfiToIndex('epubcfi(/6/3)'), isNull);
    expect(fakeCfiToIndex('epubcfi(/6/0)'), isNull);
    expect(fakeCfiToIndex('/6/2'), isNull);
    expect(fakeCfiToIndex('page 3'), isNull);
    expect(() => fakeCfiFromIndex(-1), throwsRangeError);
  });
}
