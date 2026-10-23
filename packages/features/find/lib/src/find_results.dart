import 'dart:math' as math;

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shortcuts/shortcuts.dart';

import 'find_cubit.dart';

/// The hits so far under a status line: a row is a focusable item the
/// arrows walk; a click picks it, Return or a second click goes to it,
/// the menu key or a right click opens its menu.
class FindResults extends StatelessWidget {
  const FindResults({
    required this.state,
    required this.selected,
    this.focusRequest = 0,
    required this.onSelect,
    required this.onGoTo,
    required this.onMenu,
    super.key,
  });

  final FindState state;
  final int? selected;

  /// Raised by the dialog when the keys come down from a field: the
  /// [selected] hit takes the focus.
  final int focusRequest;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onGoTo;
  final void Function(int index, Rect anchor) onMenu;

  /// How tall the list is at most; a lower window shrinks it.
  static const double height = AppSizes.pickerListMaxHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Status(state: state),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: Container(
              decoration: appEdgedBox(
                color: context.colors.surface,
                edge: colors.line,
                radius: context.metrics.radius.tableFrame,
              ),
              clipBehavior: Clip.antiAlias,
              child: AppFocusArea(
                child: state.hits.isEmpty
                    ? _Empty(state: state)
                    : _Rows(
                        hits: state.hits,
                        selected: selected,
                        focusRequest: focusRequest,
                        onSelect: onSelect,
                        onGoTo: onGoTo,
                        onMenu: onMenu,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How many were found, and where the search is while it runs; the
/// core's word when it could not run.
class _Status extends StatelessWidget {
  const _Status({required this.state});

  final FindState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final error = state.error;
    final style = context.text.bodySmall?.copyWith(
      color: error != null ? colors.danger : colors.textMuted,
    );
    final String? summary;
    if (error != null) {
      summary = l10n.findError(error);
    } else if (state.capped) {
      summary = l10n.findResultsCapped(state.hits.length);
    } else if (state.running || state.done) {
      summary = l10n.findResults(state.hits.length);
    } else {
      summary = null;
    }
    final current = state.running ? state.current : null;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: AppIconSize.sm),
      child: Row(
        children: [
          if (state.running) ...[
            const AppSpinner(size: AppIconSize.sm),
            const SizedBox(width: AppSpacing.sm),
          ],
          if (summary != null)
            Flexible(
              child: Text(
                summary,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (current != null) ...[
            const SizedBox(width: AppSpacing.md),
            Flexible(
              child: Text(
                l10n.findScanning(current),
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.state});

  final FindState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!state.done || state.error != null) return const SizedBox.shrink();
    return Center(
      child: Text(
        l10n.findNoResults,
        style: context.text.bodyMedium?.copyWith(
          color: context.appColors.textMuted,
        ),
      ),
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({
    required this.hits,
    required this.selected,
    required this.focusRequest,
    required this.onSelect,
    required this.onGoTo,
    required this.onMenu,
  });

  final List<FindHit> hits;
  final int? selected;
  final int focusRequest;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onGoTo;
  final void Function(int index, Rect anchor) onMenu;

  /// A row's extent: the platform's list row, taller when the text is.
  static double extentOf(BuildContext context) {
    final style = context.text.bodyMedium!;
    final line =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
    return math.max(context.metrics.listRowHeight, line + 2 * AppSpacing.xs);
  }

  @override
  Widget build(BuildContext context) => CommandHandlers(
    handlers: {
      AppCommand.contextMenu: () {
        final index = selected;
        final anchor = _anchorOfSelected(context);
        if (index != null && anchor != null) onMenu(index, anchor);
      },
    },
    child: ListView.builder(
      itemExtent: extentOf(context),
      itemCount: hits.length,
      itemBuilder: (context, index) => _Row(
        key: ValueKey(hits[index].path),
        index: index,
        hit: hits[index],
        selected: index == selected,
        focusRequest: focusRequest,
        onSelect: onSelect,
        onGoTo: onGoTo,
        onMenu: onMenu,
      ),
    ),
  );

  /// The box of the selected row, for the menu the keys open.
  Rect? _anchorOfSelected(BuildContext context) {
    final key = _rowKeys[selected];
    final rowContext = key?.currentContext;
    return rowContext == null ? null : keyboardMenuAnchor(rowContext);
  }

  static final _rowKeys = <int, GlobalKey>{};
}

/// One hit: its icon and name, its folder (shortened in the middle, so
/// the end stays), its size and date in figures of one width. A click
/// picks it; a second click within the double-click time goes to it, and
/// the first one never waits for it.
class _Row extends StatefulWidget {
  const _Row({
    required this.index,
    required this.hit,
    required this.selected,
    required this.focusRequest,
    required this.onSelect,
    required this.onGoTo,
    required this.onMenu,
    super.key,
  });

  final int index;
  final FindHit hit;
  final bool selected;
  final int focusRequest;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onGoTo;
  final void Function(int index, Rect anchor) onMenu;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  final _anchor = GlobalKey();
  final _focus = FocusNode(debugLabel: 'find hit');
  bool _hovered = false;
  DateTime? _lastTap;

  @override
  void initState() {
    super.initState();
    _Rows._rowKeys[widget.index] = _anchor;
  }

  @override
  void didUpdateWidget(_Row oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && widget.focusRequest != oldWidget.focusRequest) {
      _focus.requestFocus();
    }
    if (oldWidget.index != widget.index) {
      if (_Rows._rowKeys[oldWidget.index] == _anchor) {
        _Rows._rowKeys.remove(oldWidget.index);
      }
      _Rows._rowKeys[widget.index] = _anchor;
    }
  }

  @override
  void dispose() {
    if (_Rows._rowKeys[widget.index] == _anchor) {
      _Rows._rowKeys.remove(widget.index);
    }
    _focus.dispose();
    super.dispose();
  }

  void _tap() {
    final now = DateTime.now();
    final last = _lastTap;
    if (last != null && now.difference(last) <= kDoubleTapTimeout) {
      _lastTap = null;
      widget.onGoTo(widget.index);
      return;
    }
    _lastTap = now;
    _focus.requestFocus();
    widget.onSelect(widget.index);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed) {
      widget.onGoTo(widget.index);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hit = widget.hit;
    final colors = context.appColors;
    final metrics = context.metrics;
    final emphasized = widget.selected && AppFocusArea.activeOf(context);
    final fill = widget.selected
        ? (emphasized ? colors.selectionAccent : colors.selectionMuted)
        : _hovered && metrics.navHover
        ? colors.hoverFill
        : null;
    final ink = emphasized ? colors.onAccent : context.colors.onSurface;
    final muted = emphasized ? colors.onAccentMuted : colors.textMuted;
    final detail = context.text.bodySmall?.copyWith(
      color: muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      onFocusChange: (focused) {
        if (focused) widget.onSelect(widget.index);
        setState(() {});
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
          onSecondaryTapUp: (details) =>
              widget.onMenu(widget.index, details.globalPosition & Size.zero),
          child: HintTarget(
            onActivate: () => widget.onGoTo(widget.index),
            child: Semantics(
              button: true,
              selected: widget.selected,
              label: hit.path,
              child: Container(
                key: _anchor,
                margin: EdgeInsets.symmetric(horizontal: metrics.tableRowInset),
                child: FocusRing(
                  focused: _focus.hasFocus,
                  radius: metrics.radius.tableRow,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(
                        metrics.radius.tableRow,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          hit.isDir ? AppIcons.folder : AppIcons.file,
                          size: AppIconSize.md,
                          color: emphasized
                              ? colors.onAccent
                              : colors.textMuted,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          flex: 5,
                          child: Text(
                            hit.name,
                            style: context.text.bodyMedium?.copyWith(
                              color: ink,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          flex: 6,
                          child: AppMiddleEllipsis(
                            hit.parentPath,
                            style: context.text.bodySmall!.copyWith(
                              color: muted,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          flex: 2,
                          child: Text(
                            hit.isDir ? '' : l10n.fileSize(hit.size),
                            style: detail,
                            textAlign: TextAlign.end,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          flex: 3,
                          child: Text(
                            hit.modified == null
                                ? ''
                                : l10n.dateTime(hit.modified!),
                            style: detail,
                            textAlign: TextAlign.end,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
