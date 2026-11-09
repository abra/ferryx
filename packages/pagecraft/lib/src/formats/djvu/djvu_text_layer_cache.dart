import 'package:flutter/foundation.dart';

import 'djvu_book.dart';
import 'djvu_text_layer.dart';

/// Coalesces page requests and retains a small LRU; no whole-book text cache.
class DjvuTextLayerCache extends ChangeNotifier {
  DjvuTextLayerCache(this.book, {this.capacity = 4}) {
    if (capacity <= 0) throw RangeError.value(capacity, 'capacity');
  }
  final DjvuBook book;
  final int capacity;
  final _layers = <int, DjvuTextLayer>{};
  final _loading = <int, Future<DjvuTextLayer>>{};
  bool _disposed = false;

  DjvuTextLayer? peek(int page) {
    final value = _layers.remove(page);
    if (value != null) _layers[page] = value;
    return value;
  }

  Future<DjvuTextLayer> load(int page) {
    if (_disposed) return Future.error(StateError('DjVu text cache disposed'));
    final value = peek(page);
    if (value != null) return Future.value(value);
    return _loading[page] ??= _load(page);
  }

  Future<DjvuTextLayer> _load(int page) async {
    try {
      final value = await book.pageText(page);
      if (!_disposed) {
        _layers[page] = value;
        while (_layers.length > capacity) {
          _layers.remove(_layers.keys.first);
        }
        notifyListeners();
      }
      return value;
    } finally {
      _loading.remove(page);
    }
  }

  Iterable<int> get loadedPages => _layers.keys;
  Iterable<DjvuTextLayer> get loadedLayers => _layers.values;

  @override
  void dispose() {
    _disposed = true;
    _layers.clear();
    super.dispose();
  }
}
