import 'dart:async';
import 'dart:ui' as ui;

import 'package:component_library/component_library.dart';
import 'package:flutter/widgets.dart';
import 'package:super_clipboard/super_clipboard_internal.dart';
import 'package:super_native_extensions/raw_clipboard.dart' as raw;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:super_native_extensions/raw_drag_drop.dart' as raw;

import 'file_drag_request.dart';
import 'offscreen_image.dart';

/// Drags of files out of the window through the desktop's own drag
/// session (super_native_extensions): another application gets a file URL
/// per item, a drop in this window gets [FileDragRequest.local] back.
///
/// Only the first item carries the picture; the others carry a clear
/// point under the pointer, so a thousand files start a drag about as
/// quickly as one (a pixel to send each, not a thousand large images).
class SystemFileDrags {
  /// Starts the drag at [FileDragRequest.position]; completes once the
  /// session is under way (the drop comes later, through the window's
  /// drop area).
  Future<void> start(BuildContext context, FileDragRequest request) async {
    final ratio = View.of(context).devicePixelRatio;
    final picture = await paintOffscreen(
      context,
      request.image,
      size: request.imageSize,
      pixelRatio: ratio,
    );
    final clear = await _clearPixel();
    // One item per file, as another application reads a URL from each;
    // the first carries what a drop in this window gets back. Items only
    // this window takes (an archive's members) travel as that one item.
    final writers = request.paths.isEmpty
        ? [DragItem(localData: request.local)]
        : [
            for (final (i, path) in request.paths.indexed)
              DragItem(localData: i == 0 ? request.local : null)
                ..add(Formats.fileUri(Uri.file(path))),
          ];
    // Registered together: one round trip's wait, not a thousand.
    final handles = <raw.DataProviderHandle>[];
    final items = <raw.DragItem>[];
    try {
      final registered = await Future.wait([
        for (final writer in writers)
          Future.sync(() async {
            final handle = await writer.registerWithDataProvider(
              await writer.asDataProvider(),
            );
            handles.add(handle);
            return handle;
          }),
      ]);
      for (final (i, handle) in registered.indexed) {
        final first = i == 0;
        final image = first ? picture : clear.clone();
        image.devicePixelRatio = first ? ratio : 1;
        items.add(
          raw.DragItem(
            dataProvider: handle,
            image: TargetedWidgetSnapshot(
              WidgetSnapshot.image(image),
              first
                  ? Rect.fromCenter(
                      center: request.position,
                      width: request.imageSize.width,
                      height: request.imageSize.height,
                    )
                  : request.position & const Size(1, 1),
            ),
            liftImage: null,
            localData: writers[i].localData,
          ),
        );
      }
    } on Object {
      _release(handles, items, picture);
      rethrow;
    } finally {
      clear.dispose();
    }
    final configuration = raw.DragConfiguration(
      items: items,
      allowedOperations: [
        for (final operation in request.allowed) ?toRawOperation(operation),
      ],
    );
    final dragContext = await raw.DragContext.instance();
    if (!context.mounted) {
      _release(handles, items, picture);
      return;
    }
    final session = dragContext.newSession();
    session.dragCompleted.addListener(configuration.disposeImages);
    try {
      await dragContext.startDrag(
        buildContext: context,
        session: session,
        configuration: configuration,
        position: request.position,
      );
    } on Object {
      // The desktop refused the drag (the button went up first): nothing
      // will release the items.
      session.dragCompleted.removeListener(configuration.disposeImages);
      _release(handles, items, picture);
      rethrow;
    }
  }

  void _release(
    List<raw.DataProviderHandle> handles,
    List<raw.DragItem> items,
    ui.Image picture,
  ) {
    for (final handle in handles) {
      handle.dispose();
    }
    for (final item in items) {
      item.disposeImages();
    }
    if (items.isEmpty) picture.dispose();
  }

  /// A transparent pixel: the picture of every item after the first.
  Future<ui.Image> _clearPixel() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder);
    return recorder.endRecording().toImage(1, 1);
  }
}

/// The desktop's name of [operation]; none for the answers that refuse.
raw.DropOperation? toRawOperation(FileDropOperation operation) =>
    switch (operation) {
      FileDropOperation.copy => raw.DropOperation.copy,
      FileDropOperation.move => raw.DropOperation.move,
      FileDropOperation.link => raw.DropOperation.link,
      FileDropOperation.none => null,
      FileDropOperation.forbidden => null,
    };
