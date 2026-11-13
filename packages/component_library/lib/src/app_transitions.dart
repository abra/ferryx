import 'package:material_ui/material_ui.dart';

import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_motion.dart';

/// The shared, short entrance/exit of a route or floating surface.
/// Heavy children are passed through unchanged on animation frames.
class AppSurfaceTransition extends StatelessWidget {
  const AppSurfaceTransition({
    required this.animation,
    required this.child,
    this.slide = true,
    super.key,
  });

  final Animation<double> animation;
  final Widget child;
  final bool slide;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return child;
    final progress = animation.drive(CurveTween(curve: AppMotion.curve));
    return AnimatedBuilder(
      animation: progress,
      child: child,
      builder: (context, child) {
        final closing = animation.status == AnimationStatus.reverse;
        return IgnorePointer(
          ignoring: closing,
          child: ExcludeFocus(
            excluding: closing,
            child: ExcludeSemantics(
              excluding: closing,
              child: Opacity(
                opacity: progress.value,
                child: Transform.translate(
                  offset: Offset(
                    0,
                    slide ? AppMotion.surfaceOffset * (1 - progress.value) : 0,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A modal route with the app's motion and the platform's dialog behavior.
class AppDialogRoute<T> extends DialogRoute<T> {
  AppDialogRoute({
    required super.context,
    required super.builder,
    super.settings,
    super.barrierDismissible = false,
  }) : _reverseDuration = context.motion(AppMotion.quick),
       super(
         themes: InheritedTheme.capture(
           from: context,
           to: Navigator.of(context, rootNavigator: true).context,
         ),
         barrierColor: DialogTheme.of(context).barrierColor,
         animationStyle: AnimationStyle(
           duration: context.motion(AppMotion.short),
         ),
       );

  final Duration _reverseDuration;

  @override
  Duration get reverseTransitionDuration => _reverseDuration;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => AppSurfaceTransition(animation: animation, child: child);
}

/// A full-window page that fades without sliding the window's chrome.
class AppPage<T> extends Page<T> {
  const AppPage({required this.child, super.key, super.name});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => _AppPageRoute<T>(
    page: this,
    transitionDuration: context.motion(AppMotion.short),
    reverseTransitionDuration: context.motion(AppMotion.quick),
  );
}

class _AppPageRoute<T> extends PageRoute<T> {
  _AppPageRoute({
    required AppPage<T> page,
    required this.transitionDuration,
    required this.reverseTransitionDuration,
  }) : super(settings: page);

  @override
  final Duration transitionDuration;
  @override
  final Duration reverseTransitionDuration;
  @override
  bool get maintainState => true;
  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Semantics(
    scopesRoute: true,
    explicitChildNodes: true,
    child: (settings as AppPage<T>).child,
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => AppSurfaceTransition(animation: animation, slide: false, child: child);
}
