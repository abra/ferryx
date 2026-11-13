import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoScrollbar;
import 'package:material_ui/material_ui.dart';

import 'theme/app_platform_style.dart';
import 'theme/extensions/build_context_ext.dart';

/// An overlay scrollbar with the platform's scrolling and drag feedback.
class AppScrollbar extends StatelessWidget {
  const AppScrollbar({
    required this.child,
    this.controller,
    this.thumbVisibility,
    this.notificationPredicate = defaultScrollNotificationPredicate,
    this.scrollbarOrientation,
    super.key,
  });

  final Widget child;
  final ScrollController? controller;
  final bool? thumbVisibility;
  final ScrollNotificationPredicate notificationPredicate;
  final ScrollbarOrientation? scrollbarOrientation;

  @override
  Widget build(BuildContext context) {
    // Explicit scrollbars also cover lists using the app's automatic behavior.
    final content = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: child,
    );
    if (context.metrics.style == AppPlatformStyle.macos) {
      final theme = ScrollbarTheme.of(context);
      return CupertinoScrollbar(
        controller: controller,
        thumbVisibility: thumbVisibility,
        notificationPredicate: notificationPredicate,
        scrollbarOrientation: scrollbarOrientation,
        thickness:
            theme.thickness?.resolve({}) ?? CupertinoScrollbar.defaultThickness,
        thicknessWhileDragging:
            theme.thickness?.resolve({WidgetState.hovered}) ??
            CupertinoScrollbar.defaultThicknessWhileDragging,
        radius: theme.radius ?? CupertinoScrollbar.defaultRadius,
        radiusWhileDragging:
            theme.radius ?? CupertinoScrollbar.defaultRadiusWhileDragging,
        child: content,
      );
    }
    return Scrollbar(
      controller: controller,
      thumbVisibility: thumbVisibility,
      notificationPredicate: notificationPredicate,
      scrollbarOrientation: scrollbarOrientation,
      child: content,
    );
  }
}
