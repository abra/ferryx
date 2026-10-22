import 'package:flutter/material.dart';

import 'theme/extensions/build_context_ext.dart';
import 'theme/hairlines.dart';

/// A hairline rule on the screen's pixels: [Divider]'s line, which would
/// spread over two pixels at half strength wherever it lands between them.
class AppRule extends StatelessWidget {
  const AppRule({this.axis = Axis.horizontal, this.color, super.key});

  /// Across ([Axis.horizontal]) or down.
  final Axis axis;

  /// The theme's line colour when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final side = BorderSide(color: color ?? context.appColors.line);
    final across = axis == Axis.horizontal;
    // As long as the parent lets it be, as a Container without a child
    // is: the whole width under a Center or a loose column, none where the
    // parent sets no bound.
    return LimitedBox(
      maxWidth: across ? 0 : double.infinity,
      maxHeight: across ? double.infinity : 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: across ? AppBorder(bottom: side) : AppBorder(left: side),
        ),
        child: ConstrainedBox(
          constraints: across
              ? const BoxConstraints.expand(height: 1)
              : const BoxConstraints.expand(width: 1),
        ),
      ),
    );
  }
}

/// [Divider] with its line on the screen's pixels: a rule centred in
/// [height] (the theme's divider space when null).
class AppDivider extends StatelessWidget {
  const AppDivider({
    this.height,
    this.indent = 0,
    this.endIndent = 0,
    this.color,
    super.key,
  });

  final double? height;
  final double indent;
  final double endIndent;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height ?? DividerTheme.of(context).space ?? 16,
    child: Center(
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: indent, end: endIndent),
        child: AppRule(color: color),
      ),
    ),
  );
}

/// [VerticalDivider] with its line on the screen's pixels.
class AppVerticalDivider extends StatelessWidget {
  const AppVerticalDivider({
    this.width,
    this.indent = 0,
    this.endIndent = 0,
    this.color,
    super.key,
  });

  final double? width;
  final double indent;
  final double endIndent;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width ?? DividerTheme.of(context).space ?? 16,
    child: Center(
      child: Padding(
        padding: EdgeInsets.only(top: indent, bottom: endIndent),
        child: AppRule(axis: Axis.vertical, color: color),
      ),
    ),
  );
}
