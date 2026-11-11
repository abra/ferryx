import 'dart:async';
import 'dart:math' as math;

import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shortcuts/shortcuts.dart';

import 'file_diff.dart';
import 'file_diff_cubit.dart';
import 'viewer_source.dart';

/// Read-only comparison. Vertical positions are shared; each side keeps its
/// own horizontal position so long lines never hide the other document.
class FileDiffScreen extends StatefulWidget {
  const FileDiffScreen({
    required this.left,
    required this.right,
    required this.shortcutMap,
    required this.onClose,
    super.key,
  });
  final ViewerSource left, right;
  final ShortcutMap shortcutMap;
  final VoidCallback onClose;
  @override
  State<FileDiffScreen> createState() => _FileDiffScreenState();
}

class _FileDiffScreenState extends State<FileDiffScreen> {
  final _cubit = FileDiffCubit();
  final _focus = FocusNode(debugLabel: 'file comparison');
  final _left = ScrollController(), _right = ScrollController();
  bool _synchronizing = false;
  int _change = -1;
  double _rowHeight = 0;

  @override
  void initState() {
    super.initState();
    _left.addListener(() => _sync(_left, _right));
    _right.addListener(() => _sync(_right, _left));
    unawaited(_cubit.open(widget.left, widget.right));
  }

  void _sync(ScrollController from, ScrollController to) {
    if (_synchronizing || !from.hasClients || !to.hasClients) return;
    _synchronizing = true;
    try {
      to.jumpTo(from.offset.clamp(0, to.position.maxScrollExtent));
    } finally {
      _synchronizing = false;
    }
  }

  void _next(int direction) {
    final changes = _cubit.state.result?.changes;
    if (changes == null || changes.isEmpty) return;
    final index = _change < 0
        ? (direction > 0 ? 0 : changes.length - 1)
        : (_change + direction) % changes.length;
    setState(() => _change = index);
    if (_left.hasClients) {
      _left.jumpTo(
        (changes[index] * _rowHeight).clamp(0, _left.position.maxScrollExtent),
      );
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        !_left.hasClients) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed ||
        keys.isAltPressed ||
        keys.isControlPressed ||
        keys.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final position = _left.position;
    final offset = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => _left.offset + _rowHeight,
      LogicalKeyboardKey.arrowUp => _left.offset - _rowHeight,
      LogicalKeyboardKey.pageDown => _left.offset + position.viewportDimension,
      LogicalKeyboardKey.pageUp => _left.offset - position.viewportDimension,
      LogicalKeyboardKey.home => 0.0,
      LogicalKeyboardKey.end => position.maxScrollExtent,
      _ => null,
    };
    if (offset == null) return KeyEventResult.ignored;
    _left.jumpTo(offset.clamp(0, position.maxScrollExtent));
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _focus.dispose();
    _left.dispose();
    _right.dispose();
    unawaited(_cubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final decor = WindowDecor.of(context);
    final style = context.mono;
    final scaler = MediaQuery.textScalerOf(context);
    _rowHeight =
        (scaler.scale(style.fontSize!) * (style.height ?? 1.35) + AppSpacing.xs)
            .ceilToDouble();
    return CommandShortcuts(
      shortcuts: widget.shortcutMap.toShortcuts(
        context.platform,
        scopes: const {CommandScope.viewer, CommandScope.dialogs},
      ),
      child: CommandHandlers(
        handlers: {
          AppCommand.dismiss: widget.onClose,
          AppCommand.viewerFindNext: () => _next(1),
          AppCommand.viewerFindPrevious: () => _next(-1),
          AppCommand.viewerRefresh: () {
            _change = -1;
            unawaited(_cubit.open(widget.left, widget.right));
          },
        },
        child: Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          autofocus: true,
          child: Scaffold(
            backgroundColor: context.colors.surface,
            body: BlocConsumer<FileDiffCubit, FileDiffState>(
              bloc: _cubit,
              listenWhen: (before, after) => before.result != after.result,
              listener: (context, state) {
                if (state.result?.changes.isNotEmpty ?? false) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted &&
                        identical(_cubit.state.result, state.result)) {
                      _next(1);
                    }
                  });
                }
              },
              builder: (context, state) {
                final result = state.result;
                final hasChanges = result?.changes.isNotEmpty ?? false;
                return Column(
                  children: [
                    decor.dragArea(
                      Container(
                        height: context.metrics.topBarHeight,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: context.appColors.windowChrome,
                          border: AppBorder(
                            bottom: BorderSide(color: context.appColors.line),
                          ),
                        ),
                        child: AppTopBarRow(
                          leftInset: decor.leadingInset,
                          rightInset: decor.trailingInset,
                          title: Text(
                            l10n.diffTitle,
                            style: context.text.titleSmall,
                          ),
                          leading: [
                            AppIconButton(
                              icon: AppIcons.close,
                              tooltip: l10n.actionClose,
                              shortcut: widget.shortcutMap.labelOf(
                                AppCommand.dismiss,
                                context.platform,
                              ),
                              onPressed: widget.onClose,
                            ),
                          ],
                          trailing: [
                            AppIconButton(
                              icon: AppIcons.chevronUp,
                              tooltip: l10n.diffPrevious,
                              shortcut: widget.shortcutMap.labelOf(
                                AppCommand.viewerFindPrevious,
                                context.platform,
                              ),
                              onPressed: hasChanges ? () => _next(-1) : null,
                            ),
                            AppIconButton(
                              icon: AppIcons.chevronDown,
                              tooltip: l10n.diffNext,
                              shortcut: widget.shortcutMap.labelOf(
                                AppCommand.viewerFindNext,
                                context.platform,
                              ),
                              onPressed: hasChanges ? () => _next(1) : null,
                            ),
                            AppIconButton(
                              icon: AppIcons.refresh,
                              tooltip: l10n.cmdRefresh,
                              onPressed: state.loading
                                  ? null
                                  : () {
                                      _change = -1;
                                      unawaited(
                                        _cubit.open(widget.left, widget.right),
                                      );
                                    },
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(child: _DiffPath(source: widget.left)),
                        Expanded(child: _DiffPath(source: widget.right)),
                      ],
                    ),
                    Expanded(
                      child: state.loading
                          ? const Center(child: AppSpinner())
                          : state.error != null
                          ? AppErrorState(
                              title: l10n.errorMessage(state.error!),
                              onRetry: () => unawaited(
                                _cubit.open(widget.left, widget.right),
                              ),
                            )
                          : result == null
                          ? const SizedBox.shrink()
                          : result.failure != null
                          ? AppEmptyState(
                              icon: AppIcons.file,
                              title: result.failure == FileDiffFailure.tooLarge
                                  ? l10n.diffLimit(
                                      l10n.fileSize(FileDiff.maxBytes),
                                      FileDiff.maxLines,
                                    )
                                  : result.identicalBytes
                                  ? l10n.diffIdentical
                                  : l10n.diffBinary,
                            )
                          : SelectionArea(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _DiffColumn(
                                      result: result,
                                      left: true,
                                      scroll: _left,
                                      rowHeight: _rowHeight,
                                    ),
                                  ),
                                  AppRule(
                                    axis: Axis.vertical,
                                    color: context.appColors.line,
                                  ),
                                  Expanded(
                                    child: _DiffColumn(
                                      result: result,
                                      left: false,
                                      scroll: _right,
                                      rowHeight: _rowHeight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    AppStatusBar(
                      child: Text(
                        result == null
                            ? ''
                            : result.identicalBytes
                            ? l10n.diffIdentical
                            : result.failure != null
                            ? ''
                            : result.changes.isEmpty
                            ? l10n.diffLineEndings
                            : l10n.diffChangeCount(
                                _change + 1,
                                result.changes.length,
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DiffPath extends StatelessWidget {
  const _DiffPath({required this.source});
  final ViewerSource source;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.sm),
    child: AppTooltip(
      message:
          '${source.displayPath}${source.displayPath.endsWith('/') || source.displayPath.isEmpty ? '' : '/'}${source.displayName}',
      child: AppMiddleEllipsis(
        '${source.displayPath}${source.displayPath.endsWith('/') || source.displayPath.isEmpty ? '' : '/'}${source.displayName}',
        style: context.text.bodyMedium!,
      ),
    ),
  );
}

class _DiffColumn extends StatefulWidget {
  const _DiffColumn({
    required this.result,
    required this.left,
    required this.scroll,
    required this.rowHeight,
  });
  final FileDiff result;
  final bool left;
  final ScrollController scroll;
  final double rowHeight;
  @override
  State<_DiffColumn> createState() => _DiffColumnState();
}

class _DiffColumnState extends State<_DiffColumn> {
  final _horizontal = ScrollController();
  int _longest = 0;
  FileDiff? _measured;
  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_measured != widget.result) {
      _measured = widget.result;
      _longest = 0;
      for (final row in widget.result.rows) {
        final text = widget.left ? row.left : row.right;
        _longest = math.max(
          _longest,
          text?.replaceAll('\t', '    ').length ?? 0,
        );
      }
    }
    final style = context.mono.copyWith(color: context.colors.onSurface);
    final painter = TextPainter(
      text: TextSpan(text: 'M', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final character = painter.width;
    painter.dispose();
    final gutter = character * 7 + AppSpacing.sm * 2;
    return LayoutBuilder(
      builder: (context, constraints) => Scrollbar(
        controller: _horizontal,
        notificationPredicate: (notification) =>
            notification.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(
              constraints.maxWidth,
              gutter + _longest * character + AppSpacing.md,
            ),
            height: constraints.maxHeight,
            child: Scrollbar(
              controller: widget.scroll,
              child: ListView.builder(
                controller: widget.scroll,
                itemExtent: widget.rowHeight,
                itemCount: widget.result.rows.length,
                itemBuilder: (context, index) {
                  final row = widget.result.rows[index];
                  final text = widget.left ? row.left : row.right;
                  final number = widget.left ? row.leftNumber : row.rightNumber;
                  final colors = context.appColors;
                  return Container(
                    color: row.kind == FileDiffKind.equal || text == null
                        ? null
                        : widget.left
                        ? colors.wash(0)
                        : colors.wash(3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: gutter,
                          child: ExcludeSemantics(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                              ),
                              child: Text(
                                number?.toString() ?? '',
                                textAlign: TextAlign.right,
                                style: style.copyWith(color: colors.textMuted),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            text?.replaceAll('\t', '    ') ?? '',
                            style: style,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
