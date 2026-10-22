import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/src/panel/vim_keys.dart';

void main() {
  VimKeyOutcome type(VimKeys keys, String character) => keys.feed(
    key: LogicalKeyboardKey(character.codeUnitAt(0)),
    character: character,
  );

  test('digits make a count that the next motion spends', () {
    final keys = VimKeys();
    expect(type(keys, '0'), isA<VimIgnored>());
    expect(type(keys, '1'), isA<VimConsumed>());
    expect(type(keys, '0'), isA<VimConsumed>());
    expect(keys.count, 10);
    expect(keys.pendingText, '10');
    expect(keys.takeCount(), 10);
    expect(keys.count, isNull);
    expect(keys.takeCount(), 1);
    expect(keys.takeCount(7), 7);
  });

  test('a letter is not a count and goes on', () {
    final keys = VimKeys();
    expect(type(keys, 'j'), isA<VimIgnored>());
    expect(keys.count, isNull);
  });

  test('f waits for its letter, then ; and , repeat it', () {
    final keys = VimKeys();
    keys.pending = VimPending.findForward;
    expect(keys.pendingText, 'f');
    final found = type(keys, 'd');
    expect(found, isA<VimFindChar>());
    expect((found as VimFindChar).char, 'd');
    expect(found.forward, isTrue);
    expect(keys.pending, isNull);
    expect(keys.repeatFind(reverse: false)!.forward, isTrue);
    expect(keys.repeatFind(reverse: true)!.forward, isFalse);
    keys.pending = VimPending.findBackward;
    expect((type(keys, 'x') as VimFindChar).forward, isFalse);
  });

  test('marks take a letter only; the quote itself means the place before', () {
    final keys = VimKeys();
    keys.pending = VimPending.setMark;
    expect(type(keys, '1'), isA<VimConsumed>());
    keys.pending = VimPending.setMark;
    expect((type(keys, 'a') as VimSetMark).letter, 'a');
    keys.pending = VimPending.goMark;
    expect((type(keys, "'") as VimGoMark).letter, "'");
    keys.pending = VimPending.goMark;
    expect((type(keys, 'B') as VimGoMark).letter, 'B');
  });

  test('Esc clears what waits and is otherwise left alone', () {
    final keys = VimKeys();
    expect(keys.feed(key: LogicalKeyboardKey.escape), isA<VimIgnored>());
    type(keys, '3');
    keys.pending = VimPending.findForward;
    expect(keys.feed(key: LogicalKeyboardKey.escape), isA<VimConsumed>());
    expect(keys.count, isNull);
    expect(keys.pending, isNull);
    expect(keys.pendingText, '');
  });

  test('a count stops at four digits', () {
    final keys = VimKeys();
    for (final c in '123456'.split('')) {
      type(keys, c);
    }
    expect(keys.count, VimKeys.maxCount);
  });
}
