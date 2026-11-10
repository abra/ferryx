import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_text_field.dart';
import 'app_divider.dart';
import 'app_focus_area.dart';
import 'app_icons.dart';
import 'app_key_cap.dart';
import 'app_menu.dart';
import 'app_label_and_detail.dart';
import 'pixel_snap.dart';
import 'popup_focus.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/app_typography.dart';
import 'theme/tokens/app_icon_size.dart';
import 'theme/tokens/app_motion.dart';
import 'theme/tokens/app_sizes.dart';
import 'theme/tokens/app_spacing.dart';

/// What a pick asks for: the default (Return, a click), the second
/// (⌘Return or Ctrl+Return, a click with the key) or the third (⌥Return or
/// Alt+Return, a click with it).
enum AppQuickPickerAction { primary, secondary, alternate }

/// The row picked and how.
@immutable
class AppQuickPick<T> {
  const AppQuickPick(this.value, [this.action = AppQuickPickerAction.primary]);

  final T value;
  final AppQuickPickerAction action;

  @override
  bool operator ==(Object other) =>
      other is AppQuickPick<T> &&
      other.value == value &&
      other.action == action;

  @override
  int get hashCode => Object.hash(value, action);
}

/// A row of an [AppQuickPicker]: an item, or the caption of a group.
sealed class AppQuickPickerEntry<T> {
  const AppQuickPickerEntry();
}

/// The caption over a group of items, as tall as an item.
final class AppQuickPickerHeader<T> extends AppQuickPickerEntry<T> {
  const AppQuickPickerHeader(this.title);

  final String title;
}

/// One item: its label, with the parts that matched the query
/// ([labelHighlights], `[start, end)` ranges), a muted [detail] after it
/// (a section, a parent folder; shortened in the middle), an [icon]
/// before it and key caps at the end.
final class AppQuickPickerItem<T> extends AppQuickPickerEntry<T> {
  const AppQuickPickerItem({
    required this.value,
    required this.label,
    this.labelHighlights = const [],
    this.detail,
    this.detailHighlights = const [],
    this.icon,
    this.keys = const [],
    this.dimmed = false,
  });

  final T value;
  final String label;
  final List<(int, int)> labelHighlights;
  final String? detail;
  final List<(int, int)> detailHighlights;
  final IconData? icon;

  /// Key labels, each in a cap (a command's chords).
  final List<String> keys;

  /// Drawn faint: an item that may not work as hoped (gone from disk).
  final bool dimmed;
}

/// Opens [builder]'s picker as a command palette floats: near the top of
/// the window, over everything, without dimming it; a click beside it or
/// Esc closes it and the focus goes back where it was
/// ([pushReturningFocus]), before the caller acts on the answer.
Future<R?> showAppQuickPicker<R>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => pushReturningFocus(
  context,
  _QuickPickerRoute<R>(
    builder: builder,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    duration: context.motion(AppMotion.quick),
  ),
);

class _QuickPickerRoute<R> extends PopupRoute<R> {
  _QuickPickerRoute({
    required this.builder,
    required this.barrierLabel,
    required this.duration,
  });

  final WidgetBuilder builder;

  @override
  final String barrierLabel;
  final Duration duration;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => duration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Padding(
    // Below the window's top row, as a palette opens under a title bar.
    padding: EdgeInsets.fromLTRB(
      AppSpacing.lg,
      context.metrics.topBarHeight,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
    child: Align(
      alignment: Alignment.topCenter,
      // The plate on whole pixels, wherever the centring puts it.
      child: PixelSnap(
        child: FocusScope(autofocus: true, child: Builder(builder: builder)),
      ),
    ),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}

/// A search field over a list to pick from, as a command palette or a
/// "go to" box: the caller ranks [entries] for each query
/// ([onQueryChanged]) and the picker keeps the keys: ↑ ↓ (round the ends,
/// also ⌃P ⌃N), PageUp and PageDown, Home and End move the lit row;
/// Return picks it ([onPick]), with the primary key or ⌥ for the other
/// [actions]; Esc leaves ([onDismiss], else the route pops). Hovering
/// lights a row, a click picks it. The list builds the rows in view only,
/// every row (a caption too) one [rowExtentOf] high.
class AppQuickPicker<T> extends StatefulWidget {
  const AppQuickPicker({
    required this.entries,
    required this.hintText,
    required this.noResultsText,
    required this.onQueryChanged,
    required this.onPick,
    this.emptyText,
    this.title,
    this.hints = const [],
    this.actions = const {AppQuickPickerAction.primary},
    this.initialQuery = '',
    this.onDismiss,
    this.maxVisibleRows = 12,
    super.key,
  });

  /// The rows for the query typed, best first.
  final List<AppQuickPickerEntry<T>> entries;
  final String hintText;

  /// Shown when a query matches nothing.
  final String noResultsText;

  /// Shown when there is nothing to pick before anything is typed;
  /// [noResultsText] by default.
  final String? emptyText;

  /// A caption above the field: what the pick is for.
  final String? title;

  /// Key labels and what they do, in the footer.
  final List<(String, String)> hints;

  /// The actions a pick can ask for; another one falls back to the
  /// primary.
  final Set<AppQuickPickerAction> actions;
  final String initialQuery;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<AppQuickPick<T>> onPick;
  final VoidCallback? onDismiss;

  /// Rows in view before the list scrolls, as the window allows.
  final int maxVisibleRows;

  /// A row's height at the text size: the platform's sidebar row, taller
  /// as the text grows, room for a key cap.
  static double rowExtentOf(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final body = context.text.bodyMedium!;
    final cap = context.metrics.typeScale.keyCap;
    final text = scaler.scale(body.fontSize!) * (body.height ?? 1.2);
    // A key cap: its line, a point above and below, its edges (1 and 2).
    final keyCap = scaler.scale(cap.fontSize!) * (cap.height ?? 1.2) + 5;
    return math
        .max(
          context.metrics.navItemHeight,
          math.max(text, keyCap) + AppSpacing.sm,
        )
        .roundToDouble();
  }

  @override
  State<AppQuickPicker<T>> createState() => _AppQuickPickerState<T>();
}

class _AppQuickPickerState<T> extends State<AppQuickPicker<T>> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  late final _focus = FocusNode(debugLabel: 'quick picker', onKeyEvent: _onKey);
  final _scroll = ScrollController();

  /// The lit row: an index into the entries, always an item; -1 for none.
  int _selected = -1;

  /// The query the entries were last given for.
  late String _entriesQuery = widget.initialQuery;

  /// Space above the first row and below the last.
  static const _listPadding = AppSpacing.xs;

  @override
  void initState() {
    super.initState();
    _selected = _firstItem();
  }

  @override
  void didUpdateWidget(AppQuickPicker<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.entries, widget.entries)) return;
    // New results for a new query start at the top; the same query's keep
    // the lit item where it still is.
    final query = _controller.text;
    final kept = query == _entriesQuery
        ? _indexOfValue(_valueAt(oldWidget.entries, _selected))
        : -1;
    _entriesQuery = query;
    _selected = kept >= 0 ? kept : _firstItem();
    if (kept < 0 && _scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<AppQuickPickerEntry<T>> get _entries => widget.entries;

  static T? _valueAt<T>(List<AppQuickPickerEntry<T>> entries, int index) =>
      switch (index < 0 ? null : entries.elementAtOrNull(index)) {
        AppQuickPickerItem<T>(:final value) => value,
        _ => null,
      };

  int _indexOfValue(T? value) {
    if (value == null) return -1;
    return _entries.indexWhere(
      (e) => e is AppQuickPickerItem<T> && e.value == value,
    );
  }

  int _firstItem() => _entries.indexWhere((e) => e is AppQuickPickerItem<T>);

  int _lastItem() => _entries.lastIndexWhere((e) => e is AppQuickPickerItem<T>);

  /// The item [steps] items away (by items, captions skipped); round the
  /// ends with [wrap], else stopping at them.
  int _itemAfter(int from, int steps, {required bool wrap}) {
    final items = [
      for (var i = 0; i < _entries.length; i++)
        if (_entries[i] is AppQuickPickerItem<T>) i,
    ];
    if (items.isEmpty) return -1;
    final at = items.indexOf(from);
    if (at < 0) return steps >= 0 ? items.first : items.last;
    final target = at + steps;
    if (wrap) return items[target % items.length];
    return items[target.clamp(0, items.length - 1)];
  }

  void _select(int index) {
    if (index < 0 || index == _selected) return;
    setState(() => _selected = index);
    _reveal();
  }

  /// Scrolls the lit row into view the shortest way, its group's caption
  /// with it when it is the group's first.
  void _reveal() {
    if (!_scroll.hasClients || _selected < 0) return;
    final extent = AppQuickPicker.rowExtentOf(context);
    final position = _scroll.position;
    final captioned =
        _selected > 0 && _entries[_selected - 1] is AppQuickPickerHeader<T>;
    final first = captioned ? _selected - 1 : _selected;
    final top = first == 0 ? 0.0 : _listPadding + first * extent;
    final bottom = _selected == _entries.length - 1
        ? position.maxScrollExtent + position.viewportDimension
        : _listPadding + (_selected + 1) * extent;
    if (top < position.pixels) {
      position.jumpTo(top);
    } else if (bottom > position.pixels + position.viewportDimension) {
      position.jumpTo(
        (bottom - position.viewportDimension).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
    }
  }

  /// Rows a page moves by: those in view, less one kept for context.
  int get _page {
    if (!_scroll.hasClients) return 1;
    final rows =
        _scroll.position.viewportDimension /
        AppQuickPicker.rowExtentOf(context);
    return math.max(1, rows.floor() - 1);
  }

  AppQuickPickerAction _actionOf(HardwareKeyboard keyboard) {
    final primary = context.platform == TargetPlatform.macOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    final action = primary
        ? AppQuickPickerAction.secondary
        : keyboard.isAltPressed
        ? AppQuickPickerAction.alternate
        : AppQuickPickerAction.primary;
    return widget.actions.contains(action)
        ? action
        : AppQuickPickerAction.primary;
  }

  void _pick(int index, AppQuickPickerAction action) {
    if (index < 0) return;
    if (_entries.elementAtOrNull(index) case AppQuickPickerItem<T>(
      :final value,
    )) {
      widget.onPick(AppQuickPick(value, action));
    }
  }

  void _dismiss() {
    final dismiss = widget.onDismiss;
    if (dismiss != null) {
      dismiss();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final control = keyboard.isControlPressed;
    final plain =
        !keyboard.isShiftPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed &&
        !control;
    if (key == LogicalKeyboardKey.escape) {
      _dismiss();
    } else if (key == LogicalKeyboardKey.arrowDown ||
        (control && key == LogicalKeyboardKey.keyN)) {
      _select(_itemAfter(_selected, 1, wrap: true));
    } else if (key == LogicalKeyboardKey.arrowUp ||
        (control && key == LogicalKeyboardKey.keyP)) {
      _select(_itemAfter(_selected, -1, wrap: true));
    } else if (key == LogicalKeyboardKey.pageDown) {
      _select(_itemAfter(_selected, _page, wrap: false));
    } else if (key == LogicalKeyboardKey.pageUp) {
      _select(_itemAfter(_selected, -_page, wrap: false));
    } else if (key == LogicalKeyboardKey.home && plain) {
      _select(_firstItem());
    } else if (key == LogicalKeyboardKey.end && plain) {
      _select(_lastItem());
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) _pick(_selected, _actionOf(keyboard));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final extent = AppQuickPicker.rowExtentOf(context);
    final title = widget.title;
    final decoration = AppMenuPanel.plate(
      context,
      radius: context.metrics.radius.dialog,
    );
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: AppSizes.paletteWidth,
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: PixelSnap(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    0,
                  ),
                  child: Text(
                    title,
                    style: context.text.bodySmall
                        ?.weight(FontWeight.w600)
                        .copyWith(color: colors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Icon(
                      AppIcons.search,
                      size: AppIconSize.lg,
                      color: colors.textMuted,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: AppTextField(
                        controller: _controller,
                        focusNode: _focus,
                        autofocus: true,
                        // A palette's query reads a step above the body.
                        style: context.text.titleMedium!.weight(
                          FontWeight.w400,
                        ),
                        hintText: widget.hintText,
                        appearance: AppTextFieldAppearance.embedded,
                        onChanged: widget.onQueryChanged,
                      ),
                    ),
                  ],
                ),
              ),
              AppDivider(color: colors.line),
              // The list gives way first when the window is short.
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        extent * widget.maxVisibleRows + 2 * _listPadding,
                  ),
                  child: _entries.isEmpty
                      ? _NothingToPick(
                          text: _controller.text.trim().isEmpty
                              ? widget.emptyText ?? widget.noResultsText
                              : widget.noResultsText,
                        )
                      : ListView.builder(
                          controller: _scroll,
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                            vertical: _listPadding,
                          ),
                          itemExtent: extent,
                          itemCount: _entries.length,
                          itemBuilder: (context, index) =>
                              switch (_entries[index]) {
                                AppQuickPickerHeader<T>(:final title) =>
                                  _QuickPickerCaption(title),
                                final AppQuickPickerItem<T> item =>
                                  _QuickPickerRow<T>(
                                    item: item,
                                    selected: index == _selected,
                                    onHover: () => _select(index),
                                    onTap: () => _pick(
                                      index,
                                      _actionOf(HardwareKeyboard.instance),
                                    ),
                                  ),
                              },
                        ),
                ),
              ),
              if (widget.hints.isNotEmpty) AppMenuFooter(hints: widget.hints),
            ],
          ),
        ),
      ),
    );
  }
}

/// No row to show: what was typed matched nothing, or there is nothing
/// yet.
class _NothingToPick extends StatelessWidget {
  const _NothingToPick({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.xl,
    ),
    child: Text(
      text,
      style: context.text.bodyMedium?.copyWith(
        color: context.appColors.textMuted,
      ),
      textAlign: TextAlign.center,
    ),
  );
}

/// A group's caption, at the bottom of a row's height.
class _QuickPickerCaption extends StatelessWidget {
  const _QuickPickerCaption(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      context.metrics.rowInset + AppSpacing.sm,
      0,
      AppSpacing.lg,
      AppSpacing.xxs,
    ),
    child: Align(
      alignment: Alignment.bottomLeft,
      child: Text(
        title,
        style: context.text.labelSmall?.copyWith(
          color: context.appColors.textMuted,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}

class _QuickPickerRow<T> extends StatelessWidget {
  const _QuickPickerRow({
    required this.item,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });

  final AppQuickPickerItem<T> item;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = context.metrics;
    // Grey, as every selection, while the window is not the active one.
    final active = AppFocusArea.activeOf(context);
    final lit = selected && active;
    final ink = lit
        ? colors.onSelection
        : item.dimmed
        ? colors.textFaint
        : context.colors.onSurface;
    final secondary = lit ? colors.onSelectionMuted : colors.textMuted;
    final body = context.text.bodyMedium!.copyWith(color: ink);
    // What matched: heavier, and in the link colour off the accent.
    TextStyle matched(TextStyle style) =>
        style.copyWith(color: lit ? null : colors.link).weight(FontWeight.w700);
    final detailStyle = context.text.bodySmall!.copyWith(color: secondary);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      value: item.detail,
      excludeSemantics: true,
      child: MouseRegion(
        // Movement only: a list scrolled by the keys under a resting
        // pointer keeps the row the keys lit.
        onHover: (_) => onHover(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: metrics.rowInset),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              color: !selected
                  ? null
                  : active
                  ? colors.selectionAccent
                  : colors.selectionMuted,
              borderRadius: BorderRadius.circular(metrics.radius.row),
            ),
            child: Row(
              children: [
                if (item.icon != null) ...[
                  Icon(
                    item.icon,
                    size: AppIconSize.md,
                    color: lit ? colors.onSelection : colors.textMuted,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: AppLabelAndDetail(
                    label: item.label,
                    labelStyle: body,
                    labelHighlights: item.labelHighlights,
                    labelMatched: matched(body),
                    detail: item.detail,
                    detailStyle: detailStyle,
                    detailHighlights: item.detailHighlights,
                    detailMatched: matched(detailStyle),
                  ),
                ),
                if (item.keys.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.md),
                  AppKeyCaps(item.keys),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
