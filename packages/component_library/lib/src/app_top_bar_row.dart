import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_sizes.dart';
import 'theme/tokens/app_spacing.dart';

/// A top bar's row: [leading] controls, a [title] taking the room left,
/// the content's actions in the richest of their [forms] that fits, and
/// [trailing]. Neighbours stand a bar's spacing apart, groups
/// [AppSpacing.sm].
///
/// Where the platform centres a bar's title (`AppMetrics.centeredBarTitle`,
/// libadwaita's header bar), the title takes its own width and sits in the
/// middle of the whole bar, moved toward the free side as far as the
/// buttons need; a title that takes all the room it is given stays at the
/// start.
///
/// What fits is measured, not guessed from a breakpoint: faces, text sizes
/// and the platform's control sizes all change the widths. A form's width
/// is learned the first time it shows; one that turns out too wide gives
/// way on the next frame (and is scaled down for that frame), a wider bar
/// brings a richer form back. When no form fits, none shows: what they do
/// stays on the keys and in ⌘K. The bar never overruns; at a width even its
/// leading and trailing controls do not fit, it clips.
///
/// Every group is laid out at its natural width and no taller than the
/// bar, so a control that grows with the text keeps to the bar's height.
class AppTopBarRow extends StatefulWidget {
  const AppTopBarRow({
    required this.title,
    this.leading = const [],
    this.forms = const [],
    this.trailing = const [],
    this.titleMinWidth = AppSizes.topBarTitleMinWidth,
    this.preferLaterBelow,
    this.measureKey,
    this.leftInset = 0,
    this.rightInset = 0,
    super.key,
  });

  final Widget title;
  final List<Widget> leading;

  /// The content's actions, richest first: all of them, then a compact
  /// set.
  final List<List<Widget>> forms;
  final List<Widget> trailing;

  /// Room the title keeps when a form is weighed; it may still shrink to
  /// nothing at a width where no form fits.
  final double titleMinWidth;

  /// Below this width the second form is tried before the first is ever
  /// measured, so a narrow bar does not open on a frame of the richest one.
  final double? preferLaterBelow;

  /// What the learned widths belong to (the kind of page the bar is for);
  /// a new key forgets them. The text size and the locale forget them too.
  final Object? measureKey;

  /// Room kept free at the bar's left and right edges, for the window's
  /// buttons drawn over it. Nothing lays out there, but a centred title
  /// centres across it, as a header bar's title does across its window
  /// buttons.
  final double leftInset;
  final double rightInset;

  @override
  State<AppTopBarRow> createState() => _AppTopBarRowState();
}

class _AppTopBarRowState extends State<AppTopBarRow> {
  /// The width the whole bar needs with each form, once it has shown.
  final _needs = <int, double>{};
  Object? _measuredFor;
  bool _rebuildScheduled = false;

  int _formFor(double width) {
    final forms = widget.forms.length;
    for (var i = 0; i < forms; i++) {
      final need = _needs[i];
      if (need == null) {
        final guess = widget.preferLaterBelow;
        final skip = i == 0 && forms > 1 && guess != null && width < guess;
        if (!skip) return i;
        continue;
      }
      if (need <= width + precisionErrorTolerance) return i;
    }
    return forms;
  }

  /// Called from layout: remembers [need] and, when [form] is too wide for
  /// [width], rebuilds after the frame with the next form.
  void _measured(int form, double need, double width) {
    _needs[form] = need;
    if (need <= width + precisionErrorTolerance ||
        form >= widget.forms.length ||
        _rebuildScheduled) {
      return;
    }
    _rebuildScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final measuredFor = (
      widget.measureKey,
      MediaQuery.textScalerOf(context).scale(100),
      Localizations.maybeLocaleOf(context),
    );
    if (measuredFor != _measuredFor) {
      _measuredFor = measuredFor;
      _needs.clear();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final form = _formFor(constraints.maxWidth);
        final actions = form < widget.forms.length
            ? widget.forms[form]
            : const <Widget>[];
        return _TopBarLayout(
          gap: AppSpacing.sm,
          titleMinWidth: widget.titleMinWidth,
          centerTitle: context.metrics.centeredBarTitle,
          leftInset: widget.leftInset,
          rightInset: widget.rightInset,
          textDirection: Directionality.of(context),
          onNeed: (need, width) => _measured(form, need, width),
          leading: widget.leading.isEmpty ? null : _Group(widget.leading),
          title: widget.title,
          actions: actions.isEmpty ? null : _Group(actions),
          trailing: widget.trailing.isEmpty ? null : _Group(widget.trailing),
        );
      },
    );
  }
}

/// Controls of one slot side by side, the platform's toolbar spacing apart.
class _Group extends StatelessWidget {
  const _Group(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: context.metrics.toolbarSpacing,
    children: children,
  );
}

enum _Slot { leading, title, actions, trailing }

class _TopBarLayout
    extends SlottedMultiChildRenderObjectWidget<_Slot, RenderBox> {
  const _TopBarLayout({
    required this.gap,
    required this.titleMinWidth,
    required this.centerTitle,
    required this.leftInset,
    required this.rightInset,
    required this.textDirection,
    required this.onNeed,
    required this.title,
    this.leading,
    this.actions,
    this.trailing,
  });

  final double gap;
  final double titleMinWidth;
  final bool centerTitle;
  final double leftInset;
  final double rightInset;
  final TextDirection textDirection;
  final void Function(double need, double width) onNeed;
  final Widget? leading;
  final Widget title;
  final Widget? actions;
  final Widget? trailing;

  @override
  Iterable<_Slot> get slots => _Slot.values;

  @override
  Widget? childForSlot(_Slot slot) => switch (slot) {
    _Slot.leading => leading,
    _Slot.title => title,
    _Slot.actions => actions,
    _Slot.trailing => trailing,
  };

  @override
  _RenderTopBar createRenderObject(BuildContext context) => _RenderTopBar(
    gap: gap,
    titleMinWidth: titleMinWidth,
    centerTitle: centerTitle,
    leftInset: leftInset,
    rightInset: rightInset,
    textDirection: textDirection,
    onNeed: onNeed,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderTopBar renderObject) {
    renderObject
      ..gap = gap
      ..titleMinWidth = titleMinWidth
      ..centerTitle = centerTitle
      ..leftInset = leftInset
      ..rightInset = rightInset
      ..textDirection = textDirection
      ..onNeed = onNeed;
  }
}

class _RenderTopBar extends RenderBox
    with SlottedContainerRenderObjectMixin<_Slot, RenderBox> {
  _RenderTopBar({
    required this._gap,
    required this._titleMinWidth,
    required this._centerTitle,
    required this._leftInset,
    required this._rightInset,
    required this._textDirection,
    required this.onNeed,
  });

  void Function(double need, double width) onNeed;

  double get gap => _gap;
  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  double get titleMinWidth => _titleMinWidth;
  double _titleMinWidth;
  set titleMinWidth(double value) {
    if (value == _titleMinWidth) return;
    _titleMinWidth = value;
    markNeedsLayout();
  }

  bool get centerTitle => _centerTitle;
  bool _centerTitle;
  set centerTitle(bool value) {
    if (value == _centerTitle) return;
    _centerTitle = value;
    markNeedsLayout();
  }

  double get leftInset => _leftInset;
  double _leftInset;
  set leftInset(double value) {
    if (value == _leftInset) return;
    _leftInset = value;
    markNeedsLayout();
  }

  double get rightInset => _rightInset;
  double _rightInset;
  set rightInset(double value) {
    if (value == _rightInset) return;
    _rightInset = value;
    markNeedsLayout();
  }

  bool get _ltr => textDirection == TextDirection.ltr;
  double get _startInset => _ltr ? leftInset : rightInset;
  double get _endInset => _ltr ? rightInset : leftInset;

  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  bool _clipped = false;

  /// Below 1 only for the frame before a too wide form gives way, or when
  /// even the leading and trailing controls crowd the actions out.
  double _actionsScale = 1;

  RenderBox? get _leading => childForSlot(_Slot.leading);
  RenderBox get _title => childForSlot(_Slot.title)!;
  RenderBox? get _actions => childForSlot(_Slot.actions);
  RenderBox? get _trailing => childForSlot(_Slot.trailing);

  /// Start to end, as they are laid out.
  List<RenderBox> get _inOrder => [
    ?_leading,
    _title,
    ?_actions,
    ?_trailing,
  ];

  double get _gaps => gap * (_inOrder.length - 1);

  Size _laidOut(RenderBox box) =>
      box == _actions ? box.size * _actionsScale : box.size;

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final height = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : computeMaxIntrinsicHeight(width);
    // The groups at their natural width, no taller than the bar.
    final natural = BoxConstraints(maxHeight: height);
    for (final box in [?_leading, ?_actions, ?_trailing]) {
      box.layout(natural, parentUsesSize: true);
    }
    final leading = _leading?.size.width ?? 0;
    final actions = _actions?.size.width ?? 0;
    final trailing = _trailing?.size.width ?? 0;
    final insets = leftInset + rightInset;
    onNeed(
      insets + leading + actions + trailing + _gaps + titleMinWidth,
      width,
    );
    final room = math.max(0.0, width - insets - leading - trailing - _gaps);
    _actionsScale = actions > room ? room / actions : 1;
    // The title has what is left: all of it, or up to it when centred.
    final title = math.max(0.0, room - actions * _actionsScale);
    _title.layout(
      BoxConstraints(
        minWidth: centerTitle ? 0 : title,
        maxWidth: title,
        maxHeight: height,
      ),
      parentUsesSize: true,
    );
    size = constraints.constrain(Size(width, height));
    var x = _startInset;
    for (final box in _inOrder) {
      final laidOut = _laidOut(box);
      // A centred title: the bar's middle, kept within the room it has.
      final start = box == _title && centerTitle
          ? ((size.width - laidOut.width) / 2)
                .clamp(x, x + title - laidOut.width)
                .toDouble()
          : x;
      final left = _ltr ? start : size.width - start - laidOut.width;
      (box.parentData! as BoxParentData).offset = Offset(
        left,
        (size.height - laidOut.height) / 2,
      );
      x += (box == _title ? title : laidOut.width) + gap;
    }
    _clipped = x - gap > size.width - _endInset + precisionErrorTolerance;
  }

  Matrix4 _actionsTransform(Offset offset) =>
      Matrix4.translationValues(offset.dx, offset.dy, 0)
        ..scaleByDouble(_actionsScale, _actionsScale, 1, 1);

  @override
  void paint(PaintingContext context, Offset offset) {
    void paintChildren(PaintingContext context, Offset offset) {
      for (final box in _inOrder) {
        final at = offset + (box.parentData! as BoxParentData).offset;
        if (box == _actions && _actionsScale < 1) {
          context.pushTransform(
            needsCompositing,
            Offset.zero,
            _actionsTransform(at),
            (context, offset) => context.paintChild(box, offset),
          );
        } else {
          context.paintChild(box, at);
        }
      }
    }

    if (_clipped) {
      // Never under the window's buttons.
      context.pushClipRect(
        needsCompositing,
        offset,
        Rect.fromLTRB(leftInset, 0, size.width - rightInset, size.height),
        paintChildren,
      );
    } else {
      paintChildren(context, offset);
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final offset = (child.parentData! as BoxParentData).offset;
    if (child == _actions && _actionsScale < 1) {
      transform.multiply(_actionsTransform(offset));
    } else {
      transform.translateByDouble(offset.dx, offset.dy, 0, 1);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final box in _inOrder.reversed) {
      final offset = (box.parentData! as BoxParentData).offset;
      final hit = box == _actions && _actionsScale < 1
          ? result.addWithPaintTransform(
              transform: _actionsTransform(offset),
              position: position,
              hitTest: (result, transformed) =>
                  box.hitTest(result, position: transformed),
            )
          : result.addWithPaintOffset(
              offset: offset,
              position: position,
              hitTest: (result, transformed) =>
                  box.hitTest(result, position: transformed),
            );
      if (hit) return true;
    }
    return false;
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => _inOrder.fold(
    leftInset + rightInset + _gaps,
    (sum, box) => sum + box.getMaxIntrinsicWidth(height),
  );

  @override
  double computeMinIntrinsicHeight(double width) => _inOrder.fold(
    0,
    (h, box) => math.max(h, box.getMinIntrinsicHeight(double.infinity)),
  );

  @override
  double computeMaxIntrinsicHeight(double width) => _inOrder.fold(
    0,
    (h, box) => math.max(h, box.getMaxIntrinsicHeight(double.infinity)),
  );

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
    Size(
      constraints.maxWidth,
      constraints.hasBoundedHeight
          ? constraints.maxHeight
          : computeMaxIntrinsicHeight(constraints.maxWidth),
    ),
  );
}
