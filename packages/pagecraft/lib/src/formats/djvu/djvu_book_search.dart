import 'dart:async';

import '../../search/text_search.dart';
import 'djvu_book.dart';
import 'djvu_text_layer.dart';
import 'djvu_text_layer_cache.dart';

class DjvuSearchHit {
  const DjvuSearchHit({required this.page, required this.match});
  final int page;
  final TextSearchMatch match;
  DjvuTextRange get range => DjvuTextRange(match.start, match.end);
}

/// Results arrive page by page. Subscription cancellation stops subsequent
/// requests; one already accepted native operation completes before close.
Stream<List<DjvuSearchHit>> searchDjvuBook(
  DjvuBook book,
  String query, {
  DjvuTextLayerCache? cache,
}) {
  var cancelled = false;
  Completer<void>? resumed;
  late StreamController<List<DjvuSearchHit>> results;

  Future<void> run() async {
    try {
      if (foldSearchText(query).text.trim().isEmpty) return;
      for (var page = 0; page < book.pageCount && !cancelled; page++) {
        if (results.isPaused) {
          resumed = Completer<void>();
          await resumed!.future;
        }
        if (cancelled) break;
        final layer = await (cache?.load(page) ?? book.pageText(page));
        if (cancelled) break;
        final matches = [
          for (final match in layer.search(query))
            DjvuSearchHit(page: page, match: match),
        ];
        if (matches.isNotEmpty) results.add(matches);
      }
    } on Object catch (error, stackTrace) {
      if (!cancelled) results.addError(error, stackTrace);
    } finally {
      unawaited(results.close());
    }
  }

  void resume() {
    if (resumed?.isCompleted == false) resumed!.complete();
    resumed = null;
  }

  results = StreamController<List<DjvuSearchHit>>(
    onListen: () => unawaited(run()),
    onResume: resume,
    onCancel: () {
      cancelled = true;
      resume();
    },
  );
  return results.stream;
}
