import 'dart:math' as math;

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:shortcuts/shortcuts.dart';

import 'file_icon.dart';
import 'inline_rename.dart';
import 'panel_row.dart';
import 'panel_state.dart';
import 'recent_entries.dart';
import 'rows_list.dart';

/// Only cells in the viewport request decodes; the shared provider owns limits.
class RowsThumbnails extends StatefulWidget {
  const RowsThumbnails({
    required this.tab,
    required this.active,
    required this.callbacks,
    required this.rename,
    required this.onGeometry,
    this.provider,
    this.cursorKey,
    this.dropRow,
    super.key,
  });
  final PanelTabState tab;
  final bool active;
  final RowCallbacks callbacks;
  final RenameSpec rename;
  final ValueChanged<PanelGeometry> onGeometry;
  final ThumbnailProvider? provider;
  final GlobalKey? cursorKey;
  final String? dropRow;
  @override
  State<RowsThumbnails> createState() => _RowsThumbnailsState();
}

class _RowsThumbnailsState extends State<RowsThumbnails> {
  final _scroll = ScrollController();
  late final _follow = AppScrollReveal(_scroll);
  bool _jumpNextReveal = true;
  bool? _reduceMotion;
  (Size, double, int)? _layout;
  int _columns = 1, _page = 1;
  double _extent = 1;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_geometry);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = context.reduceMotion;
    if (reduced != _reduceMotion) {
      _reduceMotion = reduced;
      if (_follow.isAnimating) _follow.schedule(_reveal);
    }
  }

  void _geometry() {
    if (!mounted) return;
    widget.onGeometry(
      PanelGeometry(
        rowsPerPage: _page,
        columnsPerRow: _columns,
        firstVisibleRow: _scroll.hasClients
            ? (_scroll.offset / _extent).floor() * _columns
            : 0,
      ),
    );
  }

  @override
  void didUpdateWidget(RowsThumbnails oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        widget.tab.id != oldWidget.tab.id ||
        widget.tab.location != oldWidget.tab.location;
    _jumpNextReveal |= changed;
    if (changed ||
        widget.tab.cursor != oldWidget.tab.cursor ||
        widget.tab.scrollRequest != oldWidget.tab.scrollRequest) {
      _follow.schedule(_reveal);
    }
  }

  void _reveal() {
    if (!mounted || !_scroll.hasClients || widget.tab.cursor < 0) return;
    final top = (widget.tab.cursor ~/ _columns) * _extent;
    final bottom = top + _extent;
    _follow.reveal(
      start: top,
      end: bottom,
      alignment: widget.tab.scrollAlign.alignment,
      reduceMotion: context.reduceMotion,
      immediate: _jumpNextReveal,
    );
    _jumpNextReveal = false;
  }

  @override
  void dispose() {
    _follow.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final columns = math.max(
        1,
        (constraints.maxWidth / (AppSizes.thumbnailCellWidth * scale)).floor(),
      );
      final extent =
          AppSizes.thumbnailImageHeight +
          panelRowHeight(context) +
          2 * AppSpacing.sm;
      final layout = (constraints.biggest, extent, columns);
      if (layout != _layout) {
        _layout = layout;
        _jumpNextReveal = true;
        _follow.schedule(_reveal);
      }
      _columns = columns;
      _extent = extent;
      _page = math.max(1, (constraints.maxHeight / extent).floor()) * columns;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _geometry();
      });
      if (widget.tab.rows.isEmpty) {
        return EmptyRows(read: widget.tab.listing != null);
      }
      return NotificationListener<UserScrollNotification>(
        onNotification: _follow.onUserScroll,
        child: Scrollbar(
          controller: _scroll,
          child: GridView.builder(
            controller: _scroll,
            scrollCacheExtent: const ScrollCacheExtent.pixels(0),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: extent,
            ),
            itemCount: widget.tab.rows.length,
            itemBuilder: (context, index) {
              final entry = widget.tab.rows[index];
              final look = rowLookOf(
                widget.tab,
                index,
                active: widget.active && AppFocusArea.activeOf(context),
                dropRow: widget.dropRow,
                now: RecentEntriesClock.nowOf(context),
              );
              final renaming = widget.tab.renaming == index;
              return Semantics(
                selected: look.selected || look.cursor,
                button: true,
                label: rowSemanticsLabel(context, entry),
                child: HintTarget(
                  onActivate: () => widget.callbacks.onDoubleTap(index),
                  onActivateAlt: () => widget.callbacks.onTapDown(
                    index,
                    toggle: true,
                    range: false,
                  ),
                  child: RowDragArea(
                    index: index,
                    entry: entry,
                    location: widget.tab.location,
                    renaming: renaming,
                    drag: widget.callbacks.drag,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (_) => widget.callbacks.onTapDown(
                        index,
                        toggle: Chord.primaryHeld(Theme.of(context).platform),
                        range: HardwareKeyboard.instance.isShiftPressed,
                      ),
                      onDoubleTap: () => widget.callbacks.onDoubleTap(index),
                      onSecondaryTapDown: (details) => widget.callbacks
                          .onSecondaryTapDown(index, details.globalPosition),
                      child: Container(
                        key: index == widget.tab.cursor
                            ? widget.cursorKey
                            : ValueKey(entry.key),
                        margin: EdgeInsets.all(context.metrics.tableRowInset),
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        foregroundDecoration: renaming
                            ? null
                            : look.cursorDecoration(context.appColors),
                        decoration: BoxDecoration(
                          color: look.background(context.appColors),
                          borderRadius: BorderRadius.circular(
                            context.metrics.radius.tableRow,
                          ),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: _Thumbnail(
                                key: ValueKey(entry.key),
                                entry: entry,
                                location: widget.tab.locationOf(entry),
                                provider: widget.provider,
                              ),
                            ),
                            SizedBox(
                              height: panelRowHeight(context),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: renaming
                                        ? InlineRename(
                                            name: entry.name,
                                            caret: widget.rename.caret,
                                            shortcutMap:
                                                widget.rename.shortcutMap,
                                            onCommit:
                                                widget.callbacks.onRenameCommit,
                                            onCancel:
                                                widget.callbacks.onRenameCancel,
                                          )
                                        : AppMiddleEllipsis(
                                            entry.name,
                                            style: context.text.bodyMedium!
                                                .copyWith(
                                                  color: look.foreground(
                                                    context,
                                                  ),
                                                ),
                                          ),
                                  ),
                                  if (look.selected)
                                    Icon(
                                      AppIcons.check,
                                      size: AppIconSize.xs,
                                      color: look.checkMark(context.appColors),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

class _Thumbnail extends StatefulWidget {
  const _Thumbnail({
    required this.entry,
    required this.location,
    required this.provider,
    super.key,
  });
  final FileEntry entry;
  final Location location;
  final ThumbnailProvider? provider;
  @override
  State<_Thumbnail> createState() => _ThumbnailState();
}

class _ThumbnailState extends State<_Thumbnail> {
  ThumbnailLease? _lease;
  Uint8List? _bytes;
  Object? _requestKey;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _request();
  }

  @override
  void didUpdateWidget(_Thumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    _request();
  }

  void _request() {
    final width =
        (AppSizes.thumbnailImageHeight * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(64, 512);
    final key = (widget.provider, widget.location, widget.entry, width);
    if (key == _requestKey) return;
    _requestKey = key;
    _lease?.cancel();
    _bytes = null;
    final lease = widget.provider?.acquire(
      ThumbnailRequest(
        location: widget.location,
        entry: widget.entry,
        targetWidth: width,
      ),
    );
    _lease = lease;
    lease?.bytes.then((bytes) {
      if (mounted && identical(lease, _lease)) setState(() => _bytes = bytes);
    });
  }

  @override
  void dispose() {
    _lease?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _bytes != null
      ? Image.memory(
          _bytes!,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) =>
              FileIcon(widget.entry, size: AppIconSize.xl),
        )
      : FileIcon(widget.entry, size: AppIconSize.xl);
}
