import 'package:flutter/material.dart';

import 'app_context_menu.dart';
import 'app_icons.dart';
import 'theme/tokens/app_icon_size.dart';
import 'theme/tokens/app_spacing.dart';

/// A button that opens a menu of actions under itself: its [label], then a
/// chevron. Picking an action calls [onSelected]; Esc or a click outside
/// picks nothing. Unlike `AppPopupButton` it holds no choice: each pick is
/// something to do.
///
/// [style] sizes it like the buttons beside it (a large one in a row of
/// large buttons, `AppButtonStyles.small` on a list's row).
class AppMenuButton<T> extends StatelessWidget {
  const AppMenuButton({
    required this.label,
    required this.entries,
    required this.onSelected,
    this.style,
    this.enabled = true,
    super.key,
  });

  final String label;
  final List<AppMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;
  final ButtonStyle? style;

  /// Greyed, and opens nothing.
  final bool enabled;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final picked = await showAppMenu<T>(
      context: context,
      anchor: box.localToGlobal(Offset.zero) & box.size,
      entries: entries,
    );
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => OutlinedButton(
      onPressed: enabled ? () => _open(context) : null,
      style: style,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpacing.xs,
        children: [
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          // In the label's colour: the button may sit on a dark bar.
          const Icon(AppIcons.chevronDown, size: AppIconSize.sm),
        ],
      ),
    ),
  );
}
