import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/src/dialogs/names_check.dart';

void main() {
  const originals = ['a.txt', 'b.txt', 'c.md'];

  NamesCheck check(String text, {Set<String> existing = const {}}) =>
      checkNames(originals: originals, text: text, existing: existing);

  test('the text as it was changes nothing and has no errors', () {
    final result = check('a.txt\nb.txt\nc.md');
    expect(result.errors, 0);
    expect(result.changed, isEmpty);
    expect(result.canApply, isFalse);
    expect(result.linesMatch, isTrue);
  });

  test('a changed line renames its item, trimmed; one kept exactly as it '
      'was keeps even its spaces', () {
    final result = checkNames(
      originals: const [' odd ', 'b.txt'],
      text: ' odd \n  bee.txt  ',
      existing: const {},
    );
    expect(result.newNames, [' odd ', 'bee.txt']);
    expect(result.changed, [1]);
    expect(result.canApply, isTrue);
  });

  test('a trailing newline is not a line of its own', () {
    final result = check('a.txt\nb.txt\nd.md\n\n');
    expect(result.lineCount, 3);
    expect(result.errors, 0);
    expect(result.changed, [2]);
  });

  test('empty names, separators and impossible names are errors', () {
    final result = check('  \nsub/b.txt\n..');
    expect(result.problems, [
      NameProblem.empty,
      NameProblem.separator,
      NameProblem.invalid,
    ]);
    expect(result.errors, 3);
    expect(result.canApply, isFalse);
    expect(result.firstProblem, 0);
  });

  test('two lines with one name are both errors, each pointing at the '
      'other', () {
    final result = check('x.txt\nb.txt\nx.txt');
    expect(result.problems, [
      NameProblem.duplicate,
      null,
      NameProblem.duplicate,
    ]);
    expect(result.duplicateOf, {0: 2, 2: 0});
    // A new name taking the name a kept line keeps.
    final kept = check('b.txt\nb.txt\nc.md');
    expect(kept.problems.first, NameProblem.duplicate);
  });

  test('a name of the folder not being renamed is taken; one being '
      'renamed away is free, so names can swap', () {
    final taken = check('a.txt\nnotes.txt\nc.md', existing: {'notes.txt'});
    expect(taken.problems, [null, NameProblem.exists, null]);
    final swap = check('b.txt\na.txt\nc.md', existing: {'notes.txt'});
    expect(swap.errors, 0);
    expect(swap.changed, [0, 1]);
    expect(swap.newNames, ['b.txt', 'a.txt', 'c.md']);
  });

  test('fewer lines than names: the names left without one are errors', () {
    final result = check('a.txt\nb.txt');
    expect(result.linesMatch, isFalse);
    expect(result.problems, [null, null, NameProblem.missing]);
    expect(result.newNames.last, isNull);
    expect(result.canApply, isFalse);
  });

  test('more lines than names: the extra lines are errors', () {
    final result = check('a.txt\nb.txt\nc.md\nd.md\n');
    expect(result.lineCount, 4);
    expect(result.problems, [null, null, null, NameProblem.extra]);
    expect(result.canApply, isFalse);
  });

  test('thousands of names check in a few milliseconds', () {
    final many = [for (var i = 0; i < 20000; i++) 'photo-$i.jpg'];
    final text = [for (final n in many) n.toUpperCase()].join('\n');
    final watch = Stopwatch()..start();
    final result = checkNames(originals: many, text: text, existing: {});
    expect(result.changed.length, 20000);
    expect(watch.elapsedMilliseconds, lessThan(200));
  });
}
