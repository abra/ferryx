import 'dart:async';
import 'dart:math' as math;

import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pagecraft/all_formats.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

import 'document_cubit.dart';
import 'document_session.dart';
import 'viewer_source.dart';

/// Host for Pagecraft resources; views below only render state and callbacks.
class DocumentPreviewScreen extends StatefulWidget {
  const DocumentPreviewScreen({
    required this.source,
    required this.generation,
    this.fontSize = Preferences.defaultDocumentFontSize,
    this.onFontSizeChanged,
    this.autofocus = true,
    this.focusNode,
    this.opener = openDocumentSession,
    this.shortcutMap,
    super.key,
  });

  final DocumentFileSource source;
  final int generation;
  final double fontSize;
  final ValueChanged<double>? onFontSizeChanged;
  final bool autofocus;
  final FocusNode? focusNode;
  final DocumentOpener opener;
  final ShortcutMap? shortcutMap;

  @override
  State<DocumentPreviewScreen> createState() => _DocumentPreviewScreenState();
}

class _DocumentPreviewScreenState extends State<DocumentPreviewScreen> {
  late final _cubit = DocumentCubit(
    opener: widget.opener,
    beforeRelease: () => WidgetsBinding.instance.endOfFrame,
  );
  FocusNode? _ownedFocus;
  FocusNode get _focus =>
      widget.focusNode ??
      (_ownedFocus ??= FocusNode(debugLabel: 'document preview'));
  late double _fontSize = Preferences.normalizeDocumentFontSize(
    widget.fontSize,
  );
  DocumentAppearance? _appearance;
  Object? _appearanceKey;
  int _openRequest = 0;

  String? _chord(AppCommand command) =>
      widget.shortcutMap?.labelOf(command, context.platform);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAppearance();
  }

  void _updateAppearance() {
    final type = context.metrics.typeScale;
    final scale = MediaQuery.textScalerOf(context);
    final key = (
      _fontSize,
      context.colors.onSurface,
      context.colors.surface,
      type,
      scale,
    );
    if (key == _appearanceKey) return;
    _appearanceKey = key;
    final first = _appearance == null;
    _appearance = DocumentAppearance(
      style: BookStyle(
        fontScale: _fontSize / 16,
        fontFamily: type.sansFamily,
        textColor: context.colors.onSurface.toARGB32(),
        backgroundColor: context.colors.surface.toARGB32(),
        lineHeight: 1.5,
        justify: false,
      ),
      fonts: BookFonts(
        serif: type.sansFamily,
        sansSerif: type.sansFamily,
        systemUi: type.sansFamily,
        monospace: type.monoFamily,
        fallback: type.sansFallback,
      ),
      settings: const TextPageSettings(
        topMargin: AppSpacing.lg,
        bottomMargin: AppSpacing.lg,
        maxColumnCount: 1,
        measure: AppSizes.documentMaxWidth,
      ),
      textScaler: scale,
    );
    if (first) {
      _open();
    } else {
      _cubit.updateAppearance(_appearance!);
    }
  }

  void _open() {
    final request = ++_openRequest;
    unawaited(
      _cubit.open(widget.source, _appearance!).then((_) {
        if (!mounted || request != _openRequest) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              widget.autofocus &&
              request == _openRequest &&
              (ModalRoute.of(context)?.isCurrent ?? true)) {
            _focus.requestFocus();
          }
        });
      }),
    );
  }

  @override
  void didUpdateWidget(DocumentPreviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fontSize != widget.fontSize) {
      _fontSize = Preferences.normalizeDocumentFontSize(widget.fontSize);
    }
    _updateAppearance();
    if (oldWidget.source != widget.source ||
        oldWidget.generation != widget.generation) {
      _open();
    }
  }

  @override
  void dispose() {
    _ownedFocus?.dispose();
    unawaited(_cubit.close());
    super.dispose();
  }

  void _setFontSize(double value) {
    final next = Preferences.normalizeDocumentFontSize(value);
    if (next == _fontSize) return;
    setState(() => _fontSize = next);
    _updateAppearance();
    widget.onFontSizeChanged?.call(next);
  }

  void _zoomIn() {
    if (_cubit.state.fixed) {
      _cubit.zoomTo(_cubit.state.zoom + 0.5);
    } else {
      _setFontSize(_fontSize + 1);
    }
  }

  void _zoomOut() {
    if (_cubit.state.fixed) {
      _cubit.zoomTo(_cubit.state.zoom - 0.5);
    } else {
      _setFontSize(_fontSize - 1);
    }
  }

  void _resetZoom() {
    if (_cubit.state.fixed) {
      _cubit.zoomTo(1);
    } else {
      _setFontSize(Preferences.defaultDocumentFontSize);
    }
  }

  Future<void> _contents() async {
    final session = _cubit.state.session;
    final entries = session?.contents;
    if (entries == null || entries.isEmpty) return;
    final selected = await showAppQuickPicker<DocumentContentsEntry>(
      context,
      builder: (_) => _DocumentContents(entries: entries),
    );
    if (!mounted || selected == null || _cubit.state.session != session) return;
    await _cubit.goToContents(selected);
  }

  Future<void> _goTo() async {
    final state = _cubit.state;
    if (!state.fixed) return _contents();
    if (state.count == 0) return;
    final index = await showAppDialog<int>(
      context,
      (_) => _DocumentPageDialog(current: state.index, count: state.count),
    );
    if (!mounted || index == null || _cubit.state.session != state.session) {
      return;
    }
    await _cubit.goTo(index);
  }

  Future<void> _menu(Rect anchor) async {
    final l10n = context.l10n;
    final state = _cubit.state;
    final picked = await showAppMenu<AppCommand>(
      context: context,
      anchor: anchor,
      entries: [
        if (state.session?.contents.isNotEmpty ?? false)
          AppMenuAction(
            value: AppCommand.documentContents,
            label: l10n.documentContents,
            shortcut: _chord(AppCommand.documentContents),
            icon: AppIcons.tableOfContents,
          ),
        if (state.fixed) ...[
          AppMenuAction(
            value: AppCommand.documentGoToPage,
            label: l10n.documentGoToPage,
            shortcut: _chord(AppCommand.viewerGoTo),
            icon: AppIcons.goTo,
          ),
          const AppMenuSeparator(),
          AppMenuAction(
            value: AppCommand.documentZoomIn,
            label: l10n.cmdDocumentZoomIn,
            shortcut: _chord(AppCommand.documentZoomIn),
            icon: AppIcons.magnifyIn,
          ),
          AppMenuAction(
            value: AppCommand.documentZoomOut,
            label: l10n.cmdDocumentZoomOut,
            shortcut: _chord(AppCommand.documentZoomOut),
            icon: AppIcons.magnifyOut,
          ),
          AppMenuAction(
            value: AppCommand.documentFitPage,
            label: l10n.documentFitPage,
            shortcut: _chord(AppCommand.documentFitPage),
            icon: AppIcons.fillWindow,
          ),
        ] else ...[
          if (state.session?.contents.isNotEmpty ?? false)
            const AppMenuSeparator(),
          AppMenuSection(l10n.documentFontSizeValue(_fontSize.round())),
          AppMenuAction(
            value: AppCommand.documentZoomIn,
            label: l10n.documentFontIncrease,
            shortcut: _chord(AppCommand.documentZoomIn),
            icon: AppIcons.add,
            enabled: _fontSize < Preferences.maxDocumentFontSize,
          ),
          AppMenuAction(
            value: AppCommand.documentZoomOut,
            label: l10n.documentFontDecrease,
            shortcut: _chord(AppCommand.documentZoomOut),
            icon: AppIcons.minus,
            enabled: _fontSize > Preferences.minDocumentFontSize,
          ),
          AppMenuAction(
            value: AppCommand.documentFitPage,
            label: l10n.documentFontReset,
            shortcut: _chord(AppCommand.documentFitPage),
            enabled: _fontSize != Preferences.defaultDocumentFontSize,
          ),
        ],
      ],
    );
    if (!mounted) return;
    switch (picked) {
      case AppCommand.documentContents:
        await _contents();
      case AppCommand.documentGoToPage:
        await _goTo();
      case AppCommand.documentZoomIn:
        _zoomIn();
      case AppCommand.documentZoomOut:
        _zoomOut();
      case AppCommand.documentFitPage:
        _resetZoom();
      default:
        break;
    }
  }

  Future<void> _link(TextSectionLayout section, int link) async {
    final href = await _cubit.followLink(section, link);
    if (!mounted || href == null) return;
    final l10n = context.l10n;
    await showAppDialog<void>(
      context,
      (context) => AppDialog(
        title: l10n.documentExternalLink,
        body: SelectableText(href),
        actions: [
          OutlinedButton(
            onPressed: () =>
                unawaited(Clipboard.setData(ClipboardData(text: href))),
            child: Text(l10n.actionCopy),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionDone),
          ),
        ],
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final action = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft ||
      LogicalKeyboardKey.arrowUp ||
      LogicalKeyboardKey.pageUp => _cubit.previous,
      LogicalKeyboardKey.arrowRight ||
      LogicalKeyboardKey.arrowDown ||
      LogicalKeyboardKey.pageDown => _cubit.next,
      LogicalKeyboardKey.home => _cubit.first,
      LogicalKeyboardKey.end => _cubit.last,
      _ => null,
    };
    if (action == null) return KeyEventResult.ignored;
    unawaited(action());
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<DocumentCubit, DocumentState>(
        bloc: _cubit,
        builder: (context, state) {
          final ready =
              state.session != null && !state.loading && state.failure == null;
          final hasContents = ready && state.session!.contents.isNotEmpty;
          return CommandHandlers(
            handlers: {
              if (ready && state.canPrevious)
                AppCommand.documentPrevious: () => unawaited(_cubit.previous()),
              if (ready && state.canNext)
                AppCommand.documentNext: () => unawaited(_cubit.next()),
              if (hasContents)
                AppCommand.documentContents: () => unawaited(_contents()),
              if (ready) ...{
                AppCommand.documentFitPage: _resetZoom,
                AppCommand.documentZoomIn: _zoomIn,
                AppCommand.documentZoomOut: _zoomOut,
                AppCommand.contextMenu: () => unawaited(
                  _menu(keyboardMenuAnchor(_focus.context ?? context)),
                ),
              },
              if (ready && state.fixed)
                AppCommand.documentGoToPage: () => unawaited(_goTo()),
              if (ready && (state.fixed || hasContents))
                AppCommand.viewerGoTo: () => unawaited(_goTo()),
            },
            child: Focus(
              focusNode: _focus,
              autofocus: widget.autofocus,
              onKeyEvent: _onKey,
              child: _DocumentView(
                state: state,
                onPrevious: () => unawaited(_cubit.previous()),
                onNext: () => unawaited(_cubit.next()),
                onContents: () => unawaited(_contents()),
                onGoTo: () => unawaited(_goTo()),
                onRetry: _open,
                onZoom: _cubit.zoomTo,
                onLink: (section, link) => unawaited(_link(section, link)),
                onMenu: (anchor) => unawaited(_menu(anchor)),
                chord: _chord,
                fontSize: _fontSize,
                onFontSizeChanged: _setFontSize,
              ),
            ),
          );
        },
      );
}

class _DocumentView extends StatelessWidget {
  const _DocumentView({
    required this.state,
    required this.onPrevious,
    required this.onNext,
    required this.onContents,
    required this.onGoTo,
    required this.onRetry,
    required this.onZoom,
    required this.onLink,
    required this.onMenu,
    required this.chord,
    required this.fontSize,
    required this.onFontSizeChanged,
  });

  final DocumentState state;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onContents;
  final VoidCallback onGoTo;
  final VoidCallback onRetry;
  final ValueChanged<double> onZoom;
  final TextLinkTapCallback onLink;
  final ValueChanged<Rect> onMenu;
  final String? Function(AppCommand) chord;
  final double fontSize;
  final ValueChanged<double> onFontSizeChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final session = state.session;
    final failure = state.failure;
    if (failure != null) {
      return AppErrorState(
        title: _failureMessage(l10n, failure),
        onRetry: failure.kind == DocumentFailureKind.read ? onRetry : null,
        retryLabel: l10n.actionRetry,
      );
    }
    if (session == null) {
      return const Center(child: AppSpinner());
    }
    final position = session.textController?.position;
    final spreadCount = position?.spreadCount;
    final sectionLabel = l10n.documentSection(state.index + 1, state.count);
    final label = state.fixed
        ? l10n.documentPage(state.index + 1, state.count)
        : spreadCount != null
        ? l10n.joinedDetails(
            sectionLabel,
            l10n.documentPage(position!.spread + 1, spreadCount),
          )
        : sectionLabel;
    return Column(
      children: [
        Container(
          height: context.metrics.topBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: context.appColors.windowChrome,
            border: AppBorder(
              bottom: BorderSide(color: context.appColors.line),
            ),
          ),
          child: AppTopBarRow(
            titleMinWidth: AppSizes.documentPositionMinWidth,
            preferLaterBelow: AppSizes.paneCompactWidth,
            title: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall,
            ),
            leading: [
              AppIconButton(
                icon: AppIcons.chevronLeft,
                tooltip: l10n.documentPrevious,
                shortcut: chord(AppCommand.documentPrevious),
                onPressed: state.canPrevious ? onPrevious : null,
              ),
              AppIconButton(
                icon: AppIcons.chevronRight,
                tooltip: l10n.documentNext,
                shortcut: chord(AppCommand.documentNext),
                onPressed: state.canNext ? onNext : null,
              ),
            ],
            forms: [
              [
                if (session.contents.isNotEmpty)
                  AppIconButton(
                    icon: AppIcons.tableOfContents,
                    tooltip: l10n.documentContents,
                    shortcut: chord(AppCommand.documentContents),
                    onPressed: state.loading ? null : onContents,
                  ),
                if (state.fixed) ...[
                  AppIconButton(
                    icon: AppIcons.goTo,
                    tooltip: l10n.documentGoToPage,
                    shortcut: chord(AppCommand.viewerGoTo),
                    onPressed: onGoTo,
                  ),
                  AppIconButton(
                    icon: AppIcons.magnifyOut,
                    tooltip: l10n.cmdDocumentZoomOut,
                    shortcut: chord(AppCommand.documentZoomOut),
                    onPressed: state.zoom > 1
                        ? () => onZoom(state.zoom - 0.5)
                        : null,
                  ),
                  AppIconButton(
                    icon: AppIcons.magnifyIn,
                    tooltip: l10n.cmdDocumentZoomIn,
                    shortcut: chord(AppCommand.documentZoomIn),
                    onPressed: state.zoom < 4
                        ? () => onZoom(state.zoom + 0.5)
                        : null,
                  ),
                  AppIconButton(
                    icon: AppIcons.fillWindow,
                    tooltip: l10n.documentFitPage,
                    shortcut: chord(AppCommand.documentFitPage),
                    onPressed: state.zoom > 1 ? () => onZoom(1) : null,
                  ),
                ] else ...[
                  _DocumentFontButton(
                    glyph: fontSize.round().toString(),
                    label: l10n.joinedDetails(
                      l10n.documentFontSizeValue(fontSize.round()),
                      l10n.documentFontReset,
                    ),
                    shortcut: chord(AppCommand.documentFitPage),
                    onPressed: fontSize != Preferences.defaultDocumentFontSize
                        ? () => onFontSizeChanged(
                            Preferences.defaultDocumentFontSize,
                          )
                        : null,
                  ),
                ],
              ],
              const [],
            ],
            trailing: [
              if (!state.fixed) ...[
                _DocumentFontButton(
                  glyph: 'A−',
                  label: l10n.documentFontDecrease,
                  shortcut: chord(AppCommand.documentZoomOut),
                  onPressed: fontSize > Preferences.minDocumentFontSize
                      ? () => onFontSizeChanged(fontSize - 1)
                      : null,
                ),
                _DocumentFontButton(
                  glyph: 'A+',
                  label: l10n.documentFontIncrease,
                  shortcut: chord(AppCommand.documentZoomIn),
                  onPressed: fontSize < Preferences.maxDocumentFontSize
                      ? () => onFontSizeChanged(fontSize + 1)
                      : null,
                ),
              ],
              Builder(
                builder: (context) => AppIconButton(
                  icon: AppIcons.more,
                  tooltip: l10n.documentActions,
                  onPressed: () => onMenu(keyboardMenuAnchor(context)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: context.colors.surface,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (session.textController case final controller?)
                  TextPagesView(
                    key: ObjectKey(session),
                    controller: controller,
                    animateTurns: false,
                    backgroundColor: context.colors.surface,
                    onTap: (point) {
                      if (point.dx < 0.3) onPrevious();
                      if (point.dx > 0.7) onNext();
                    },
                    onLinkTap: onLink,
                  )
                else if (session.fixedPages case final pages?)
                  _DocumentFixedPage(
                    key: ObjectKey(session),
                    pages: pages,
                    index: state.index,
                    zoom: state.zoom,
                    onZoom: onZoom,
                  ),
                if (state.loading) const Center(child: AppSpinner()),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DocumentFontButton extends StatelessWidget {
  const _DocumentFontButton({
    required this.glyph,
    required this.label,
    required this.shortcut,
    required this.onPressed,
  });

  final String glyph;
  final String label;
  final String? shortcut;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => AppIconButton(
    icon: AppIcons.text,
    tooltip: label,
    shortcut: shortcut,
    onPressed: onPressed,
    glyph: Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          glyph,
          style: context.text.bodySmall?.copyWith(
            color: onPressed == null
                ? context.appColors.textFaint
                : context.appColors.textMuted,
          ),
        ),
      ),
    ),
  );
}

String _failureMessage(FerryxLocalizations l10n, DocumentFailure failure) {
  final file = failure.fileError;
  if (file != null) return l10n.errorMessage(file);
  return switch (failure.kind) {
    DocumentFailureKind.password => l10n.documentPasswordRequired,
    DocumentFailureKind.fixedLayout => l10n.documentUnsupportedLayout,
    DocumentFailureKind.verticalWriting => l10n.documentUnsupportedVertical,
    DocumentFailureKind.unsupported => l10n.documentUnsupportedFormat,
    DocumentFailureKind.read => l10n.documentOpenFailed,
  };
}

class _DocumentFixedPage extends StatefulWidget {
  const _DocumentFixedPage({
    required this.pages,
    required this.index,
    required this.zoom,
    required this.onZoom,
    super.key,
  });

  final FixedPageSource pages;
  final int index;
  final double zoom;
  final ValueChanged<double> onZoom;

  @override
  State<_DocumentFixedPage> createState() => _DocumentFixedPageState();
}

class _DocumentFixedPageState extends State<_DocumentFixedPage> {
  final _transform = TransformationController();
  Size _viewport = Size.zero;

  @override
  void didUpdateWidget(_DocumentFixedPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final gestureScale = _transform.value.getMaxScaleOnAxis();
    if (oldWidget.index != widget.index ||
        (oldWidget.zoom != widget.zoom &&
            (gestureScale - widget.zoom).abs() > precisionErrorTolerance)) {
      final zoom = widget.zoom;
      _transform.value = Matrix4.identity()
        ..setEntry(0, 0, zoom)
        ..setEntry(1, 1, zoom)
        ..setEntry(0, 3, _viewport.width * (1 - zoom) / 2)
        ..setEntry(1, 3, _viewport.height * (1 - zoom) / 2);
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _viewport = constraints.biggest;
      final availableWidth = math.max(
        1.0,
        constraints.maxWidth - AppSpacing.md * 2,
      );
      final availableHeight = math.max(
        1.0,
        constraints.maxHeight - AppSpacing.md * 2,
      );
      final aspect = widget.pages.pageAspect(widget.index);
      final fitWidth = aspect == null
          ? availableWidth
          : math.min(availableWidth, availableHeight * aspect);
      final width =
          (fitWidth * MediaQuery.devicePixelRatioOf(context) * widget.zoom)
              .ceil();
      return GestureDetector(
        onDoubleTap: () => widget.onZoom(widget.zoom > 1 ? 1 : 2),
        child: InteractiveViewer(
          transformationController: _transform,
          minScale: 1,
          maxScale: 4,
          onInteractionEnd: (_) =>
              widget.onZoom(_transform.value.getMaxScaleOnAxis()),
          child: SizedBox.expand(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Image(
                image: widget.pages.pageImage(widget.index, targetWidth: width),
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                semanticLabel: context.l10n.documentPage(
                  widget.index + 1,
                  widget.pages.pageCount,
                ),
                frameBuilder: (context, child, frame, synchronous) =>
                    frame == null && !synchronous
                    ? const Center(child: AppSpinner())
                    : child,
                errorBuilder: (context, error, stack) => AppErrorState(
                  title: context.l10n.documentPageFailed(widget.index + 1),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _DocumentContents extends StatefulWidget {
  const _DocumentContents({required this.entries});
  final List<DocumentContentsEntry> entries;
  @override
  State<_DocumentContents> createState() => _DocumentContentsState();
}

class _DocumentContentsState extends State<_DocumentContents> {
  String _query = '';
  @override
  Widget build(BuildContext context) => AppQuickPicker<DocumentContentsEntry>(
    title: context.l10n.documentContents,
    hintText: context.l10n.documentContents,
    noResultsText: context.l10n.viewerNoMatch,
    entries: [
      for (final entry in widget.entries)
        if (entry.label.toLowerCase().contains(_query.toLowerCase()))
          AppQuickPickerItem(value: entry, label: entry.label),
    ],
    onQueryChanged: (value) => setState(() => _query = value),
    onPick: (pick) => Navigator.of(context).pop(pick.value),
  );
}

class _DocumentPageDialog extends StatefulWidget {
  const _DocumentPageDialog({required this.current, required this.count});
  final int current;
  final int count;
  @override
  State<_DocumentPageDialog> createState() => _DocumentPageDialogState();
}

class _DocumentPageDialogState extends State<_DocumentPageDialog> {
  late final _text = TextEditingController(text: '${widget.current + 1}');
  late int? _page = widget.current + 1;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final page = _page;
    final valid = page != null && page >= 1 && page <= widget.count;
    return AppDialog(
      title: l10n.documentGoToPage,
      body: TextField(
        controller: _text,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          hintText: l10n.documentGoToPageHint(widget.count),
        ),
        onEditingComplete: () {},
        onSubmitted: (_) {
          if (valid) Navigator.of(context).pop(page - 1);
        },
        onChanged: (value) =>
            setState(() => _page = int.tryParse(value.trim())),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: valid ? () => Navigator.of(context).pop(page - 1) : null,
          child: Text(l10n.actionGo),
        ),
      ],
    );
  }
}
