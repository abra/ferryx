import 'package:flutter/material.dart';

/// A go_router page shown as a modal dialog over the page below it, so a
/// route like `/settings` keeps push/pop semantics while the workspace stays
/// visible behind it. The barrier is the theme's (none on macOS, where a
/// sheet does not dim its window), and a click beside the dialog leaves it
/// open, as a window or a sheet stays until it is closed.
class DialogPage<T> extends Page<T> {
  const DialogPage({
    required this.builder,
    this.barrierDismissible = false,
    super.key,
    super.name,
  });

  final WidgetBuilder builder;

  /// A click on the scrim closes the dialog.
  final bool barrierDismissible;

  @override
  Route<T> createRoute(BuildContext context) => DialogRoute<T>(
    context: context,
    settings: this,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierColor: DialogTheme.of(context).barrierColor,
  );
}
