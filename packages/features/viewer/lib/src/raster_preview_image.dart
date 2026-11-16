import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Memory image decoded inside a physical-pixel box, without upscaling.
/// Each side remains positive even when a very wide/tall image fits to
/// less than one pixel on its minor axis.
class RasterPreviewImage extends MemoryImage {
  const RasterPreviewImage(
    super.bytes, {
    required this.maxWidth,
    required this.maxHeight,
  }) : assert(maxWidth > 0 && maxHeight > 0);

  final int maxWidth;
  final int maxHeight;

  @override
  ImageStreamCompleter loadImage(
    MemoryImage key,
    ImageDecoderCallback decode,
  ) => super.loadImage(
    key,
    (buffer, {getTargetSize}) => decode(
      buffer,
      getTargetSize: (width, height) {
        final scale = math.min(
          1.0,
          math.min(maxWidth / width, maxHeight / height),
        );
        return ui.TargetImageSize(
          width: (width * scale).floor().clamp(1, maxWidth),
          height: (height * scale).floor().clamp(1, maxHeight),
        );
      },
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is RasterPreviewImage &&
      identical(bytes, other.bytes) &&
      maxWidth == other.maxWidth &&
      maxHeight == other.maxHeight;

  @override
  int get hashCode => Object.hash(runtimeType, bytes, maxWidth, maxHeight);
}
