import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Shows [child] when its natural width fits the width it is given, else
/// [fallback]: a toolbar whose labels give way to icons, a note that moves
/// under its heading. The test is the real text's width, not a guessed
/// breakpoint, because the faces and their sizes differ by platform.
///
/// The width is [child]'s max intrinsic width, so [child] may stretch
/// (`Expanded`, `Spacer`) once it fits. Both stay mounted and laid out
/// (switching keeps their state and costs no rebuild); only the one shown
/// is painted, hit-tested, read by screen readers and seen by finders as
/// onstage, as with `Offstage`.
///
/// Neither form can take keyboard focus, or the hidden copy would: it is
/// for labels and pointer toolbars that leave the focus where it is. A row
/// of focusable controls that must fold goes in an `OverflowBar` or `Wrap`.
class AppFitOrElse extends MultiChildRenderObjectWidget {
  AppFitOrElse({required Widget child, required Widget fallback, super.key})
    : super(
        children: [
          ExcludeFocus(child: child),
          ExcludeFocus(child: fallback),
        ],
      );

  @override
  RenderObject createRenderObject(BuildContext context) => RenderFitOrElse();

  @override
  MultiChildRenderObjectElement createElement() => _FitOrElseElement(this);
}

class _FitOrElseElement extends MultiChildRenderObjectElement {
  _FitOrElseElement(super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    final fits = (renderObject as RenderFitOrElse).fits;
    visitor(fits ? children.first : children.last);
  }
}

/// The render object of [AppFitOrElse]; public for tests.
class RenderFitOrElse extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FitParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FitParentData> {
  bool _fits = true;

  /// Whether [AppFitOrElse.child] is the one on show after the last layout.
  bool get fits => _fits;

  RenderBox get _wide => firstChild!;
  RenderBox get _narrow => lastChild!;
  RenderBox get _shown => _fits ? _wide : _narrow;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FitParentData) {
      child.parentData = _FitParentData();
    }
  }

  bool _fitsIn(BoxConstraints constraints) {
    final height = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : double.infinity;
    return _wide.getMaxIntrinsicWidth(height) <=
        constraints.maxWidth + precisionErrorTolerance;
  }

  @override
  void performLayout() {
    _fits = _fitsIn(constraints);
    _wide.layout(constraints, parentUsesSize: true);
    _narrow.layout(constraints, parentUsesSize: true);
    size = _shown.size;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      (_fitsIn(constraints) ? _wide : _narrow).getDryLayout(constraints);

  @override
  double computeMinIntrinsicWidth(double height) =>
      _narrow.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _wide.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      (width.isFinite && _wide.getMaxIntrinsicWidth(double.infinity) > width
              ? _narrow
              : _wide)
          .getMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      (width.isFinite && _wide.getMaxIntrinsicWidth(double.infinity) > width
              ? _narrow
              : _wide)
          .getMaxIntrinsicHeight(width);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _shown.getDistanceToActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) =>
      context.paintChild(_shown, offset);

  @override
  bool paintsChild(RenderBox child) => child == _shown;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      _shown.hitTest(result, position: position);

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) =>
      visitor(_shown);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      FlagProperty('fits', value: _fits, ifTrue: 'child', ifFalse: 'fallback'),
    );
  }
}

class _FitParentData extends ContainerBoxParentData<RenderBox> {}
