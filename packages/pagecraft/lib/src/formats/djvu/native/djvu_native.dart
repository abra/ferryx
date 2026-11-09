/// Private C ABI for the bundled DjVuLibre decoder. Calls stay on its worker.
library;

import 'dart:ffi';

const _asset = 'package:pagecraft/src/formats/djvu/native/djvu_native.dart';

@Native<Pointer<Void> Function(Pointer<Char>, Int64)>(
  symbol: 'pagecraft_djvu_open',
  assetId: _asset,
)
external Pointer<Void> djvuOpen(Pointer<Char> path, int timeoutMs);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'pagecraft_djvu_close',
  assetId: _asset,
)
external void djvuClose(Pointer<Void> document);

@Native<Pointer<Char> Function()>(
  symbol: 'pagecraft_djvu_last_error',
  assetId: _asset,
)
external Pointer<Char> djvuLastError();

@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'pagecraft_djvu_page_count',
  assetId: _asset,
)
external int djvuPageCount(Pointer<Void> document);

@Native<
  Int32 Function(
    Pointer<Void>,
    Int32,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Int32>,
  )
>(
  symbol: 'pagecraft_djvu_page_info',
  assetId: _asset,
)
external int djvuPageInfo(
  Pointer<Void> document,
  int page,
  Pointer<Int32> width,
  Pointer<Int32> height,
  Pointer<Int32> dpi,
);

@Native<
  Pointer<Uint8> Function(
    Pointer<Void>,
    Int32,
    Int32,
    Int32,
    Int32,
    Int32,
    Int32,
    Int32,
  )
>(
  symbol: 'pagecraft_djvu_render',
  assetId: _asset,
)
external Pointer<Uint8> djvuRender(
  Pointer<Void> document,
  int page,
  int fullWidth,
  int fullHeight,
  int x,
  int y,
  int width,
  int height,
);

@Native<Pointer<Char> Function(Pointer<Void>, Int32)>(
  symbol: 'pagecraft_djvu_text',
  assetId: _asset,
)
external Pointer<Char> djvuText(Pointer<Void> document, int page);

@Native<Pointer<Char> Function(Pointer<Void>)>(
  symbol: 'pagecraft_djvu_outline',
  assetId: _asset,
)
external Pointer<Char> djvuOutline(Pointer<Void> document);

@Native<Pointer<Char> Function(Pointer<Void>)>(
  symbol: 'pagecraft_djvu_metadata',
  assetId: _asset,
)
external Pointer<Char> djvuMetadata(Pointer<Void> document);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'pagecraft_djvu_free',
  assetId: _asset,
)
external void djvuFree(Pointer<Void> allocation);
