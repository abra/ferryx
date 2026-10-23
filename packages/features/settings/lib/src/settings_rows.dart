import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';

/// A page of settings: its groups one under the other, one content margin
/// in from every edge and one apart (the window's scroll behaviour draws
/// the scrollbar).
class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.children, super.key});

  final List<Widget> children;

  /// The gap before [child]: a group's label pads itself above
  /// ([sectionLabelTopInset]), so a titled group stands as far from what
  /// is above it as an untitled one.
  static double _gapBefore(Widget child, double margin) =>
      child is SettingsGroup && child.title != null
      ? margin - sectionLabelTopInset
      : margin;

  @override
  Widget build(BuildContext context) {
    final margin = context.metrics.contentMargin;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        margin,
        children.isEmpty ? margin : _gapBefore(children.first, margin),
        margin,
        margin,
      ),
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: _gapBefore(children[i], margin)),
          children[i],
        ],
      ],
    );
  }
}

/// What [AppSectionLabel] pads above its text.
const double sectionLabelTopInset = AppSpacing.md;

/// A group of rows in one rounded box under a small heading, as the
/// grouped boxes of System Settings, a Fluent SettingsCard and an
/// AdwPreferencesGroup: a hairline between rows. [footer] goes under the
/// box (the buttons of a list).
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    required this.children,
    this.title,
    this.footer,
    super.key,
  });

  final String? title;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (title != null) AppSectionLabel(title!, inset: false),
      SettingsBox(children: children),
      if (footer != null) ...[const SizedBox(height: AppSpacing.sm), footer!],
    ],
  );
}

/// The rounded box of a [SettingsGroup]: rows with a hairline between.
class SettingsBox extends StatelessWidget {
  const SettingsBox({required this.children, super.key});

  final List<Widget> children;

  /// The box's fill: the surface, or in the dark a lighter fill than the
  /// window (the dark surface is darker than the window, a raised box is
  /// lighter).
  static Color fillOf(BuildContext context) =>
      context.isDark ? context.appColors.controlFill : context.colors.surface;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: appEdgedBox(
        color: fillOf(context),
        edge: colors.line,
        radius: context.metrics.radius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const AppDivider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: children[i],
            ),
          ],
        ],
      ),
    );
  }
}

/// A row of a group that holds a word instead of a control: a list with
/// nothing in it yet.
class SettingsPlaceholderRow extends StatelessWidget {
  const SettingsPlaceholderRow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minHeight: context.metrics.controlHeight),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: context.text.bodyMedium?.copyWith(
          color: context.appColors.textMuted,
        ),
      ),
    ),
  );
}

class ToggleRow extends StatelessWidget {
  const ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.note,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? note;

  @override
  Widget build(BuildContext context) => AppControlRow(
    label: label,
    note: note,
    control: AppToggle(value: value, onChanged: onChanged),
  );
}

class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.note,
    super.key,
  });

  final String label;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final String? note;

  @override
  Widget build(BuildContext context) => AppControlRow(
    label: label,
    note: note,
    control: AppPopupButton<T>(
      value: value,
      items: items,
      onChanged: onChanged,
    ),
  );
}

class SegmentRow<T> extends StatelessWidget {
  const SegmentRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.note,
    super.key,
  });

  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final String? note;

  @override
  Widget build(BuildContext context) => AppControlRow(
    label: label,
    note: note,
    control: AppSegmentedControl<T>(
      options: options,
      value: value,
      onChanged: onChanged,
    ),
  );
}

/// A label, the value the slider stands at, and the slider ending at the
/// control column's edge; the ring shows keyboard focus.
class SliderRow extends StatefulWidget {
  const SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
    super.key,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  State<SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<SliderRow> {
  final _focus = FocusNode(debugLabel: 'slider');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus != _focused) {
      setState(() => _focused = _focus.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) => AppControlRow(
    label: widget.label,
    control: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: AppSizes.settingsNumberFieldWidth,
          child: Text(
            widget.display,
            style: context.text.bodyMedium?.copyWith(
              color: context.appColors.textMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            textAlign: TextAlign.end,
            maxLines: 1,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        FocusRing(
          focused: _focused,
          radius: AppRadius.full,
          child: SizedBox(
            width: AppSizes.settingsSliderWidth,
            child: Slider(
              focusNode: _focus,
              value: widget.value.clamp(widget.min, widget.max),
              min: widget.min,
              max: widget.max,
              divisions: widget.divisions,
              label: widget.display,
              onChanged: widget.onChanged,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A labelled text field of a dialog.
class LabeledField extends StatelessWidget {
  const LabeledField({
    required this.label,
    required this.controller,
    this.hint,
    this.autofocus = false,
    this.monospace = false,
    this.trailing,
    this.onSubmitted,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool autofocus;
  final bool monospace;
  final Widget? trailing;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      autofocus: autofocus,
      style: monospace ? context.mono : null,
      decoration: InputDecoration(hintText: hint),
      onEditingComplete: () {},
      onSubmitted: onSubmitted,
    );
    return LabeledControl(
      label: label,
      child: trailing == null
          ? field
          : Row(
              children: [
                Expanded(child: field),
                SizedBox(width: context.metrics.toolbarSpacing),
                trailing!,
              ],
            ),
    );
  }
}

/// A control of a dialog under its label, laid out as [LabeledField] is,
/// so a form's labels line up.
class LabeledControl extends StatelessWidget {
  const LabeledControl({required this.label, required this.child, super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: context.text.labelMedium),
      const SizedBox(height: AppSpacing.xs),
      child,
    ],
  );
}

/// A row of a list the settings keep (an editor, a tool, a layout) inside
/// a [SettingsGroup]: its title and a word about it, with edit and remove
/// at the end.
class ListEntryRow extends StatelessWidget {
  const ListEntryRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.editTooltip,
    required this.removeTooltip,
    required this.onEdit,
    required this.onRemove,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String editTooltip;
  final String removeTooltip;
  final VoidCallback onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      spacing: context.metrics.toolbarSpacing,
      children: [
        Icon(icon, size: AppIconSize.md, color: colors.textMuted),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: context.text.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: context.text.bodySmall?.copyWith(
                    color: colors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        AppIconButton(
          icon: AppIcons.edit,
          tooltip: editTooltip,
          onPressed: onEdit,
        ),
        AppIconButton(
          icon: AppIcons.trash,
          tooltip: removeTooltip,
          onPressed: onRemove,
        ),
      ],
    );
  }
}
