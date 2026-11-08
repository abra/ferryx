import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'app_key_cap.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_spacing.dart';

/// One entry of [AppKeyHints]: the keys and what they do.
@immutable
class AppKeyHint {
  const AppKeyHint(this.keys, this.label, {this.typed = false});

  /// Key labels, each drawn as its own cap (`['←', '→']`); build them with
  /// `Chord.keyLabel` so they read right on every desktop.
  final List<String> keys;
  final String label;

  /// The keys are typed text (Vim's `l`, `gg`, `/`): see [AppKeyCap.typed].
  final bool typed;
}

/// The keys that work right now, as a strip of caps and words that wraps:
/// `← → width   ⇧ step 64   ↩ done   esc cancel`. Shown where a mode takes
/// keys the rest of the app does not (resizing a panel, the PDF area).
class AppKeyHints extends StatelessWidget {
  const AppKeyHints(this.hints, {this.singleLine = false, super.key});

  final List<AppKeyHint> hints;

  /// Shows only the leading entries that fit, each in full. Use for a
  /// fixed-height footer, with the most useful hints first.
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final style = context.text.bodySmall?.copyWith(
      color: context.appColors.textMuted,
    );
    final entries = [
      for (final hint in hints)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final key in hint.keys) ...[
              AppKeyCap(key, typed: hint.typed),
              const SizedBox(width: AppSpacing.xxs),
            ],
            const SizedBox(width: AppSpacing.xxs),
            Text(hint.label, style: style),
          ],
        ),
    ];
    if (singleLine) return _HintLine(children: entries);
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: entries,
    );
  }
}

/// Hints have no controls: the hidden suffix must not be painted or read
/// by assistive technology. Measure the actual caps and text once per
/// layout, including the current font and text scale.
class _HintLine extends MultiChildRenderObjectWidget {
  const _HintLine({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHintLine(Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, _RenderHintLine renderObject) {
    renderObject.textDirection = Directionality.of(context);
  }

  @override
  MultiChildRenderObjectElement createElement() => _HintLineElement(this);
}

class _HintLineElement extends MultiChildRenderObjectElement {
  _HintLineElement(super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    for (final child in children.take(
      (renderObject as _RenderHintLine).shown,
    )) {
      visitor(child);
    }
  }
}

class _HintParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderHintLine extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HintParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HintParentData> {
  _RenderHintLine(this._textDirection);

  int shown = 0;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HintParentData) {
      child.parentData = _HintParentData();
    }
  }

  @override
  void performLayout() {
    final previous = shown;
    shown = 0;
    var width = 0.0;
    var height = 0.0;
    var fits = true;
    for (final child in getChildrenAsList()) {
      child.layout(const BoxConstraints(), parentUsesSize: true);
      final end = width + (shown == 0 ? 0 : AppSpacing.md) + child.size.width;
      fits = fits && end <= constraints.maxWidth;
      if (!fits) continue;
      width = end;
      if (height < child.size.height) height = child.size.height;
      shown++;
    }
    size = constraints.constrain(Size(width, height));
    var start = 0.0;
    for (final child in getChildrenAsList().take(shown)) {
      (child.parentData! as _HintParentData).offset = Offset(
        _textDirection == TextDirection.ltr
            ? start
            : size.width - start - child.size.width,
        (size.height - child.size.height) / 2,
      );
      start += child.size.width + AppSpacing.md;
    }
    if (previous != shown) markNeedsSemanticsUpdate();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    var width = 0.0;
    var height = 0.0;
    var gap = 0.0;
    for (final child in getChildrenAsList()) {
      final natural = child.getDryLayout(const BoxConstraints());
      final end = width + gap + natural.width;
      if (end > constraints.maxWidth) break;
      width = end;
      if (height < natural.height) height = natural.height;
      gap = AppSpacing.md;
    }
    return constraints.constrain(Size(width, height));
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      getChildrenAsList().fold(
        0.0,
        (sum, child) => sum + child.getMaxIntrinsicWidth(height),
      ) +
      (childCount > 0 ? (childCount - 1) * AppSpacing.md : 0);

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in getChildrenAsList().take(shown)) {
      context.paintChild(
        child,
        offset + (child.parentData! as _HintParentData).offset,
      );
    }
  }

  @override
  bool paintsChild(RenderBox child) =>
      getChildrenAsList().take(shown).contains(child);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    for (final child in getChildrenAsList().take(shown)) {
      visitor(child);
    }
  }
}
