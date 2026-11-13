import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'native_selection_snapshot.dart';

const _surfaceType = 'io.github.abra.native_text_selection/surface';

/// Checks registration rather than assuming a plugin exists on every host.
abstract final class NativeSelectionPlatform {
  static Future<bool>? _availability;

  static Future<bool> get isAvailable => _availability ??= _check();

  static Future<bool> _check() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return false;
    }
    try {
      return await const MethodChannel(
            'io.github.abra.native_text_selection/capabilities',
          ).invokeMethod<bool>('isAvailable') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @visibleForTesting
  static void resetAvailability() => _availability = null;
}

/// Hosts system selection controls over Flutter-rendered text.
///
/// The child owns layout and initial word selection. A native surface exists
/// only for an active range; scrolling and page turns otherwise use Flutter's
/// ordinary gesture arena. Unsupported hosts retain their Flutter controls.
class NativeSelectionSurface extends StatefulWidget {
  const NativeSelectionSurface({
    super.key,
    required this.child,
    required this.snapshot,
    required this.onSelectionChanged,
    this.onAdjusting,
    this.onAvailabilityChanged,
    this.onActiveChanged,
    this.onAction,
    this.enabled = true,
  });

  final Widget child;
  final NativeSelectionSnapshot? snapshot;
  final ValueChanged<TextSelection?> onSelectionChanged;
  final ValueChanged<bool>? onAdjusting;
  final ValueChanged<bool>? onAvailabilityChanged;
  final ValueChanged<bool>? onActiveChanged;
  final ValueChanged<String>? onAction;
  final bool enabled;

  @override
  State<NativeSelectionSurface> createState() => _NativeSelectionSurfaceState();
}

class _NativeSelectionSurfaceState extends State<NativeSelectionSurface> {
  MethodChannel? _channel;
  bool _available = false;
  bool _active = false;
  bool _adjusting = false;
  bool _scheduled = false;
  int? _sentRevision;
  TextSelection? _sentSelection;
  int _generation = 0;
  (int, TextSelection?)? _unsupportedRange;

  bool get _showsSurface {
    final snapshot = widget.snapshot;
    final selection = snapshot?.selection;
    return _available &&
        widget.enabled &&
        snapshot != null &&
        _unsupportedRange != (snapshot.revision, snapshot.selection) &&
        snapshot.boxes.isNotEmpty &&
        selection != null &&
        selection.isValid &&
        !selection.isCollapsed;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_checkAvailability());
  }

  Future<void> _checkAvailability() async {
    final available = await NativeSelectionPlatform.isAvailable;
    if (!mounted) return;
    setState(() => _available = available);
    widget.onAvailabilityChanged?.call(available);
  }

  @override
  void didUpdateWidget(NativeSelectionSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_showsSurface) {
      _scheduleSync();
    } else if (_channel != null) {
      // Drop stale callbacks before the platform view's asynchronous disposal.
      _disconnect();
    }
  }

  void _scheduleSync() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted && _showsSurface) unawaited(_sync());
    });
  }

  Future<void> _onCreated(int id) async {
    if (!mounted || !_showsSurface) return;
    _disconnect();
    final channel = MethodChannel('$_surfaceType/$id');
    _channel = channel;
    channel.setMethodCallHandler(_onNativeCall);
    await _sync();
  }

  Future<void> _sync() async {
    final snapshot = widget.snapshot;
    final channel = _channel;
    if (snapshot == null || channel == null) return;
    final generation = _generation;
    try {
      if (_sentRevision != snapshot.revision) {
        _sentRevision = snapshot.revision;
        _sentSelection = snapshot.selection;
        final accepted = await channel.invokeMethod<bool>(
          'update',
          snapshot.toMessage(),
        );
        if (accepted == false) {
          if (_isCurrentRequest(snapshot, generation)) _unsupported();
          return;
        }
      } else if (!_sameRange(_sentSelection, snapshot.selection)) {
        _sentSelection = snapshot.selection;
        final selection = snapshot.selection;
        if (selection == null) {
          await channel.invokeMethod<void>('clear');
        } else {
          await channel.invokeMethod<void>('select', {
            'base': selection.baseOffset,
            'extent': selection.extentOffset,
          });
        }
      }
    } on PlatformException {
      if (_isCurrentRequest(snapshot, generation)) _unsupported();
    } on MissingPluginException {
      if (_isCurrentRequest(snapshot, generation)) _unsupported();
    }
  }

  // Document anchors may normalize handle order. Do not echo that normalization
  // into an ongoing native drag of the same selected range.
  bool _sameRange(TextSelection? first, TextSelection? second) => first == null
      ? second == null
      : second != null &&
            first.start == second.start &&
            first.end == second.end;

  bool _isCurrentRequest(NativeSelectionSnapshot snapshot, int generation) =>
      mounted &&
      generation == _generation &&
      widget.snapshot?.revision == snapshot.revision &&
      widget.snapshot?.selection == snapshot.selection;

  Future<void> _onNativeCall(MethodCall call) async {
    final message = call.arguments;
    final snapshot = widget.snapshot;
    if (!mounted ||
        snapshot == null ||
        message is! Map ||
        message['revision'] != snapshot.revision) {
      return;
    }
    switch (call.method) {
      case 'ready':
        if (!_active && _showsSurface) {
          _active = true;
          widget.onActiveChanged?.call(true);
        }
      case 'selectionChanged':
        final base = message['base'];
        final extent = message['extent'];
        if (base is! int || extent is! int) return;
        if (base == -1 && extent == -1) {
          _sentSelection = null;
          widget.onSelectionChanged(null);
        } else if (base >= 0 &&
            extent >= 0 &&
            base <= snapshot.text.length &&
            extent <= snapshot.text.length) {
          final selection = TextSelection(
            baseOffset: base,
            extentOffset: extent,
          );
          if (_sentSelection == selection) return;
          _sentSelection = selection;
          widget.onSelectionChanged(selection);
        }
      case 'adjusting':
        final value = message['value'];
        if (value is! bool || value == _adjusting) return;
        _adjusting = value;
        widget.onAdjusting?.call(value);
      case 'unsupportedGeometry':
        _unsupported();
      case 'action':
        final action = message['action'];
        if (action is String) widget.onAction?.call(action);
    }
  }

  void _unsupported() {
    final snapshot = widget.snapshot;
    _disconnect();
    setState(() {
      _unsupportedRange = snapshot == null
          ? null
          : (snapshot.revision, snapshot.selection);
    });
  }

  void _notify<T>(ValueChanged<T>? callback, T value) {
    if (callback == null) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) callback(value);
      });
    } else {
      callback(value);
    }
  }

  void _disconnect({bool notify = true}) {
    _generation++;
    _channel?.setMethodCallHandler(null);
    _channel = null;
    _sentRevision = null;
    _sentSelection = null;
    if (_adjusting) {
      _adjusting = false;
      if (notify) _notify(widget.onAdjusting, false);
    }
    if (_active) {
      _active = false;
      if (notify) _notify(widget.onActiveChanged, false);
    }
  }

  @override
  void dispose() {
    _disconnect(notify: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      widget.child,
      if (_showsSurface)
        Positioned.fill(
          child: _NativePlatformSelectionView(
            snapshot: widget.snapshot!,
            onCreated: _onCreated,
          ),
        ),
    ],
  );
}

class _NativePlatformSelectionView extends StatefulWidget {
  const _NativePlatformSelectionView({
    required this.snapshot,
    required this.onCreated,
  });

  final NativeSelectionSnapshot snapshot;
  final PlatformViewCreatedCallback onCreated;

  @override
  State<_NativePlatformSelectionView> createState() =>
      _NativePlatformSelectionViewState();
}

class _NativePlatformSelectionViewState
    extends State<_NativePlatformSelectionView> {
  late final _gestures = <Factory<OneSequenceGestureRecognizer>>{
    Factory<_NativeHandleGestureRecognizer>(
      () => _NativeHandleGestureRecognizer(_isHandlePointer),
    ),
  };

  bool _isHandlePointer(Offset global) {
    final render = context.findRenderObject();
    final snapshot = widget.snapshot;
    final selection = snapshot.selection;
    if (render is! RenderBox || selection == null) return false;
    final local = render.globalToLocal(global);
    final scale = render.getTransformTo(null).getMaxScaleOnAxis();
    final padding = scale > 0 ? 24 / scale : 24.0;
    for (final start in [true, false]) {
      final offset = start ? selection.start : selection.end;
      final box = snapshot.caretCellAt(offset, upstream: !start);
      if (box != null) {
        final leading =
            (offset < box.end) != (box.direction == TextDirection.rtl);
        final x = leading ? box.rect.left : box.rect.right;
        if (Rect.fromLTRB(
          x - padding,
          box.rect.top - padding,
          x + padding,
          box.rect.bottom + padding,
        ).contains(local)) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _NativeSelectionHitRegion(
        canHit: _isHandlePointer,
        child: UiKitView(
          viewType: _surfaceType,
          // Cell coordinates are physical; writing direction belongs to cells.
          layoutDirection: TextDirection.ltr,
          creationParams: widget.snapshot.toMessage(),
          creationParamsCodec: const StandardMessageCodec(),
          gestureRecognizers: _gestures,
          onPlatformViewCreated: widget.onCreated,
          hitTestBehavior: PlatformViewHitTestBehavior.translucent,
        ),
      );
    }
    return _NativeSelectionHitRegion(
      canHit: _isHandlePointer,
      child: PlatformViewLink(
        viewType: _surfaceType,
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: _gestures,
          hitTestBehavior: PlatformViewHitTestBehavior.translucent,
        ),
        onCreatePlatformView: (params) =>
            PlatformViewsService.initExpensiveAndroidView(
                id: params.id,
                viewType: _surfaceType,
                layoutDirection: TextDirection.ltr,
                creationParams: widget.snapshot.toMessage(),
                creationParamsCodec: const StandardMessageCodec(),
                // Keep Flutter focus and its action menu on the text owner.
                // The read-only native Editor takes Android focus independently.
              )
              ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
              ..addOnPlatformViewCreatedListener(widget.onCreated)
              ..create(),
      ),
    );
  }
}

/// A platform view's arena captain competes even if its recognizers reject a
/// pointer. Exclude the view from hit testing entirely outside its handles.
class _NativeSelectionHitRegion extends SingleChildRenderObjectWidget {
  const _NativeSelectionHitRegion({required this.canHit, required super.child});

  final bool Function(Offset) canHit;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNativeSelectionHitRegion(canHit);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderNativeSelectionHitRegion renderObject,
  ) {
    renderObject.canHit = canHit;
  }
}

class _RenderNativeSelectionHitRegion extends RenderProxyBox {
  _RenderNativeSelectionHitRegion(this.canHit);

  bool Function(Offset) canHit;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      canHit(localToGlobal(position)) &&
      super.hitTest(result, position: position);
}

class _NativeHandleGestureRecognizer extends EagerGestureRecognizer {
  _NativeHandleGestureRecognizer(this.canStart);

  final bool Function(Offset) canStart;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      canStart(event.position) && super.isPointerAllowed(event);
}
