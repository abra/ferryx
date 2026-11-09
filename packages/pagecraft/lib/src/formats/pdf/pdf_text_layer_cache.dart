import 'dart:async';

import 'package:flutter/foundation.dart';

import 'pdf_book.dart';
import 'pdf_text_layer.dart';

/// Text layers of a [PdfBook], loaded on demand and kept for the pages
/// read last.
///
/// A layer is a few hundred boxes and a string; [capacity] pages of them
/// cover the visible spread, its neighbours and a search's recent pages
/// without holding a long book's text. Listeners hear when a layer
/// arrives, so overlays built without one rebuild with it.
class PdfTextLayerCache extends ChangeNotifier {
  PdfTextLayerCache(this.book, {this.capacity = 12}) : assert(capacity > 0);

  final PdfBook book;
  final int capacity;

  // Insertion order is recency: `peek` re-inserts, eviction drops the first.
  final _layers = <int, PdfTextLayer>{};
  final _loading = <int, Future<PdfTextLayer>>{};
  bool _disposed = false;

  /// The layer of [page] if it is loaded, moving it to the front.
  PdfTextLayer? peek(int page) {
    final layer = _layers.remove(page);
    if (layer != null) _layers[page] = layer;
    return layer;
  }

  /// Loads the layer of [page], once per page at a time.
  Future<PdfTextLayer> load(int page) {
    final cached = peek(page);
    if (cached != null) return Future.value(cached);
    return _loading[page] ??= _load(page);
  }

  Future<PdfTextLayer> _load(int page) async {
    try {
      final layer = await PdfTextLayer.load(book, page);
      if (_disposed) return layer;
      _layers[page] = layer;
      while (_layers.length > capacity) {
        _layers.remove(_layers.keys.first);
      }
      notifyListeners();
      return layer;
    } finally {
      _loading.remove(page);
    }
  }

  /// Pages whose layers are loaded, oldest first.
  Iterable<int> get loadedPages => _layers.keys;

  /// The loaded layers, oldest first, without touching their recency.
  Iterable<PdfTextLayer> get loadedLayers => _layers.values;

  @override
  void dispose() {
    _disposed = true;
    _layers.clear();
    super.dispose();
  }
}
