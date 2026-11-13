import 'package:material_ui/material_ui.dart';

import 'app_segmented_control.dart';
import 'app_tooltip.dart';
import 'hints/hint_registry.dart';
import 'theme/app_platform_style.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_radius.dart';
import 'theme/tokens/app_spacing.dart';

class AppPageTab<T> {
  const AppPageTab(this.value, this.label, {this.shortcut});

  final T value;
  final String label;

  /// Chord that opens the tab (`⌥2`), shown in its tooltip; empty or `null`
  /// shows none.
  final String? shortcut;
}

/// Switches the sections of a page (Home / Cards / Stats) the platform's
/// way: a segmented control on macOS and GNOME (NSSegmentedControl, the
/// inline view switcher), Fluent's selector bar with its accent pill on
/// Windows.
class AppPageTabs<T> extends StatelessWidget {
  const AppPageTabs({
    required this.tabs,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final List<AppPageTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    if (context.metrics.style != AppPlatformStyle.windows) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Align(
          alignment: Alignment.centerLeft,
          // Every segment carries its own ⌘J label.
          child: AppSegmentedControl<T>(
            options: [for (final tab in tabs) (tab.value, tab.label)],
            value: value,
            onChanged: onChanged,
          ),
        ),
      );
    }
    return Row(
      children: [
        for (final tab in tabs)
          _SelectorItem(
            label: tab.label,
            shortcut: tab.shortcut,
            selected: tab.value == value,
            onTap: () => onChanged(tab.value),
          ),
      ],
    );
  }
}

/// One item of Fluent's SelectorBar.
class _SelectorItem extends StatefulWidget {
  const _SelectorItem({
    required this.label,
    required this.shortcut,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? shortcut;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SelectorItem> createState() => _SelectorItemState();
}

class _SelectorItemState extends State<_SelectorItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final item = Container(
      height: context.metrics.controlHeight + 8,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: _hovered ? colors.hoverFill : null,
        borderRadius: BorderRadius.circular(context.metrics.radius.control),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            widget.label,
            style: context.text.bodyMedium?.copyWith(
              color: widget.selected
                  ? context.colors.onSurface
                  : colors.textMuted,
            ),
          ),
          if (widget.selected)
            Positioned(
              bottom: 2,
              child: Container(
                width: 16,
                height: 3,
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
        ],
      ),
    );
    final shortcut = widget.shortcut;
    return HintTarget(
      onActivate: widget.onTap,
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: widget.label,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: shortcut == null || shortcut.isEmpty
                ? item
                : AppTooltip(
                    message: widget.label,
                    shortcut: shortcut,
                    child: item,
                  ),
          ),
        ),
      ),
    );
  }
}
