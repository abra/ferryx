import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_feature/src/preview_search.dart';

class _Target implements PreviewSearchTarget {
  final streams = <String, StreamController<List<PreviewSearchHit>>>{};
  final revealed = <Object>[];
  @override
  Stream<List<PreviewSearchHit>> search(String query) =>
      (streams[query] = StreamController()).stream;
  @override
  Future<void> reveal(PreviewSearchHit hit) async {
    revealed.add(hit.anchor);
  }
}

void main() {
  test(
    'debounces, retires old work, wraps results and detaches safely',
    () async {
      final controller = PreviewSearchController(), target = _Target();
      final owner = Object();
      controller.attach(owner, target);
      controller.show();
      controller.setQuery('old');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      target.streams['old']!.add([const PreviewSearchHit(1, 'first')]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.hits.length, 1);
      controller.setQuery('new');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      target.streams['old']!.add([const PreviewSearchHit(2, 'stale')]);
      target.streams['new']!.add([
        const PreviewSearchHit(3, 'third'),
        const PreviewSearchHit(4, 'fourth'),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.hits.map((h) => h.anchor), [3, 4]);
      controller.next(-1);
      expect(controller.current, 1);
      controller.next(1);
      expect(controller.current, 0);
      controller.detach(Object());
      expect(controller.hits.length, 2);
      controller.dispose();
      controller.detach(owner);
      for (final stream in target.streams.values) {
        unawaited(stream.close());
      }
    },
  );
  test('reports an explicit result cap and stream failure', () async {
    final controller = PreviewSearchController(), target = _Target();
    controller.attach(target, target);
    controller.setQuery('many');
    await Future<void>.delayed(const Duration(milliseconds: 220));
    target.streams['many']!.add(
      List.generate(1002, (i) => PreviewSearchHit(i, 'hit')),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.hits.length, 1000);
    expect(controller.capped, isTrue);
    expect(controller.loading, isFalse);
    controller.setQuery('broken');
    await Future<void>.delayed(const Duration(milliseconds: 220));
    target.streams['broken']!.addError(StateError('damaged'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.failed, isTrue);
    controller.dispose();
    for (final stream in target.streams.values) {
      unawaited(stream.close());
    }
  });
}
