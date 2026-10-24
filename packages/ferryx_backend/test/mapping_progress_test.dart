import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' as rust;
import 'package:flutter_test/flutter_test.dart';

rust.ProgressView event({
  rust.OpStateView state = rust.OpStateView.running,
  int itemsDone = 0,
  List<rust.OpErrorView> errors = const [],
  List<rust.FolderSizeView> sizes = const [],
  List<String> sources = const [],
}) => rust.ProgressView(
  id: 7,
  kind: rust.OpKindView.calcSizes,
  state: state,
  bytesDone: 0,
  bytesTotal: 0,
  itemsDone: itemsDone,
  itemsTotal: 3,
  current: '',
  startedMs: 0,
  elapsedMs: 0,
  bytesPerSecond: 0,
  errors: errors,
  sizes: sizes,
  sources: sources,
  destination: '/to',
);

void main() {
  test('an event adds its news to the report before it', () {
    const sources = ['/a', '/b', '/c'];
    final first = rust.progressFromEvent(
      event(
        sources: sources,
        sizes: [const rust.FolderSizeView(path: '/a', bytes: 1)],
      ),
    );
    expect(first.sources, sources);
    expect(first.sizes, [const FolderSize(path: '/a', bytes: 1)]);

    // Between the first and the last: no sources, the news alone.
    final second = rust.progressFromEvent(
      event(
        itemsDone: 2,
        sizes: [const rust.FolderSizeView(path: '/b', bytes: 2)],
        errors: [const rust.OpErrorView(path: '/c', message: 'denied')],
      ),
      previous: first,
    );
    expect(second.itemsDone, 2);
    expect(second.sources, sources);
    expect(second.sizes, const [
      FolderSize(path: '/a', bytes: 1),
      FolderSize(path: '/b', bytes: 2),
    ]);
    expect(second.errors, const [
      OperationError(path: '/c', message: 'denied'),
    ]);

    // Nothing new: the lists stand as they were.
    final third = rust.progressFromEvent(event(itemsDone: 2), previous: second);
    expect(third.sizes, second.sizes);
    expect(third.errors, second.errors);

    final last = rust.progressFromEvent(
      event(
        state: rust.OpStateView.doneWithErrors,
        itemsDone: 3,
        sources: sources,
        sizes: [const rust.FolderSizeView(path: '/c', bytes: 0)],
      ),
      previous: third,
    );
    expect(last.state, OpState.doneWithErrors);
    expect(last.sources, sources);
    expect(last.sizes.map((s) => s.path), ['/a', '/b', '/c']);
    expect(last.errors, hasLength(1));
  });

  test('a whole report maps as it is', () {
    final whole = rust.progressFromView(
      event(
        sources: const ['/a'],
        sizes: [const rust.FolderSizeView(path: '/a', bytes: 9)],
      ),
    );
    expect(whole.sizes, [const FolderSize(path: '/a', bytes: 9)]);
    expect(whole.destination, '/to');
  });
}
