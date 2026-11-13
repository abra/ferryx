import 'dart:async';
import 'dart:typed_data';

import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:material_ui/material_ui.dart';

import 'text_window.dart';
import 'viewer_source.dart';
import 'viewer_views.dart';

/// Images use bounded repository reads, never the renderer's file/network IO.
class MarkdownImage extends StatefulWidget {
  const MarkdownImage({
    required this.source,
    required this.reference,
    required this.alt,
    required this.generation,
    this.embeddedBytes,
    super.key,
  });
  final ViewerSource source;
  final Uri reference;
  final String? alt;
  final int generation;

  /// Bounded raster bytes extracted from an office document by the core.
  final Uint8List? embeddedBytes;
  @override
  State<MarkdownImage> createState() => _MarkdownImageState();
}

class _MarkdownImageState extends State<MarkdownImage> {
  static const _maxBytes = 8 * 1024 * 1024;
  static const _maxPixelsPerSide = 2048;
  late Future<ImageProvider?> _image;
  ImageProvider? _provider;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _image = _load();
  }

  @override
  void didUpdateWidget(MarkdownImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.source != oldWidget.source ||
        widget.reference != oldWidget.reference ||
        widget.embeddedBytes != oldWidget.embeddedBytes ||
        widget.generation != oldWidget.generation) {
      _evict();
      _image = _load();
    }
  }

  Future<ImageProvider?> _load() async {
    final attempt = ++_attempt;
    final embedded = widget.embeddedBytes;
    if (embedded != null) {
      if (embedded.isEmpty || embedded.length > _maxBytes) return null;
      return _provider = ResizeImage(
        MemoryImage(embedded),
        width: _maxPixelsPerSide,
        height: _maxPixelsPerSide,
        policy: ResizeImagePolicy.fit,
        allowUpscaling: false,
      );
    }
    final source = widget.source;
    if (source is! RelativeViewerSource) return null;
    final image = source.resolveRelative(widget.reference);
    if (image == null || !isImageName(image.displayName)) return null;
    final size = await image.size();
    if (!mounted || attempt != _attempt || size <= 0 || size > _maxBytes) {
      return null;
    }
    final bytes = await image.read(0, size);
    if (!mounted || attempt != _attempt) return null;
    return _provider = ResizeImage(
      MemoryImage(bytes),
      width: _maxPixelsPerSide,
      height: _maxPixelsPerSide,
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    );
  }

  void _evict() {
    final provider = _provider;
    _provider = null;
    if (provider != null) unawaited(provider.evict());
  }

  @override
  void dispose() {
    _attempt++;
    _evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ImageProvider?>(
    future: _image,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        // A zero-height leading item can leave the lazy list before its
        // image arrives. Keep it laid out throughout the asynchronous read.
        return const _ImageLoading();
      }
      final provider = snapshot.data;
      if (provider == null) {
        return _ImagePlaceholder(reference: widget.reference, alt: widget.alt);
      }
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: AppSizes.imageMaxHeight),
        child: Image(
          image: provider,
          semanticLabel: widget.alt,
          fit: BoxFit.contain,
          frameBuilder: (context, child, frame, synchronous) =>
              frame == null ? const _ImageLoading() : child,
          errorBuilder: (context, error, stack) =>
              _ImagePlaceholder(reference: widget.reference, alt: widget.alt),
        ),
      );
    },
  );
}

class _ImageLoading extends StatelessWidget {
  const _ImageLoading();

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: context.metrics.controlHeight,
    child: const DelayedSpinner(),
  );
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.reference, required this.alt});
  final Uri reference;
  final String? alt;
  @override
  Widget build(BuildContext context) => AppTooltip(
    message: reference.toString(),
    child: Text(
      alt?.isNotEmpty == true ? alt! : context.l10n.markdownImageUnavailable,
      style: context.text.bodySmall?.copyWith(
        color: context.appColors.textMuted,
      ),
    ),
  );
}
