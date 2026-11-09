import 'dart:ui' as ui show BoxHeightStyle;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:native_text_selection/native_text_selection.dart';

import '../layout/text_page.dart';
import '../layout/text_page_selection.dart';

/// A viewport's native UTF-16 text, mapped back to Pagecraft's paragraph
/// fragments. Building boxes is deferred until selection starts and cached
/// while only the selected range changes.
class TextNativeSelectionGeometry {
  TextNativeSelectionGeometry._(
    this._pages,
    this._transforms,
    this._size,
    this._fragments,
    this.text,
    this.boxes,
    this.regions,
  );

  factory TextNativeSelectionGeometry.capture(
    Iterable<RenderTextColumnPage> pages,
    RenderBox viewport,
  ) {
    final visible = <RenderTextColumnPage>[];
    final transforms = <Matrix4>[];
    final fragments = <_NativeParagraph>[];
    final boxes = <NativeTextBox>[];
    final regions = <NativeTextRegion>[];
    final buffer = StringBuffer();
    final bounds = Offset.zero & viewport.size;
    for (final page in pages) {
      final transform = page.getTransformTo(viewport);
      if (!MatrixUtils.transformRect(
        transform,
        Offset.zero & page.size,
      ).overlaps(bounds)) {
        continue;
      }
      visible.add(page);
      transforms.add(transform);
      final regionStart = buffer.length;
      for (final fragment in page.selectionFragments) {
        if (!fragment.boundingBoxes.any(
          (box) => MatrixUtils.transformRect(transform, box).overlaps(bounds),
        )) {
          continue;
        }
        if (buffer.isNotEmpty) buffer.write('\n');
        final start = buffer.length;
        final text = fragment.item.paragraph.box.text.substring(
          fragment.start,
          fragment.end,
        );
        buffer.write(text);
        fragments.add(_NativeParagraph(page, fragment, start));
        var offset = fragment.start;
        for (final character in text.characters) {
          final end = offset + character.length;
          Rect? cell;
          TextDirection? direction;
          for (final box in fragment.item.paragraph.boxesFor(
            offset,
            end,
            heightStyle: ui.BoxHeightStyle.max,
          )) {
            final rect = MatrixUtils.transformRect(
              transform,
              box.toRect().shift(fragment.origin),
            );
            if (!rect.isEmpty) {
              cell = cell?.expandToInclude(rect) ?? rect;
              direction ??= box.direction;
            }
          }
          if (cell != null) {
            boxes.add(
              NativeTextBox(
                start: start + offset - fragment.start,
                end: start + end - fragment.start,
                rect: cell,
                direction: direction!,
              ),
            );
          }
          offset = end;
        }
      }
      if (buffer.length > regionStart) {
        final rect = MatrixUtils.transformRect(
          transform,
          Offset.zero & page.size,
        ).intersect(bounds);
        final previous = regions.isEmpty ? null : regions.last;
        // Article slices make one continuous text column. Side-by-side book
        // pages stay separate so Android can use the active physical column.
        if (previous != null &&
            (previous.rect.left - rect.left).abs() < 0.5 &&
            (previous.rect.right - rect.right).abs() < 0.5 &&
            (previous.rect.bottom - rect.top).abs() < 0.5) {
          regions[regions.length - 1] = NativeTextRegion(
            start: previous.start,
            end: buffer.length,
            rect: previous.rect.expandToInclude(rect),
          );
        } else {
          regions.add(
            NativeTextRegion(
              start: regionStart,
              end: buffer.length,
              rect: rect,
            ),
          );
        }
      }
    }
    return TextNativeSelectionGeometry._(
      visible,
      transforms,
      viewport.size,
      fragments,
      buffer.toString(),
      List.unmodifiable(boxes),
      List.unmodifiable(regions),
    );
  }

  final List<RenderTextColumnPage> _pages;
  final List<Matrix4> _transforms;
  final Size _size;
  final List<_NativeParagraph> _fragments;
  final String text;
  final List<NativeTextBox> boxes;
  final List<NativeTextRegion> regions;

  bool matches(Iterable<RenderTextColumnPage> pages, RenderBox viewport) {
    if (_size != viewport.size) return false;
    final bounds = Offset.zero & viewport.size;
    var i = 0;
    for (final page in pages) {
      final transform = page.getTransformTo(viewport);
      if (!MatrixUtils.transformRect(
        transform,
        Offset.zero & page.size,
      ).overlaps(bounds)) {
        continue;
      }
      if (i >= _pages.length ||
          !identical(page, _pages[i]) ||
          transform != _transforms[i]) {
        return false;
      }
      i++;
    }
    if (i != _pages.length) return false;
    for (final fragment in _fragments) {
      if (!fragment.page.selectionFragments.contains(fragment.selectable) ||
          fragment.origin != fragment.selectable.origin) {
        return false;
      }
    }
    return true;
  }

  TextSelection? get selection {
    int? start;
    int? end;
    for (final fragment in _fragments) {
      final selected = fragment.selectable.selection;
      if (selected == null || selected.isCollapsed) continue;
      start ??= fragment.start + selected.start - fragment.selectable.start;
      end = fragment.start + selected.end - fragment.selectable.start;
    }
    return start == null || end == null
        ? null
        : TextSelection(baseOffset: start, extentOffset: end);
  }

  /// A point just inside the corresponding grapheme's leading/trailing half.
  /// Existing selection events keep the region delegates and CFI source maps
  /// synchronized when native handles change the selected range.
  Offset? edgeAt(int offset, {required bool isEnd}) {
    if (offset < 0 || offset > text.length) return null;
    final ordered = isEnd ? _fragments.reversed : _fragments;
    for (final fragment in ordered) {
      final length = fragment.selectable.end - fragment.selectable.start;
      if (isEnd
          ? offset <= fragment.start
          : offset >= fragment.start + length) {
        continue;
      }
      if (isEnd ? offset > fragment.start + length : offset < fragment.start) {
        continue;
      }
      final local = fragment.selectable.start + offset - fragment.start;
      final source = fragment.selectable.item.paragraph.box.text;
      final range = source.substring(fragment.selectable.start, local);
      final char = isEnd
          ? local -
                (range.characters.isEmpty ? 0 : range.characters.last.length)
          : local;
      final remaining = source.substring(char, fragment.selectable.end);
      if (remaining.isEmpty) continue;
      final end = char + remaining.characters.first.length;
      final characterBoxes = fragment.selectable.item.paragraph.boxesFor(
        char,
        end,
      );
      if (characterBoxes.isEmpty) continue;
      final box = isEnd ? characterBoxes.last : characterBoxes.first;
      final rect = box.toRect().shift(fragment.selectable.origin);
      final trailing = isEnd != (box.direction == TextDirection.rtl);
      final x = trailing
          ? rect.right - rect.width / 4
          : rect.left + rect.width / 4;
      return fragment.page.localToGlobal(
        Offset(x, rect.center.dy),
      );
    }
    // Separators have no glyph. Their selection edge belongs to the adjacent
    // paragraph, matching the source range that Pagecraft already emits.
    final candidates = isEnd ? boxes.reversed : boxes;
    for (final box in candidates) {
      if (isEnd ? box.end <= offset : box.start >= offset) {
        return edgeAt(isEnd ? box.end : box.start, isEnd: isEnd);
      }
    }
    return null;
  }

  NativeSelectionSnapshot snapshot({
    required int revision,
    required Color accent,
    required Color selectionColor,
  }) => NativeSelectionSnapshot(
    revision: revision,
    text: text,
    boxes: boxes,
    regions: regions,
    selection: selection,
    accent: accent,
    selectionColor: selectionColor,
  );
}

class _NativeParagraph {
  _NativeParagraph(this.page, this.selectable, this.start)
    : origin = selectable.origin;

  final RenderTextColumnPage page;
  final PageParagraphSelectable selectable;
  final int start;
  final Offset origin;
}

/// Shared lifecycle for paged books and scrolling articles. No platform view
/// exists until the initial Flutter long press has released its pointer.
class TextNativeSelectionController extends ChangeNotifier {
  TextNativeSelectionController({
    required this.pages,
    required this.viewport,
    required this.region,
    required this.selectionState,
    required this.contextMenuBuilder,
    required this.onChanged,
    required this.onClear,
  }) {
    NativeSelectionPlatform.isAvailable.then((available) {
      if (_disposed) return;
      _available = available;
      if (available) refresh();
    });
  }

  final Iterable<RenderTextColumnPage> Function() pages;
  final BuildContext Function() viewport;
  final SelectionHandler? Function() region;
  final SelectableRegionState? Function() selectionState;
  final SelectableRegionContextMenuBuilder? Function() contextMenuBuilder;
  final VoidCallback onChanged;
  final VoidCallback onClear;
  TextNativeSelectionGeometry? _geometry;
  NativeSelectionSnapshot? _snapshot;
  int _revision = 0;
  bool _available = false;
  bool _scheduled = false;
  bool _disposed = false;
  bool _deferred = false;
  bool active = false;
  bool selecting = false;
  ContextMenuController? _menu;
  bool _menuAdjusting = false;
  bool _menuScheduled = false;
  bool _menuRequested = false;

  NativeSelectionSnapshot? get snapshot => _snapshot;

  void refresh({bool deferred = false}) {
    _deferred = deferred;
    if (_disposed || !_available || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_disposed) return;
      final currentPages = pages().toList();
      if (!currentPages.any((page) => page.selection != null)) {
        _geometry = null;
        _hideMenu();
        if (_snapshot == null) return;
        _snapshot = null;
        notifyListeners();
        return;
      }
      // Gesture cancellation dismisses native UI even while geometry waits
      // for the initial pointer to leave the scrolling view.
      if (_deferred) return;
      final context = viewport();
      final view = context.findRenderObject();
      if (view is! RenderBox || !view.attached || !view.hasSize) return;
      if (_geometry?.matches(currentPages, view) != true) {
        _geometry = TextNativeSelectionGeometry.capture(currentPages, view);
        _revision++;
      }
      final geometry = _geometry!;
      final style = DefaultSelectionStyle.of(context);
      final accent =
          style.selectionColor?.withValues(alpha: 1) ??
          style.cursorColor ??
          const Color(0xFF007AFF);
      final selectionColor =
          style.selectionColor ?? DefaultSelectionStyle.defaultColor;
      if (_snapshot != null &&
          _snapshot!.revision == _revision &&
          (_snapshot!.accent != accent ||
              _snapshot!.selectionColor != selectionColor)) {
        _revision++;
      }
      if (_snapshot?.revision == _revision &&
          _snapshot?.selection == geometry.selection) {
        return;
      }
      if (active &&
          !_menuAdjusting &&
          _snapshot?.selection != geometry.selection) {
        _menuRequested = true;
      }
      _snapshot = geometry.snapshot(
        revision: _revision,
        accent: accent,
        selectionColor: selectionColor,
      );
      notifyListeners();
      _scheduleMenu();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void setActive(bool value) {
    if (_disposed || active == value) return;
    active = value;
    if (value) {
      selectionState()?.hideToolbar(true);
      _menuRequested = true;
      _scheduleMenu();
    } else {
      _hideMenu();
    }
    notifyListeners();
  }

  void setAdjusting(bool value) {
    if (_disposed || _menuAdjusting == value) return;
    _menuAdjusting = value;
    if (value) {
      _hideMenu();
    } else if (active) {
      _menuRequested = true;
      _scheduleMenu();
    }
  }

  void _hideMenu() {
    _menuRequested = false;
    _menu?.remove();
    _menu = null;
  }

  void _scheduleMenu() {
    if (_disposed || !active || _menuAdjusting || _menuScheduled) return;
    _menuScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _menuScheduled = false;
      if (_disposed ||
          !active ||
          _menuAdjusting ||
          !_menuRequested ||
          _snapshot?.selection == null) {
        return;
      }
      final state = selectionState();
      if (state == null || !state.mounted) return;
      if (_menu?.isShown == true) {
        _menu!.markNeedsBuild();
        return;
      }
      final menu = ContextMenuController(
        onRemove: () => _menuRequested = false,
      );
      _menu = menu;
      menu.show(
        context: viewport(),
        contextMenuBuilder: (context) {
          final builder = contextMenuBuilder();
          if (builder != null) return builder(context, state);
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: state.contextMenuAnchors,
            buttonItems: [
              for (final item in state.contextMenuButtonItems)
                ContextMenuButtonItem(
                  type: item.type,
                  label: item.label,
                  onPressed: () {
                    _hideMenu();
                    item.onPressed?.call();
                  },
                ),
            ],
          );
        },
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void setSelection(TextSelection? selection) {
    if (_disposed || selecting) return;
    if (selection == null || selection.isCollapsed) {
      onClear();
      refresh();
      return;
    }
    final geometry = _geometry;
    final delegate = region();
    if (geometry == null || delegate == null) return;
    final start = geometry.edgeAt(selection.start, isEnd: false);
    final end = geometry.edgeAt(selection.end, isEnd: true);
    if (start == null || end == null) return;
    selecting = true;
    try {
      delegate.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forStart(globalPosition: start),
      );
      delegate.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forEnd(globalPosition: end),
      );
    } finally {
      selecting = false;
    }
    onChanged();
    refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _hideMenu();
    _geometry = null;
    _snapshot = null;
    super.dispose();
  }
}

/// Exposes the SelectionArea delegate without coupling document models to it.
class TextSelectionRegionProbe extends StatefulWidget {
  const TextSelectionRegionProbe({
    super.key,
    required this.onRegion,
    required this.child,
  });

  final ValueChanged<SelectionHandler?> onRegion;
  final Widget child;

  @override
  State<TextSelectionRegionProbe> createState() =>
      _TextSelectionRegionProbeState();
}

class _TextSelectionRegionProbeState extends State<TextSelectionRegionProbe> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registrar = SelectionContainer.maybeOf(context);
    widget.onRegion(
      registrar is SelectionHandler ? registrar as SelectionHandler : null,
    );
  }

  @override
  void dispose() {
    widget.onRegion(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
