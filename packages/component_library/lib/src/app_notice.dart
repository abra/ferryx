import 'package:material_ui/material_ui.dart';

import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_motion.dart';

/// A short notice at the bottom of the window (an import done, a move with
/// its undo key, an error), in the platform's toast plate; a new one takes
/// the place of the one showing. Two lines at most.
///
/// The plate keeps its whole shadow: a [SnackBar] clips itself to its box
/// by default, which cut the shadow off at the plate's edges.
void showAppNotice(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
}) {
  ScaffoldMessenger.maybeOf(context)
    ?..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        clipBehavior: Clip.none,
        duration: duration,
        content: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
      snackBarAnimationStyle: AnimationStyle(
        duration: context.motion(AppMotion.short),
        reverseDuration: context.motion(AppMotion.quick),
      ),
    );
}
