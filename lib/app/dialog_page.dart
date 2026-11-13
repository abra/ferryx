import 'package:component_library/component_library.dart';
import 'package:material_ui/material_ui.dart';

/// A go_router page shown as a modal dialog over the page below it, so a
/// route like `/settings` keeps push/pop semantics while the workspace stays
/// visible behind it. The barrier and motion follow the app's theme. A click
/// beside the dialog leaves it open, as a window or sheet stays until closed.
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
  Route<T> createRoute(BuildContext context) => AppDialogRoute<T>(
    context: context,
    settings: this,
    builder: builder,
    barrierDismissible: barrierDismissible,
  );
}
