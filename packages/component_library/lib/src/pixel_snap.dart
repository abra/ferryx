import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import 'app_scrollbar.dart';
import 'theme/app_platform_style.dart';
import 'theme/extensions/build_context_ext.dart';

/// Paints [child] on the pixels of the layer it is painted in: shifted by
/// under half a device pixel, so its top left lands on one. The hairline
/// borders snap within their layer (`snapToPixels`); a layer is on the
/// screen's pixels when each layer it sits in was placed so. Put one where
/// a subtree that makes layers lands at a fraction: a surface placed by
/// centring or by an anchor (a dialog, a menu), a scroll view below text,
/// a list's row on its own layer. The size stays as laid out; hit testing
/// and the paint transform take the shift too, so what is anchored to a
/// child lines up with what is drawn.
class PixelSnap extends SingleChildRenderObjectWidget {
  const PixelSnap({super.child, super.key});

  @override
  RenderPixelSnap createRenderObject(BuildContext context) =>
      RenderPixelSnap(MediaQuery.devicePixelRatioOf(context));

  @override
  void updateRenderObject(BuildContext context, RenderPixelSnap renderObject) {
    renderObject.devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class RenderPixelSnap extends RenderProxyBox {
  RenderPixelSnap(this._devicePixelRatio);

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  /// How far the child was moved at the last paint.
  Offset _shift = Offset.zero;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    // [offset] is this box's place in its layer: a list scrolled moves it,
    // and its viewport paints it again there.
    double onPixel(double v) =>
        (v * _devicePixelRatio).roundToDouble() / _devicePixelRatio;
    final snapped = Offset(onPixel(offset.dx), onPixel(offset.dy));
    _shift = snapped - offset;
    context.paintChild(child, snapped);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _shift,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_shift.dx, _shift.dy, 0, 1);
  }
}

/// A list's row on a layer of its own, on the screen's pixels: Flutter's
/// own boundary for a row ([RepaintBoundary], so scrolling moves the row
/// without painting it again) would sit wherever the rows above it add up
/// to. Here the row's layer lands on a pixel of the list's ([PixelSnap])
/// and its height is rounded up to a whole pixel, so the rows below land
/// alike: rows that touch, a selection's fills, stay touching. For a list
/// built with `addRepaintBoundaries: false`; [wrap] keeps the row's key.
class PixelRow extends StatelessWidget {
  const PixelRow({required this.child, super.key});

  /// [row] in a [PixelRow] under the row's own key, which the list finds
  /// the row by; a global key stays the row's alone.
  factory PixelRow.wrap(Widget row) =>
      PixelRow(key: row.key is GlobalKey ? null : row.key, child: row);

  final Widget child;

  @override
  Widget build(BuildContext context) => PixelSnap(
    child: _WholePixelHeight(
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      child: RepaintBoundary(child: child),
    ),
  );
}

/// [builder]'s rows in [PixelRow]s: the item builder of a list built with
/// `addRepaintBoundaries: false`.
NullableIndexedWidgetBuilder pixelRows(NullableIndexedWidgetBuilder builder) =>
    (context, index) => switch (builder(context, index)) {
      final row? => PixelRow.wrap(row),
      null => null,
    };

/// A surface's content, sized so that the parent centring the surface
/// puts it on whole pixels: rounded up to a whole device pixel, and one
/// more where the room left around it is odd. For a surface centred where
/// no [PixelSnap] can reach (a [Dialog] centres its Material), whose fill,
/// edge and clip would otherwise straddle a pixel at each side.
class CentredOnPixels extends SingleChildRenderObjectWidget {
  const CentredOnPixels({super.child, super.key});

  @override
  RenderCentredOnPixels createRenderObject(BuildContext context) =>
      RenderCentredOnPixels(MediaQuery.devicePixelRatioOf(context));

  @override
  void updateRenderObject(
    BuildContext context,
    RenderCentredOnPixels renderObject,
  ) {
    renderObject.devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class RenderCentredOnPixels extends RenderProxyBox {
  RenderCentredOnPixels(this._devicePixelRatio);

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsLayout();
  }

  /// [extent] in a room of [room], both along one axis.
  double _even(double extent, double room) {
    if (!room.isFinite) return extent;
    // An extent a rounding error off a pixel is on it.
    var pixels = (extent * _devicePixelRatio - 0.01).ceil();
    if (((room * _devicePixelRatio).round() - pixels).isOdd) pixels++;
    return pixels / _devicePixelRatio;
  }

  Size _fit(Size size, BoxConstraints constraints) => constraints.constrain(
    Size(
      _even(size.width, constraints.maxWidth),
      _even(size.height, constraints.maxHeight),
    ),
  );

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return _fit(child.getDryLayout(constraints), constraints);
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    final fitted = _fit(child.size, constraints);
    // The content fills the pixel it gained, so no strip of the surface
    // shows beside it. A floor, not a tight size: a child laid out tight
    // is a relayout boundary and would keep this size as its content
    // grows or shrinks.
    final floor = constraints.copyWith(
      minWidth: fitted.width,
      minHeight: fitted.height,
    );
    if (fitted != child.size && !floor.isTight) {
      child.layout(floor, parentUsesSize: true);
    }
    size = child.size;
  }
}

/// [child] as tall as it is, rounded up to a whole device pixel.
class _WholePixelHeight extends SingleChildRenderObjectWidget {
  const _WholePixelHeight({
    required this.devicePixelRatio,
    required super.child,
  });

  final double devicePixelRatio;

  @override
  _RenderWholePixelHeight createRenderObject(BuildContext context) =>
      _RenderWholePixelHeight(devicePixelRatio);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderWholePixelHeight renderObject,
  ) {
    renderObject.devicePixelRatio = devicePixelRatio;
  }
}

class _RenderWholePixelHeight extends RenderProxyBox {
  _RenderWholePixelHeight(this._devicePixelRatio);

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsLayout();
  }

  Size _whole(Size size, BoxConstraints constraints) {
    final device = size.height * _devicePixelRatio;
    final near = device.roundToDouble();
    // A height a rounding error off a pixel is on it.
    final up = (device - near).abs() < 0.01 ? near : device.ceilToDouble();
    return constraints.constrain(Size(size.width, up / _devicePixelRatio));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return _whole(child.getDryLayout(constraints), constraints);
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    size = _whole(child.size, constraints);
  }
}

/// Desktop scrolling with platform scrollbars and views placed on their
/// layer's pixels ([PixelSnap]), so their hairlines remain crisp.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => PixelSnap(
    child:
        context.metrics.style == AppPlatformStyle.macos &&
            axisDirectionToAxis(details.direction) == Axis.vertical
        ? AppScrollbar(controller: details.controller, child: child)
        : super.buildScrollbar(context, child, details),
  );
}
