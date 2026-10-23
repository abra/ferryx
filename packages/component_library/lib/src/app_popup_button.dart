import 'package:flutter/material.dart';

import 'app_context_menu.dart';
import 'app_icons.dart';
import 'app_window_activity.dart';
import 'theme/app_button_styles.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_icon_size.dart';
import 'theme/tokens/app_spacing.dart';

/// A pop-up button: the current choice and a chevron, opening a menu of the
/// others with the current one checked and lit. The platform's own control (an
/// NSPopUpButton, a Fluent ComboBox, a GTK dropdown) drawn as the theme's
/// regular push button; on macOS 15 its chevrons sit in the accent's cap,
/// grey while the window is in the background or the button is off.
class AppPopupButton<T> extends StatelessWidget {
  const AppPopupButton({
    required this.value,
    required this.items,
    required this.onChanged,
    this.maxLabelWidth = 220,
    this.enabled = true,
    super.key,
  });

  final T value;

  /// Value and label pairs, in menu order.
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final double maxLabelWidth;

  /// Shows the choice greyed and opens nothing, while it cannot change.
  final bool enabled;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final picked = await showAppMenu<T>(
      context: context,
      anchor: box.localToGlobal(Offset.zero) & box.size,
      // Opens on the current choice, so ↑/↓ step from it.
      initialValue: value,
      entries: [
        for (final (option, label) in items)
          AppMenuAction(value: option, label: label, checked: option == value),
      ],
    );
    if (picked != null && picked != value) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final label = items.where((i) => i.$1 == value).firstOrNull?.$2 ?? '';
    final cap = context.metrics.popupCap;
    return Builder(
      builder: (context) => OutlinedButton(
        onPressed: enabled ? () => _open(context) : null,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppButtonStyles.labelRoom(context),
            // The cap stands 2 from the bezel's edge, the bare chevrons as
            // far as a label would.
            cap ? AppSpacing.xxs : AppSpacing.sm,
            AppButtonStyles.labelRoom(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxLabelWidth),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (cap)
              _PopupCap(lit: enabled && AppWindowActivity.of(context))
            else
              Icon(
                AppIcons.chevronsUpDown,
                size: AppIconSize.sm,
                color: context.appColors.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}

/// NSPopUpButton's cap on macOS 15: a 16-pt square of the accent, rounded,
/// with the chevrons in white; grey when [lit] is false.
class _PopupCap extends StatelessWidget {
  const _PopupCap({required this.lit});

  final bool lit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: AppIconSize.md,
      height: AppIconSize.md,
      decoration: BoxDecoration(
        color: lit ? colors.accent : colors.pressedFill,
        borderRadius: BorderRadius.circular(context.metrics.radius.chip),
      ),
      child: Icon(
        AppIcons.chevronsUpDown,
        size: AppIconSize.sm,
        color: lit ? colors.onAccent : colors.textMuted,
      ),
    );
  }
}
