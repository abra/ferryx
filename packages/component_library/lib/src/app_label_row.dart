import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'theme/tokens/app_spacing.dart';

/// A label and a secondary text after it, the label first: it keeps its
/// whole width while it fits, the trailing text takes what is left (end it
/// with an ellipsis) and hides when less than [minTrailingWidth] remains.
/// A `Row` cannot say this: an `Expanded` label always yields to the text
/// after it, and two flexible children split the room in fixed shares.
///
/// Fills the width it is given; the trailing text sits at the end. Both
/// are centred on the row's height. Widths come from the children's
/// intrinsic widths, which a `Text` caches, so long lists stay cheap.
class AppLabelRow extends MultiChildRenderObjectWidget {
  AppLabelRow({
    required Widget label,
    required Widget trailing,
    this.gap = AppSpacing.sm,
    this.minTrailingWidth = 24,
    super.key,
  }) : super(children: [label, trailing]);

  final double gap;
  final double minTrailingWidth;

  @override
  RenderAppLabelRow createRenderObject(BuildContext context) =>
      RenderAppLabelRow(gap: gap, minTrailingWidth: minTrailingWidth);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderAppLabelRow renderObject,
  ) => renderObject
    ..gap = gap
    ..minTrailingWidth = minTrailingWidth;
}

/// The render object of [AppLabelRow]; public for tests.
class RenderAppLabelRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _LabelRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _LabelRowParentData> {
  RenderAppLabelRow({required this._gap, required this._minTrailingWidth});

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  double _minTrailingWidth;
  set minTrailingWidth(double value) {
    if (value == _minTrailingWidth) return;
    _minTrailingWidth = value;
    markNeedsLayout();
  }

  bool _showsTrailing = true;

  /// Whether the trailing child had room at the last layout.
  bool get showsTrailing => _showsTrailing;

  RenderBox get _label => firstChild!;
  RenderBox get _trailing => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _LabelRowParentData) {
      child.parentData = _LabelRowParentData();
    }
  }

  /// The widths the label and the trailing child get in [maxWidth].
  (double, double) _widths(double maxWidth, double height) {
    final label = _label.getMaxIntrinsicWidth(height);
    final trailing = _trailing.getMaxIntrinsicWidth(height);
    if (!maxWidth.isFinite) return (label, trailing);
    final labelWidth = math.min(label, maxWidth);
    final room = maxWidth - labelWidth - _gap;
    if (room < math.min(_minTrailingWidth, trailing)) return (maxWidth, 0);
    return (labelWidth, math.min(trailing, room));
  }

  @override
  void performLayout() {
    final height = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : double.infinity;
    final (labelWidth, trailingWidth) = _widths(constraints.maxWidth, height);
    _showsTrailing = trailingWidth > 0;
    BoxConstraints within(double width) =>
        BoxConstraints(maxWidth: width, maxHeight: constraints.maxHeight);
    _label.layout(within(labelWidth), parentUsesSize: true);
    _trailing.layout(within(trailingWidth), parentUsesSize: true);
    final rowHeight = math.max(
      _label.size.height,
      _showsTrailing ? _trailing.size.height : 0.0,
    );
    final width = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : labelWidth + (_showsTrailing ? _gap + trailingWidth : 0);
    size = constraints.constrain(Size(width, rowHeight));
    (_label.parentData! as _LabelRowParentData).offset = Offset(
      0,
      (size.height - _label.size.height) / 2,
    );
    (_trailing.parentData! as _LabelRowParentData).offset = Offset(
      size.width - _trailing.size.width,
      (size.height - _trailing.size.height) / 2,
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _label.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _label.getMaxIntrinsicWidth(height) +
      _gap +
      _trailing.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) => math.max(
    _label.getMinIntrinsicHeight(width),
    _trailing.getMinIntrinsicHeight(width),
  );

  @override
  double computeMaxIntrinsicHeight(double width) => math.max(
    _label.getMaxIntrinsicHeight(width),
    _trailing.getMaxIntrinsicHeight(width),
  );

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) {
    context.paintChild(
      _label,
      offset + (_label.parentData! as _LabelRowParentData).offset,
    );
    if (_showsTrailing) {
      context.paintChild(
        _trailing,
        offset + (_trailing.parentData! as _LabelRowParentData).offset,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    visitor(_label);
    if (_showsTrailing) visitor(_trailing);
  }
}

class _LabelRowParentData extends ContainerBoxParentData<RenderBox> {}
