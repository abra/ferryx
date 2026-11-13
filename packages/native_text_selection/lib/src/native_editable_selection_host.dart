import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import 'native_selection_snapshot.dart';
import 'native_selection_surface.dart';

/// Adds platform selection controls to an existing read-only EditableText.
/// The original widget still owns text, layout, semantics and callbacks.
/// Editable fields retain Flutter's IME connection and selection controls.
class NativeEditableSelectionHost extends StatefulWidget {
  const NativeEditableSelectionHost({super.key, required this.child});

  final Widget child;

  @override
  State<NativeEditableSelectionHost> createState() =>
      _NativeEditableSelectionHostState();
}

class _NativeEditableSelectionHostState
    extends State<NativeEditableSelectionHost> {
  EditableTextState? _editable;
  TextEditingController? _controller;
  FocusNode? _focusNode;
  ViewportOffset? _textOffset;
  ScrollPosition? _ancestorScroll;
  NativeSelectionSnapshot? _snapshot;
  List<NativeTextBox> _boxes = const [];
  Object? _geometry;
  int _revision = 0;
  int _pointers = 0;
  bool _scheduled = false;
  bool _active = false;
  bool _available = false;
  bool _adjusting = false;
  final _overlayController = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    unawaited(_checkAvailability());
  }

  Future<void> _checkAvailability() async {
    final available = await NativeSelectionPlatform.isAvailable;
    if (!mounted) return;
    _available = available;
    _scheduleCapture();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scroll = Scrollable.maybeOf(context)?.position;
    if (!identical(scroll, _ancestorScroll)) {
      _ancestorScroll?.removeListener(_scheduleCapture);
      _ancestorScroll?.isScrollingNotifier.removeListener(_scheduleCapture);
      _ancestorScroll = scroll;
      scroll?.addListener(_scheduleCapture);
      scroll?.isScrollingNotifier.addListener(_scheduleCapture);
    }
    _scheduleCapture();
  }

  @override
  void didUpdateWidget(NativeEditableSelectionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleCapture();
  }

  void _scheduleCapture() {
    if (!mounted || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _capture();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  EditableTextState? _findEditable() {
    EditableTextState? result;
    void visit(Element element) {
      if (result != null) return;
      if (element is StatefulElement && element.state is EditableTextState) {
        result = element.state as EditableTextState;
        return;
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    return result;
  }

  void _attach(EditableTextState? editable) {
    final controller = editable?.widget.controller;
    final offset = editable?.renderEditable.offset;
    final focusNode = editable?.widget.focusNode;
    if (identical(_editable, editable) &&
        identical(_controller, controller) &&
        identical(_focusNode, focusNode) &&
        identical(_textOffset, offset)) {
      return;
    }
    _restoreHighlight();
    _active = false;
    _adjusting = false;
    _controller?.removeListener(_scheduleCapture);
    _focusNode?.removeListener(_scheduleCapture);
    _textOffset?.removeListener(_scheduleCapture);
    _editable = editable;
    _controller = controller;
    _focusNode = focusNode;
    _textOffset = offset;
    controller?.addListener(_scheduleCapture);
    focusNode?.addListener(_scheduleCapture);
    offset?.addListener(_scheduleCapture);
    _geometry = null;
  }

  void _capture() {
    _attach(_findEditable());
    final editable = _editable;
    final controller = _controller;
    final viewport = Overlay.maybeOf(
      context,
      rootOverlay: true,
    )?.context.findRenderObject();
    if (!_available ||
        editable == null ||
        controller == null ||
        _focusNode?.hasFocus != true ||
        !editable.widget.readOnly ||
        editable.widget.obscureText ||
        viewport is! RenderBox ||
        !viewport.hasSize ||
        !controller.selection.isValid ||
        controller.selection.isCollapsed) {
      _hideNativeSurface(clearGeometry: true);
      return;
    }
    if (_ancestorScroll?.isScrollingNotifier.value == true) {
      editable.hideToolbar(true);
      _hideNativeSurface();
      return;
    }
    if (_pointers > 0) return;
    final renderer = editable.renderEditable;
    if (!renderer.attached || !renderer.hasSize) return;
    final transform = renderer.getTransformTo(viewport);
    final key = (
      controller.text,
      renderer.text,
      transform,
      renderer.size,
      viewport.size,
      renderer.offset.pixels,
      renderer.textScaler,
      renderer.textAlign,
      renderer.textDirection,
    );
    if (_geometry != key) {
      final boxes = <NativeTextBox>[];
      var offset = 0;
      for (final character in controller.text.characters) {
        final end = offset + character.length;
        Rect? cell;
        TextDirection? direction;
        for (final box in renderer.getBoxesForSelection(
          TextSelection(baseOffset: offset, extentOffset: end),
        )) {
          final rect = MatrixUtils.transformRect(transform, box.toRect());
          if (!rect.isEmpty) {
            cell = cell?.expandToInclude(rect) ?? rect;
            direction ??= box.direction;
          }
        }
        if (cell != null) {
          boxes.add(
            NativeTextBox(
              start: offset,
              end: end,
              rect: cell,
              direction: direction!,
            ),
          );
        }
        offset = end;
      }
      _boxes = List.unmodifiable(boxes);
      _geometry = key;
      _revision++;
    }
    final scrollViewport = _ancestorScroll?.context.notificationContext
        ?.findRenderObject();
    var visibleBounds = Offset.zero & viewport.size;
    if (scrollViewport is RenderBox && scrollViewport.hasSize) {
      visibleBounds = visibleBounds.intersect(
        MatrixUtils.transformRect(
          scrollViewport.getTransformTo(viewport),
          Offset.zero & scrollViewport.size,
        ),
      );
    }
    final range = controller.selection;
    final selectedCells = _boxes.where(
      (box) => box.start < range.end && box.end > range.start,
    );
    if (selectedCells.isEmpty ||
        !visibleBounds.contains(selectedCells.first.rect.topLeft) ||
        !visibleBounds.contains(selectedCells.first.rect.bottomRight) ||
        !visibleBounds.contains(selectedCells.last.rect.topLeft) ||
        !visibleBounds.contains(selectedCells.last.rect.bottomRight)) {
      _hideNativeSurface();
      return;
    }
    final selectionColor =
        editable.widget.selectionColor ??
        Theme.of(context).textSelectionTheme.selectionColor ??
        DefaultSelectionStyle.defaultColor;
    final accent =
        Theme.of(context).textSelectionTheme.selectionHandleColor ??
        editable.widget.cursorColor;
    final previous = _snapshot;
    if (previous != null &&
        previous.revision == _revision &&
        (previous.accent != accent ||
            previous.selectionColor != selectionColor)) {
      _revision++;
    }
    if (previous?.revision != _revision ||
        previous?.selection != controller.selection ||
        previous?.accent != accent ||
        previous?.selectionColor != selectionColor) {
      setState(() {
        _snapshot = NativeSelectionSnapshot(
          revision: _revision,
          text: controller.text,
          boxes: _boxes,
          selection: controller.selection,
          accent: accent,
          selectionColor: selectionColor,
        );
      });
    }
    if (_active) {
      renderer.selectionColor = Colors.transparent;
    }
    if (!_overlayController.isShowing) _overlayController.show();
  }

  void _hideNativeSurface({bool clearGeometry = false}) {
    if (clearGeometry) {
      _geometry = null;
      _boxes = const [];
    }
    _overlayController.hide();
    _active = false;
    _adjusting = false;
    _restoreHighlight();
    if (_snapshot != null) setState(() => _snapshot = null);
  }

  void _setActive(bool value) {
    if (value && _focusNode?.hasFocus != true) return;
    if (_active == value) return;
    _active = value;
    if (value) {
      _editable?.hideToolbar(true);
      if (!_adjusting) _editable?.showToolbar();
    } else {
      _restoreHighlight();
    }
    _scheduleCapture();
  }

  void _setAdjusting(bool value) {
    if (value && _focusNode?.hasFocus != true) return;
    if (_adjusting == value) return;
    _adjusting = value;
    if (value) {
      _editable?.hideToolbar(true);
    } else if (_active) {
      _editable?.showToolbar();
    }
  }

  void _restoreHighlight() {
    final editable = _editable;
    if (editable != null &&
        editable.mounted &&
        editable.renderEditable.attached) {
      editable.renderEditable.selectionColor = editable.widget.selectionColor;
    }
  }

  void _select(TextSelection? selection) {
    final editable = _editable;
    final controller = _controller;
    if (editable == null ||
        controller == null ||
        !editable.mounted ||
        _focusNode?.hasFocus != true) {
      return;
    }
    final next =
        selection ??
        TextSelection.collapsed(offset: controller.selection.extentOffset);
    editable.userUpdateTextEditingValue(
      controller.value.copyWith(selection: next),
      SelectionChangedCause.drag,
    );
    if (_active) {
      editable.hideToolbar(true);
      if (!_adjusting) editable.showToolbar();
    }
  }

  void _action(String action) {
    final editable = _editable;
    if (editable == null || !editable.mounted) return;
    switch (action) {
      case 'copy':
        editable.copySelection(SelectionChangedCause.toolbar);
      case 'selectAll':
        editable.selectAll(SelectionChangedCause.toolbar);
    }
    _scheduleCapture();
  }

  void _pointerDown(PointerDownEvent event) => _pointers++;

  void _pointerUp(PointerEvent event) {
    if (_pointers > 0) _pointers--;
    if (_pointers == 0) _scheduleCapture();
  }

  @override
  void dispose() {
    _restoreHighlight();
    _controller?.removeListener(_scheduleCapture);
    _focusNode?.removeListener(_scheduleCapture);
    _textOffset?.removeListener(_scheduleCapture);
    _ancestorScroll?.removeListener(_scheduleCapture);
    _ancestorScroll?.isScrollingNotifier.removeListener(_scheduleCapture);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleCapture();
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (notification) {
        _scheduleCapture();
        return false;
      },
      // Native knobs extend beyond the text's own layout and hit-test bounds.
      child: OverlayPortal(
        overlayLocation: OverlayChildLocation.rootOverlay,
        controller: _overlayController,
        overlayChildBuilder: (context) {
          final snapshot = _snapshot;
          if (snapshot == null) return const SizedBox.shrink();
          return Positioned.fill(
            child: NativeSelectionSurface(
              key: ObjectKey(_controller),
              snapshot: snapshot,
              onSelectionChanged: _select,
              onAdjusting: _setAdjusting,
              onAction: _action,
              onActiveChanged: _setActive,
              child: const SizedBox.expand(),
            ),
          );
        },
        child: SizeChangedLayoutNotifier(
          child: Listener(
            onPointerDown: _pointerDown,
            onPointerUp: _pointerUp,
            onPointerCancel: _pointerUp,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
