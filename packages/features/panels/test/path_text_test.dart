import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/src/path_text.dart';

void main() {
  test('the base name is the last component with either separator', () {
    expect(PathText.baseName('/Users/me/a.txt'), 'a.txt');
    expect(PathText.baseName('/Users/me/'), 'me');
    expect(PathText.baseName(r'C:\Users\me\a.txt'), 'a.txt');
    expect(PathText.baseName('a.txt'), 'a.txt');
    expect(PathText.baseName('/'), '/');
  });

  test('the parent is everything before the last separator', () {
    expect(PathText.parentOf('/Users/me/a.txt'), '/Users/me');
    expect(PathText.parentOf('/a.txt'), '/');
    expect(PathText.parentOf('sub/a.txt'), 'sub');
    expect(PathText.parentOf('a.txt'), isNull);
    expect(PathText.parentOf(r'C:\Users\a.txt'), r'C:\Users');
  });

  test('absolute paths start at a root, a home or a drive', () {
    expect(PathText.isAbsolute('/Users'), isTrue);
    expect(PathText.isAbsolute('~/Documents'), isTrue);
    expect(PathText.isAbsolute(r'C:\Users'), isTrue);
    expect(PathText.isAbsolute(r'\\server\share'), isTrue);
    expect(PathText.isAbsolute('sub/name'), isFalse);
  });

  test('joining keeps the folder\'s own separator', () {
    expect(PathText.join('/Users/me', 'a.txt'), '/Users/me/a.txt');
    expect(PathText.join('/Users/me/', 'a.txt'), '/Users/me/a.txt');
    expect(PathText.join(r'C:\Users', 'a.txt'), r'C:\Users\a.txt');
    expect(PathText.join('', 'a.txt'), 'a.txt');
  });

  test('a long path is shortened in the middle, its last two folders '
      'kept', () {
    const long = '/Users/someone/Documents/Projects/ferryx/packages/features';
    expect(PathText.shortened(long, maxLength: 20), '/…/packages/features');
    expect(PathText.shortened('/Users/me', maxLength: 4), '/Users/me');
    expect(PathText.shortened('/Users/me/Documents'), '/Users/me/Documents');
    expect(PathText.shortened(long), '/…/packages/features');
  });
}
