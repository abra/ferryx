import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

import 'document_format.dart';
import 'document_preview_screen.dart';
import 'hex_format.dart';
import 'line_layout.dart';
import 'markdown_format.dart';
import 'markdown_preview.dart';
import 'text_preview_format.dart';
import 'text_preview_data.dart';
import 'rich_text_preview.dart';
import 'delimited_preview.dart';
import 'text_window.dart';
import 'viewer_cubit.dart';
import 'viewer_footer.dart';
import 'viewer_source.dart';
import 'viewer_state.dart';
import 'viewer_views.dart';

/// One file in the workspace or a route. Keep its key stable when moving
/// between placements so the reader, scroll position and decoder survive.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({
    required this.files,
    required this.preferences,
    required this.shortcutMap,
    required this.windowDecor,
    required this.location,
    required this.onClose,
    this.startInPreview = false,
    this.autofocus = true,
    this.focusScope,
    this.fullWindow = true,
    this.onToggleFullWindow,
    this.onFocusFiles,
    super.key,
  });

  final FileRepository files;
  final PreferencesService preferences;
  final ShortcutMap shortcutMap;
  final WindowDecor windowDecor;
  final Location location;

  /// Prefer rendered content when supported; ordinary files open as text.
  final bool startInPreview;
  final bool autofocus;
  final FocusScopeNode? focusScope;
  final bool fullWindow;
  final VoidCallback? onToggleFullWindow;
  final VoidCallback? onFocusFiles;
  final VoidCallback onClose;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late final ViewerCubit _cubit;
  final _contentFocus = FocusNode(debugLabel: 'viewer content');
  final _documentFocus = FocusNode(debugLabel: 'viewer document');
  FocusScopeNode? _ownedScope;
  FocusScopeNode get _scope =>
      widget.focusScope ??
      (_ownedScope ??= FocusScopeNode(debugLabel: 'viewer'));
  final _findFocus = FocusNode(debugLabel: 'viewer find');
  final _findController = TextEditingController();
  final _scroll = ScrollController();
  LineLayout? _layout;
  int _topLine = 0;

  @override
  void initState() {
    super.initState();
    _cubit = ViewerCubit(
      source: FileRepositorySource(widget.files, widget.location),
      wrap: widget.preferences.current.viewerWrap,
      mode:
          isDocumentName(widget.location.name) ||
              textPreviewFormatOf(widget.location.name) != null ||
              widget.startInPreview && isImageName(widget.location.name)
          ? ViewerMode.preview
          : ViewerMode.text,
    );
    unawaited(_cubit.load());
    _scroll.addListener(_onScrolled);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.autofocus) _focusContent();
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScrolled);
    _scroll.dispose();
    _findController.dispose();
    _findFocus.dispose();
    _contentFocus.dispose();
    _documentFocus.dispose();
    _ownedScope?.dispose();
    _cubit.close();
    super.dispose();
  }

  void _focusContent() {
    final document =
        _cubit.state.mode == ViewerMode.preview &&
        isDocumentName(widget.location.name);
    (document ? _documentFocus : _contentFocus).requestFocus();
  }

  void _onScopeFocus(bool focused) {
    if (focused && _scope.hasPrimaryFocus) _focusContent();
  }

  void _changeDocumentFontSize(double size) => unawaited(
    widget.preferences.update((p) => p.copyWith(documentFontSize: size)),
  );

  // ─── Scrolling ───

  void _onScrolled() {
    if (_cubit.state.mode == ViewerMode.preview) return;
    final layout = _layout;
    if (layout == null || !_scroll.hasClients) return;
    final line = layout.lineAtOffset(_scroll.offset);
    if (line != _topLine) setState(() => _topLine = line);
  }

  void _onLayout(LineLayout layout) => _layout = layout;

  /// Scrolls to what the state asks for, once the frame is laid out.
  void _scrollTo(ViewerState state) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      switch (state.scroll) {
        case ViewerScroll.top:
          _scroll.jumpTo(0);
        case ViewerScroll.bottom:
          _scroll.jumpTo(position.maxScrollExtent);
        case ViewerScroll.match:
          final layout = _layout;
          final match = state.current;
          if (layout == null || match == null) return;
          final top = layout.offsetOfLine(match.line);
          final bottom = top + layout.heightOfLine(match.line);
          if (top < position.pixels ||
              bottom > position.pixels + position.viewportDimension) {
            final centred =
                top - (position.viewportDimension - layout.lineHeight) / 2;
            _scroll.jumpTo(centred.clamp(0, position.maxScrollExtent));
          }
      }
      _onScrolled();
    });
  }

  /// At the window's end the next part loads, at its start the previous;
  /// otherwise the keys scroll as anywhere.
  KeyEventResult _onContentKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final state = _cubit.state;
    if (state.mode == ViewerMode.preview || !_scroll.hasClients) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final position = _scroll.position;
    final atEnd = position.pixels >= position.maxScrollExtent - 0.5;
    final atStart = position.pixels <= position.minScrollExtent + 0.5;
    final down =
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.arrowDown;
    final up =
        key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.arrowUp;
    if (down && atEnd && state.hasNext) {
      unawaited(_cubit.loadNext());
      return KeyEventResult.handled;
    }
    if (up && atStart && state.hasPrevious) {
      unawaited(_cubit.loadPrevious());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end && atEnd && state.hasNext) {
      unawaited(_cubit.loadLast());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home && atStart && state.hasPrevious) {
      unawaited(_cubit.load());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ─── Commands ───

  Map<AppCommand, VoidCallback> _handlers() => {
    AppCommand.viewerText: () => _setMode(ViewerMode.text),
    AppCommand.viewerHex: () => _setMode(ViewerMode.hex),
    AppCommand.viewerPreview: () => _setMode(ViewerMode.preview),
    AppCommand.viewerGoTo: () => unawaited(_goTo()),
    AppCommand.viewerRefresh: () => unawaited(_cubit.refresh()),
    AppCommand.viewerFind: _showFind,
    AppCommand.viewerFindNext: () => _find(1),
    AppCommand.viewerFindPrevious: () => _find(-1),
    AppCommand.viewerToggleWrap: _toggleWrap,
    AppCommand.confirm: () {
      if (_findFocus.hasFocus) _find(1);
    },
    AppCommand.dismiss: _dismiss,
    AppCommand.viewerToggleFullWindow: ?widget.onToggleFullWindow,
    AppCommand.switchPanel: ?widget.onFocusFiles,
  };

  void _setMode(ViewerMode mode) {
    _cubit.setMode(mode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusContent();
    });
  }

  void _toggleWrap() {
    _cubit.toggleWrap();
    unawaited(
      widget.preferences.update(
        (p) => p.copyWith(viewerWrap: _cubit.state.wrap),
      ),
    );
  }

  void _showFind() {
    if (_cubit.state.mode == ViewerMode.preview) return;
    _cubit.showFind();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      focusWithSelection(
        _findFocus,
        TextSelection(baseOffset: 0, extentOffset: _findController.text.length),
      );
    });
  }

  void _hideFind() {
    _findController.clear();
    _cubit.hideFind();
    _contentFocus.requestFocus();
  }

  void _find(int delta) {
    final state = _cubit.state;
    if (!state.findShown) {
      _showFind();
      return;
    }
    if (state.matches.isEmpty) {
      if (state.findQuery.isNotEmpty) {
        showAppNotice(context, context.l10n.viewerNoMatch);
      }
      return;
    }
    if (delta > 0) {
      _cubit.findNext();
    } else {
      _cubit.findPrevious();
    }
  }

  void _dismiss() {
    if (_cubit.state.findShown) {
      _hideFind();
      return;
    }
    widget.onClose();
  }

  Future<void> _goTo() async {
    if (_cubit.state.mode == ViewerMode.preview) return;
    final l10n = context.l10n;
    final answer = await AppDialog.prompt(
      context,
      title: l10n.viewerGoToTitle,
      confirmLabel: l10n.actionGo,
      cancelLabel: l10n.actionCancel,
      initialValue: '',
    );
    if (answer == null || !mounted) return;
    final offset = parseGoTo(answer, _cubit.state.size);
    if (offset < 0) {
      showAppNotice(context, l10n.viewerGoToHint);
      return;
    }
    await _cubit.goTo(offset);
    _contentFocus.requestFocus();
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    return FocusScope(
      node: _scope,
      onFocusChange: _onScopeFocus,
      child: Scaffold(
        backgroundColor: context.appColors.window,
        body: BlocProvider.value(
          value: _cubit,
          child: BlocListener<ViewerCubit, ViewerState>(
            listenWhen: (before, after) =>
                before.scrollRequest != after.scrollRequest,
            listener: (context, state) => _scrollTo(state),
            child: CommandShortcuts(
              shortcuts: {
                ...widget.shortcutMap.toShortcuts(
                  platform,
                  scopes: const {CommandScope.viewer, CommandScope.dialogs},
                ),
                if (widget.onFocusFiles != null)
                  for (final chord in widget.shortcutMap.chordsFor(
                    AppCommand.switchPanel,
                  ))
                    chord.toShortcutActivator(platform): const CommandIntent(
                      AppCommand.switchPanel,
                    ),
              },
              child: CommandHandlers(
                handlers: _handlers(),
                child: PreferenceBuilder<(double, double)>(
                  service: widget.preferences,
                  select: (p) => (p.viewerFontSize, p.documentFontSize),
                  builder: (context, sizes) =>
                      BlocBuilder<ViewerCubit, ViewerState>(
                        builder: (context, state) => _Frame(
                          state: state,
                          source: _cubit.source,
                          decor: widget.windowDecor,
                          shortcutMap: widget.shortcutMap,
                          fontSize: sizes.$1,
                          documentFontSize: sizes.$2,
                          onDocumentFontSizeChanged: _changeDocumentFontSize,
                          documentFocus: _documentFocus,
                          autofocus: widget.autofocus,
                          fullWindow: widget.fullWindow,
                          onToggleFullWindow: widget.onToggleFullWindow,
                          onFocusFiles: widget.onFocusFiles,
                          topLine: _topLine,
                          contentFocus: _contentFocus,
                          findFocus: _findFocus,
                          findController: _findController,
                          scroll: _scroll,
                          onLayout: _onLayout,
                          onContentKey: _onContentKey,
                          onFocusContent: _focusContent,
                          onMode: _setMode,
                          onToggleWrap: _toggleWrap,
                          onFind: _showFind,
                          onFindChanged: _cubit.setFindQuery,
                          onFindNext: () => _find(1),
                          onFindPrevious: () => _find(-1),
                          onFindClose: _hideFind,
                          onGoTo: () => unawaited(_goTo()),
                          onRefresh: () => unawaited(_cubit.refresh()),
                          onLoadNext: () => unawaited(_cubit.loadNext()),
                          onLoadPrevious: () =>
                              unawaited(_cubit.loadPrevious()),
                          onClose: widget.onClose,
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

/// The window: the top row, the find bar, the content on the surface,
/// the status bar.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.state,
    required this.source,
    required this.decor,
    required this.shortcutMap,
    required this.fontSize,
    required this.documentFontSize,
    required this.onDocumentFontSizeChanged,
    required this.documentFocus,
    required this.autofocus,
    required this.topLine,
    required this.onFocusFiles,
    required this.contentFocus,
    required this.findFocus,
    required this.findController,
    required this.scroll,
    required this.onLayout,
    required this.onContentKey,
    required this.onFocusContent,
    required this.onMode,
    required this.onToggleWrap,
    required this.onFind,
    required this.onFindChanged,
    required this.onFindNext,
    required this.onFindPrevious,
    required this.onFindClose,
    required this.onGoTo,
    required this.onRefresh,
    required this.onLoadNext,
    required this.onLoadPrevious,
    required this.onClose,
    required this.fullWindow,
    required this.onToggleFullWindow,
  });

  final ViewerState state;
  final ViewerSource source;
  final WindowDecor decor;
  final ShortcutMap shortcutMap;
  final double fontSize;
  final double documentFontSize;
  final ValueChanged<double> onDocumentFontSizeChanged;
  final FocusNode documentFocus;
  final bool autofocus;
  final int topLine;
  final VoidCallback? onFocusFiles;
  final FocusNode contentFocus;
  final FocusNode findFocus;
  final TextEditingController findController;
  final ScrollController scroll;
  final ValueChanged<LineLayout> onLayout;
  final KeyEventResult Function(FocusNode node, KeyEvent event) onContentKey;
  final VoidCallback onFocusContent;
  final ValueChanged<ViewerMode> onMode;
  final VoidCallback onToggleWrap;
  final VoidCallback onFind;
  final ValueChanged<String> onFindChanged;
  final VoidCallback onFindNext;
  final VoidCallback onFindPrevious;
  final VoidCallback onFindClose;
  final VoidCallback onGoTo;
  final VoidCallback onRefresh;
  final VoidCallback onLoadNext;
  final VoidCallback onLoadPrevious;
  final VoidCallback onClose;
  final bool fullWindow;
  final VoidCallback? onToggleFullWindow;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    String? chord(AppCommand command) => shortcutMap.labelOf(command, platform);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopRow(
          state: state,
          source: source,
          decor: decor,
          chord: chord,
          onMode: onMode,
          onToggleWrap: onToggleWrap,
          onFind: onFind,
          onGoTo: onGoTo,
          onRefresh: onRefresh,
          onClose: onClose,
          fullWindow: fullWindow,
          onToggleFullWindow: onToggleFullWindow,
        ),
        if (state.findShown)
          _FindBar(
            state: state,
            controller: findController,
            focusNode: findFocus,
            chord: chord,
            onChanged: onFindChanged,
            onNext: onFindNext,
            onPrevious: onFindPrevious,
            onClose: onFindClose,
          ),
        Expanded(
          child: ColoredBox(
            color: context.colors.surface,
            child: Listener(
              onPointerDown: (_) => onFocusContent(),
              child: AppFocusArea(
                child: AppScrollKeys(
                  child: Focus(
                    focusNode: contentFocus,
                    onKeyEvent: onContentKey,
                    child: _Content(
                      state: state,
                      source: source,
                      shortcutMap: shortcutMap,
                      fontSize: fontSize,
                      documentFontSize: documentFontSize,
                      onDocumentFontSizeChanged: onDocumentFontSizeChanged,
                      documentFocus: documentFocus,
                      autofocus: autofocus,
                      scroll: scroll,
                      onLayout: onLayout,
                      onLoadNext: onLoadNext,
                      onLoadPrevious: onLoadPrevious,
                      onShowSource: () => onMode(ViewerMode.text),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        _StatusBar(
          state: state,
          topLine: topLine,
          document: isDocumentName(source.displayName),
          shortcutMap: shortcutMap,
          showFiles: onFocusFiles != null,
        ),
      ],
    );
  }
}

/// The window's top row: the file, the mode, the tools, close.
class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.state,
    required this.source,
    required this.decor,
    required this.chord,
    required this.onMode,
    required this.onToggleWrap,
    required this.onFind,
    required this.onGoTo,
    required this.onRefresh,
    required this.onClose,
    required this.fullWindow,
    required this.onToggleFullWindow,
  });

  final ViewerState state;
  final ViewerSource source;
  final WindowDecor decor;

  /// A command's key as a label, for the tooltips.
  final String? Function(AppCommand command) chord;
  final ValueChanged<ViewerMode> onMode;
  final VoidCallback onToggleWrap;
  final VoidCallback onFind;
  final VoidCallback onGoTo;
  final VoidCallback onRefresh;
  final VoidCallback onClose;
  final bool fullWindow;
  final VoidCallback? onToggleFullWindow;

  Future<void> _menu(BuildContext context, Rect anchor) async {
    final l10n = context.l10n;
    final picked = await showAppMenu<AppCommand>(
      context: context,
      anchor: anchor,
      entries: [
        for (final (mode, command) in [
          (ViewerMode.text, AppCommand.viewerText),
          (ViewerMode.hex, AppCommand.viewerHex),
          (ViewerMode.preview, AppCommand.viewerPreview),
        ])
          AppMenuAction(
            value: command,
            label: l10n.commandLabel(command),
            shortcut: chord(command),
            checked: state.mode == mode,
          ),
        if (onToggleFullWindow != null)
          AppMenuAction(
            value: AppCommand.viewerToggleFullWindow,
            label: fullWindow ? l10n.viewerAdjacent : l10n.viewerExpand,
            icon: fullWindow ? AppIcons.dualPane : AppIcons.fillWindow,
            shortcut: chord(AppCommand.viewerToggleFullWindow),
          ),
        const AppMenuSeparator(),
        AppMenuAction(
          value: AppCommand.viewerToggleWrap,
          label: l10n.cmdViewerToggleWrap,
          shortcut: chord(AppCommand.viewerToggleWrap),
          checked: state.wrap,
          enabled: state.mode == ViewerMode.text,
        ),
        AppMenuAction(
          value: AppCommand.viewerFind,
          label: l10n.cmdViewerFind,
          icon: AppIcons.search,
          shortcut: chord(AppCommand.viewerFind),
          enabled: state.mode != ViewerMode.preview,
        ),
        AppMenuAction(
          value: AppCommand.viewerGoTo,
          label: l10n.cmdViewerGoTo,
          icon: AppIcons.goTo,
          shortcut: chord(AppCommand.viewerGoTo),
          enabled: state.mode != ViewerMode.preview,
        ),
        AppMenuAction(
          value: AppCommand.viewerRefresh,
          label: l10n.cmdRefresh,
          icon: AppIcons.refresh,
          shortcut: chord(AppCommand.viewerRefresh),
        ),
      ],
    );
    if (!context.mounted) return;
    switch (picked) {
      case AppCommand.viewerToggleFullWindow:
        onToggleFullWindow?.call();
      case AppCommand.viewerText:
        onMode(ViewerMode.text);
      case AppCommand.viewerHex:
        onMode(ViewerMode.hex);
      case AppCommand.viewerPreview:
        onMode(ViewerMode.preview);
      case AppCommand.viewerToggleWrap:
        onToggleWrap();
      case AppCommand.viewerFind:
        onFind();
      case AppCommand.viewerGoTo:
        onGoTo();
      case AppCommand.viewerRefresh:
        onRefresh();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final metrics = context.metrics;
    final text = state.mode == ViewerMode.text;
    final modes = AppSegmentedControl<ViewerMode>(
      options: [
        (ViewerMode.text, l10n.viewerModeText),
        (ViewerMode.hex, l10n.viewerModeHex),
        (ViewerMode.preview, l10n.viewerModePreview),
      ],
      value: state.mode,
      onChanged: onMode,
    );
    final row = Container(
      height: metrics.topBarHeight,
      decoration: BoxDecoration(
        color: colors.windowChrome,
        border: AppBorder(bottom: BorderSide(color: colors.line)),
      ),
      padding: const EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.sm,
      ),
      child: AppTopBarRow(
        leftInset: decor.leadingInset,
        rightInset: decor.trailingInset,
        title: _FileTitle(name: source.displayName, path: source.displayPath),
        forms: [
          [
            modes,
            AppIconButton(
              icon: AppIcons.wrap,
              tooltip: l10n.viewerWrap,
              shortcut: chord(AppCommand.viewerToggleWrap),
              selected: state.wrap && text,
              onPressed: text ? onToggleWrap : null,
            ),
            AppIconButton(
              icon: AppIcons.search,
              tooltip: l10n.cmdViewerFind,
              shortcut: chord(AppCommand.viewerFind),
              selected: state.findShown,
              onPressed: state.mode == ViewerMode.preview ? null : onFind,
            ),
            AppIconButton(
              icon: AppIcons.goTo,
              tooltip: l10n.cmdViewerGoTo,
              shortcut: chord(AppCommand.viewerGoTo),
              onPressed: state.mode == ViewerMode.preview ? null : onGoTo,
            ),
            AppIconButton(
              icon: AppIcons.refresh,
              tooltip: l10n.cmdRefresh,
              shortcut: chord(AppCommand.viewerRefresh),
              onPressed: onRefresh,
            ),
          ],
          [modes],
        ],
        trailing: [
          if (onToggleFullWindow != null)
            AppIconButton(
              icon: fullWindow ? AppIcons.dualPane : AppIcons.fillWindow,
              tooltip: fullWindow ? l10n.viewerAdjacent : l10n.viewerExpand,
              shortcut: chord(AppCommand.viewerToggleFullWindow),
              onPressed: onToggleFullWindow,
            ),
          Builder(
            builder: (context) => AppIconButton(
              icon: AppIcons.more,
              tooltip: l10n.viewerActions,
              onPressed: () => unawaited(
                _menu(context, keyboardMenuAnchor(context)),
              ),
            ),
          ),
          AppIconButton(
            icon: AppIcons.close,
            tooltip: l10n.actionClose,
            shortcut: chord(AppCommand.dismiss),
            onPressed: onClose,
          ),
        ],
      ),
    );
    return decor.dragArea(row);
  }
}

/// The file's name with its folder under it, in the top row.
class _FileTitle extends StatelessWidget {
  const _FileTitle({required this.name, required this.path});

  final String name;
  final String path;

  @override
  Widget build(BuildContext context) {
    final title = context.text.titleSmall!;
    final detail = context.text.bodySmall!.copyWith(
      color: context.appColors.textMuted,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final twoLines =
        scaler.scale(title.fontSize!) * title.height! +
        scaler.scale(detail.fontSize!) * detail.height!;
    return AppTooltip(
      message: path.isEmpty ? name : path,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // Keep the bar aligned with the file panel at large text sizes.
            if (path.isNotEmpty && twoLines <= constraints.maxHeight)
              AppMiddleEllipsis(path, style: detail),
          ],
        ),
      ),
    );
  }
}

/// The find bar under the top row: the query, the count, next and
/// previous, close.
class _FindBar extends StatelessWidget {
  const _FindBar({
    required this.state,
    required this.controller,
    required this.focusNode,
    required this.chord,
    required this.onChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
  });

  final ViewerState state;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? Function(AppCommand command) chord;
  final ValueChanged<String> onChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final metrics = context.metrics;
    final count = state.matches.length;
    final current = count == 0 ? 0 : state.currentMatch + 1;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: AppBorder(bottom: BorderSide(color: colors.line)),
      ),
      child: Row(
        spacing: metrics.toolbarSpacing,
        children: [
          SizedBox(
            width: AppSizes.titleBarSearchWidth,
            child: AppSearchField(
              hintText: l10n.viewerFindHint,
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
            ),
          ),
          Text(
            state.findQuery.isEmpty
                ? ''
                : count == 0
                ? l10n.viewerNoMatch
                : l10n.viewerMatches(current, count),
            style: context.text.bodySmall?.copyWith(
              color: count == 0 && state.findQuery.isNotEmpty
                  ? colors.danger
                  : colors.textMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          AppIconButton(
            icon: AppIcons.chevronUp,
            tooltip: l10n.cmdViewerFindPrevious,
            shortcut: chord(AppCommand.viewerFindPrevious),
            onPressed: count == 0 ? null : onPrevious,
          ),
          AppIconButton(
            icon: AppIcons.chevronDown,
            tooltip: l10n.cmdViewerFindNext,
            shortcut: chord(AppCommand.viewerFindNext),
            onPressed: count == 0 ? null : onNext,
          ),
          AppIconButton(
            icon: AppIcons.close,
            tooltip: l10n.actionClose,
            shortcut: chord(AppCommand.dismiss),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// The content by mode, with a spinner while a long read goes on and a
/// word when it fails.
class _Content extends StatelessWidget {
  const _Content({
    required this.state,
    required this.source,
    required this.shortcutMap,
    required this.fontSize,
    required this.documentFontSize,
    required this.onDocumentFontSizeChanged,
    required this.documentFocus,
    required this.autofocus,
    required this.scroll,
    required this.onLayout,
    required this.onLoadNext,
    required this.onLoadPrevious,
    required this.onShowSource,
  });

  final ViewerState state;
  final ViewerSource source;
  final ShortcutMap shortcutMap;
  final double fontSize;
  final double documentFontSize;
  final ValueChanged<double> onDocumentFontSizeChanged;
  final FocusNode documentFocus;
  final bool autofocus;
  final ScrollController scroll;
  final ValueChanged<LineLayout> onLayout;
  final VoidCallback onLoadNext;
  final VoidCallback onLoadPrevious;
  final VoidCallback onShowSource;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final error = state.error;
    if (error != null) {
      return AppErrorState(title: l10n.errorMessage(error), onRetry: null);
    }
    if (state.loading && state.generation == 0) {
      return const DelayedSpinner();
    }
    switch (state.mode) {
      case ViewerMode.preview:
        final file = source;
        if (isMarkdownName(file.displayName)) {
          return MarkdownPreview(
            source: file,
            data: state.markdown,
            size: state.size,
            generation: state.generation,
            fontSize: fontSize,
          );
        }
        if (textPreviewFormatOf(file.displayName) != null) {
          if (state.size == 0) {
            return AppEmptyState(
              title: l10n.viewerEmptyFile,
              icon: AppIcons.file,
            );
          }
          final preview = state.textPreview;
          return switch (preview) {
            HtmlPreviewData(:final html, :final images) => RichTextPreview(
              html: html,
              images: images,
              source: source,
              generation: state.generation,
              fontSize: fontSize,
            ),
            TablePreviewData() => DelimitedPreview(
              data: preview,
              fontSize: fontSize,
            ),
            FailedTextPreview(:final reason) => AppEmptyState(
              title: reason == TextPreviewFailure.limit
                  ? l10n.textPreviewLimit(
                      l10n.fileSize(
                        textPreviewFormatOf(file.displayName)!.maxInputBytes,
                      ),
                    )
                  : l10n.textPreviewFailed,
              icon: AppIcons.file,
              action: OutlinedButton(
                onPressed: onShowSource,
                child: Text(l10n.textPreviewSource),
              ),
            ),
            _ => const DelayedSpinner(),
          };
        }
        if (file is DocumentFileSource && isDocumentName(file.displayName)) {
          return DocumentPreviewScreen(
            source: file,
            generation: state.generation,
            fontSize: documentFontSize,
            onFontSizeChanged: onDocumentFontSizeChanged,
            focusNode: documentFocus,
            autofocus: autofocus,
            shortcutMap: shortcutMap,
          );
        }
        return PreviewView(
          source: source,
          size: state.size,
          generation: state.generation,
        );
      case ViewerMode.hex:
        if (state.size == 0) {
          return AppEmptyState(
            title: l10n.viewerEmptyFile,
            icon: AppIcons.file,
          );
        }
        return _Windowed(
          state: state,
          onLoadNext: onLoadNext,
          onLoadPrevious: onLoadPrevious,
          child: HexView(
            bytes: state.bytes,
            baseOffset: state.offset,
            matchesByLine: state.matchesByLine,
            current: state.current,
            fontSize: fontSize,
            controller: scroll,
            onLayout: onLayout,
          ),
        );
      case ViewerMode.text:
        if (state.size == 0) {
          return AppEmptyState(
            title: l10n.viewerEmptyFile,
            icon: AppIcons.file,
          );
        }
        return _Windowed(
          state: state,
          onLoadNext: onLoadNext,
          onLoadPrevious: onLoadPrevious,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.window.binary) _BinaryHint(text: l10n.viewerBinaryHint),
              Expanded(
                child: TextView(
                  window: state.window,
                  syntax: state.syntax,
                  matchesByLine: state.matchesByLine,
                  current: state.current,
                  wrap: state.wrap,
                  fontSize: fontSize,
                  controller: scroll,
                  onLayout: onLayout,
                  // Line numbers count from the file's start: known only
                  // while the window starts there.
                  firstLine: state.offset == 0 ? 1 : null,
                ),
              ),
            ],
          ),
        );
    }
  }
}

/// A part of a larger file: the content between the buttons to the parts
/// before and after it.
class _Windowed extends StatelessWidget {
  const _Windowed({
    required this.state,
    required this.onLoadNext,
    required this.onLoadPrevious,
    required this.child,
  });

  final ViewerState state;
  final VoidCallback onLoadNext;
  final VoidCallback onLoadPrevious;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!state.windowed) return child;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.hasPrevious)
          _PartButton(
            label: l10n.viewerLoadPrevious,
            icon: AppIcons.chevronUp,
            edge: _PartEdge.bottom,
            onPressed: onLoadPrevious,
          ),
        Expanded(child: child),
        if (state.hasNext)
          _PartButton(
            label: l10n.viewerLoadNext,
            icon: AppIcons.chevronDown,
            edge: _PartEdge.top,
            onPressed: onLoadNext,
          ),
      ],
    );
  }
}

/// The side of a part button that faces the content: the other one
/// meets a bar that draws the line already.
enum _PartEdge { top, bottom }

class _PartButton extends StatelessWidget {
  const _PartButton({
    required this.label,
    required this.icon,
    required this.edge,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final _PartEdge edge;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final side = BorderSide(color: colors.line);
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: switch (edge) {
          _PartEdge.top => AppBorder(top: side),
          _PartEdge.bottom => AppBorder(bottom: side),
        },
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: AppIconSize.sm),
          label: Text(label),
        ),
      ),
    );
  }
}

class _BinaryHint extends StatelessWidget {
  const _BinaryHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        border: AppBorder(bottom: BorderSide(color: colors.line)),
      ),
      child: Row(
        spacing: AppSpacing.sm,
        children: [
          Icon(AppIcons.info, size: AppIconSize.sm, color: colors.textMuted),
          Expanded(
            child: Text(
              text,
              style: context.text.bodySmall?.copyWith(color: colors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Under the content: where in the file the top line is (a hex offset in
/// hex mode), the line's number, the encoding, and the part shown of a
/// large file, alongside the keys that return to the file list.
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.state,
    required this.topLine,
    required this.document,
    required this.shortcutMap,
    required this.showFiles,
  });

  final ViewerState state;
  final int topLine;
  final bool document;
  final ShortcutMap shortcutMap;
  final bool showFiles;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lineStarts = state.window.lineStarts;
    final topOffset = switch (state.mode) {
      ViewerMode.text =>
        state.offset + (topLine < lineStarts.length ? lineStarts[topLine] : 0),
      ViewerMode.hex => state.offset + topLine * hexRowLength,
      ViewerMode.preview => 0,
    };
    final parts = [
      switch (state.mode) {
        ViewerMode.hex => l10n.viewerPosition(
          hexOffsetText(topOffset),
          hexOffsetText(state.size),
        ),
        ViewerMode.text => l10n.viewerPosition(
          l10n.fileSize(topOffset),
          l10n.fileSize(state.size),
        ),
        ViewerMode.preview =>
          document ? l10n.viewerModePreview : l10n.fileSize(state.size),
      },
      if (state.mode == ViewerMode.text &&
          state.offset == 0 &&
          state.window.lines.isNotEmpty)
        l10n.viewerLine(topLine + 1),
      if (state.mode == ViewerMode.text) l10n.viewerEncoding,
      if (state.windowed && state.mode != ViewerMode.preview)
        l10n.viewerWindow(
          l10n.fileSize(state.bytes.length),
          l10n.fileSize(state.size),
        ),
    ];
    return ViewerFooter(
      status: parts.reduce(l10n.joinedDetails),
      shortcutMap: shortcutMap,
      showFiles: showFiles,
    );
  }
}
