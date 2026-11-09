import 'package:flutter/widgets.dart';

/// A visual text cell and its exact UTF-16 range in the supplied text.
/// Usually one grapheme; scanned documents may supply only whole-word cells.
@immutable
class NativeTextBox {
  const NativeTextBox({
    required this.start,
    required this.end,
    required this.rect,
    this.direction = TextDirection.ltr,
  }) : assert(start >= 0 && end > start);

  final int start;
  final int end;
  final Rect rect;
  final TextDirection direction;

  Map<String, Object> toMessage() => {
    'start': start,
    'end': end,
    'left': rect.left,
    'top': rect.top,
    'right': rect.right,
    'bottom': rect.bottom,
    'rtl': direction == TextDirection.rtl,
  };
}

/// The visible clip of one physical page/column in a combined selection view.
@immutable
class NativeTextRegion {
  const NativeTextRegion({
    required this.start,
    required this.end,
    required this.rect,
  });

  final int start;
  final int end;
  final Rect rect;

  Map<String, Object> toMessage() => {
    'start': start,
    'end': end,
    'left': rect.left,
    'top': rect.top,
    'right': rect.right,
    'bottom': rect.bottom,
  };
}

/// Immutable visible text geometry, independent of any document format.
///
/// [revision] changes when text or its geometry changes. Selection-only updates
/// reuse the revision, so a drag never resends the glyph geometry.
@immutable
class NativeSelectionSnapshot {
  const NativeSelectionSnapshot({
    required this.revision,
    required this.text,
    required this.boxes,
    required this.selection,
    required this.accent,
    required this.selectionColor,
    this.regions = const [],
    this.showMenu = false,
    this.editable = false,
  });

  final int revision;
  final String text;
  final List<NativeTextBox> boxes;
  final TextSelection? selection;
  final Color accent;
  final Color selectionColor;
  final List<NativeTextRegion> regions;
  final bool showMenu;
  final bool editable;

  /// Resolves insertion edges through unboxed whitespace/newlines, using the
  /// same affinity as the native text-input adapter. Source cells may be words.
  NativeTextBox? caretCellAt(int offset, {bool upstream = false}) {
    NativeTextBox? next;
    NativeTextBox? last;
    for (final box in boxes) {
      if (last == null || box.end > last.end) last = box;
      if (box.end > offset || (upstream && box.end == offset)) {
        if (next == null || box.end < next.end) next = box;
      }
    }
    return next ?? last;
  }

  Map<String, Object?> toMessage() => {
    'revision': revision,
    'text': text,
    'boxes': [for (final box in boxes) box.toMessage()],
    'regions': [for (final region in regions) region.toMessage()],
    'selection': selection == null
        ? null
        : {'base': selection!.baseOffset, 'extent': selection!.extentOffset},
    'accent': accent.toARGB32(),
    'selectionColor': selectionColor.toARGB32(),
    'showMenu': showMenu,
    'editable': editable,
  };
}
