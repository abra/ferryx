// The window's own title bar where the app draws it (`WindowFrame`): on
// macOS the system bar is hidden and the traffic lights stay; on GNOME the
// system header bar is hidden and the app draws the window buttons. The
// workspace weaves the top row into its panels' bars (`WindowDecor`);
// other screens get a strip of the platform's top-row height with the
// title, which also drags and zooms the window. The OS title is kept up to
// date for Mission Control, the Dock and the taskbar, and the system's own
// surfaces follow the app's light or dark theme.

import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:ferryx/app/window_frame.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

/// What the title bar shows: the active panel's folder.
class WindowTitle extends ChangeNotifier {
  String? _location;
  bool _integrated = false;

  /// The screen on show draws the window's top row itself, so no strip.
  bool get integrated => _integrated;

  set integrated(bool value) {
    if (value == _integrated) return;
    _integrated = value;
    _notify();
  }

  String? get location => _location;

  set location(String? value) {
    if (value == _location) return;
    _location = value;
    _notify();
  }

  bool _disposed = false;
  bool _notifyScheduled = false;

  /// Screens report their place while they build, so listeners hear about
  /// a change a moment later (one notification per burst).
  void _notify() {
    if (_disposed || _notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// "Documents — Ferryx", shorter when nothing is open.
  String get text => [?_location, 'Ferryx'].join(' — ');
}

/// Marks the window's top row as drawn by [child] while it is on screen.
class WindowTitleIntegration extends StatefulWidget {
  const WindowTitleIntegration({
    required this.title,
    required this.child,
    super.key,
  });

  final WindowTitle title;
  final Widget child;

  @override
  State<WindowTitleIntegration> createState() => _WindowTitleIntegrationState();
}

class _WindowTitleIntegrationState extends State<WindowTitleIntegration> {
  @override
  void initState() {
    super.initState();
    widget.title.integrated = true;
  }

  @override
  void dispose() {
    widget.title.integrated = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// How the screens lay out the window's top row in [frame].
WindowDecor windowDecor(WindowFrame frame, {double cornerRadius = 0}) {
  if (!frame.integrated) return WindowDecor.none;
  return WindowDecor(
    leadingInset: frame.leadingInset,
    trailingInset: frame.trailingInset,
    cornerRadius: cornerRadius,
    dragArea: (child) => GestureDetector(
      onDoubleTap: toggleWindowZoom,
      behavior: HitTestBehavior.translucent,
      child: DragToMoveArea(child: child),
    ),
  );
}

Future<void> toggleWindowZoom() async {
  try {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  } on MissingPluginException {
    // No window plugin (tests).
  }
}

/// Puts the title strip above [child] where the app draws the title bar,
/// and GNOME's window buttons over the window's top row; under a system
/// title bar [child] shows unchanged.
class WindowChrome extends StatefulWidget {
  const WindowChrome({
    required this.title,
    required this.frame,
    required this.child,
    super.key,
  });

  final WindowTitle title;
  final WindowFrame frame;
  final Widget child;

  @override
  State<WindowChrome> createState() => _WindowChromeState();
}

class _WindowChromeState extends State<WindowChrome> with WindowListener {
  String? _osTitle;
  Brightness? _brightness;
  bool _fullScreen = false;
  bool _fullScreenEvent = false;

  @override
  void initState() {
    super.initState();
    widget.title.addListener(_onTitleChanged);
    windowManager.addListener(this);
    unawaited(_readFullScreen());
  }

  Future<void> _readFullScreen() async {
    try {
      final value = await windowManager.isFullScreen();
      if (mounted && !_fullScreenEvent) _setFullScreen(value);
    } on MissingPluginException {
      // No window plugin (tests).
    }
  }

  void _setFullScreen(bool value) {
    if (value != _fullScreen) setState(() => _fullScreen = value);
  }

  @override
  void onWindowEnterFullScreen() {
    _fullScreenEvent = true;
    _setFullScreen(true);
  }

  @override
  void onWindowLeaveFullScreen() {
    _fullScreenEvent = true;
    _setFullScreen(false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (brightness != _brightness) {
      _brightness = brightness;
      unawaited(_syncBrightness(brightness));
    }
  }

  /// The title bar, file dialogs and system menus in the app's theme, not
  /// the desktop's, when the two differ.
  static Future<void> _syncBrightness(Brightness brightness) async {
    try {
      await windowManager.setBrightness(brightness);
    } on MissingPluginException {
      // No window plugin (tests).
    }
  }

  void _onTitleChanged() => unawaited(_syncOsTitle());

  /// Mission Control and the Dock show the window by its OS title.
  Future<void> _syncOsTitle() async {
    final text = widget.title.text;
    if (text == _osTitle) return;
    _osTitle = text;
    try {
      await windowManager.setTitle(text);
    } on MissingPluginException {
      // No window plugin (tests).
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    widget.title.removeListener(_onTitleChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = widget.frame;
    if (!frame.integrated) return widget.child;
    // The window buttons stay over every route, its dialogs too: a layer
    // over the whole window keeps its top row clear of them.
    return WindowDecorScope(
      decor: windowDecor(
        frame,
        cornerRadius:
            !_fullScreen && frame.kind == WindowFrameKind.trafficLights
            ? context.metrics.radius.window
            : 0,
      ),
      child: ListenableBuilder(
        listenable: widget.title,
        builder: (context, _) {
          final content = widget.title.integrated
              ? widget.child
              : Column(
                  children: [
                    _TitleStrip(title: widget.title.text, frame: frame),
                    Expanded(child: widget.child),
                  ],
                );
          if (frame.kind != WindowFrameKind.headerBar) return content;
          final height = context.metrics.topBarHeight;
          return Stack(
            children: [
              Positioned.fill(child: content),
              if (frame.buttons.leading.isNotEmpty)
                Positioned(
                  left: 0,
                  top: 0,
                  height: height,
                  child: _HeaderBarButtons(frame.buttons.leading),
                ),
              if (frame.buttons.trailing.isNotEmpty)
                Positioned(
                  right: 0,
                  top: 0,
                  height: height,
                  child: _HeaderBarButtons(frame.buttons.trailing),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A plain title bar over screens that do not draw the top row: the
/// title centred over the whole width, clear of the window buttons.
class _TitleStrip extends StatelessWidget {
  const _TitleStrip({required this.title, required this.frame});

  final String title;
  final WindowFrame frame;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final side = frame.leadingInset > frame.trailingInset
        ? frame.leadingInset
        : frame.trailingInset;
    return SizedBox(
      height: context.metrics.topBarHeight,
      child: DragToMoveArea(
        child: GestureDetector(
          onDoubleTap: toggleWindowZoom,
          behavior: HitTestBehavior.opaque,
          child: Container(
            decoration: BoxDecoration(
              color: colors.windowChrome,
              border: AppBorder(bottom: BorderSide(color: colors.line)),
            ),
            padding: EdgeInsets.symmetric(horizontal: side + AppSpacing.sm),
            alignment: Alignment.center,
            child: Text(
              title,
              style: context.text.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

/// GNOME's window buttons: round, quiet, the ones the user's button layout
/// lists, in its order.
class _HeaderBarButtons extends StatelessWidget {
  const _HeaderBarButtons(this.buttons);

  final List<WindowButton> buttons;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (final button in buttons) _WindowButton(button)],
    ),
  );
}

class _WindowButton extends StatefulWidget {
  const _WindowButton(this.button);

  final WindowButton button;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;
  bool _pressed = false;

  Future<void> _activate() async {
    try {
      switch (widget.button) {
        case WindowButton.close:
          await windowManager.close();
        case WindowButton.minimize:
          await windowManager.minimize();
        case WindowButton.maximize:
          await toggleWindowZoom();
      }
    } on MissingPluginException {
      // No window plugin (tests).
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    final (icon, label) = switch (widget.button) {
      WindowButton.close => (AppIcons.close, l10n.windowClose),
      WindowButton.minimize => (AppIcons.windowMinimize, l10n.windowMinimize),
      WindowButton.maximize => (AppIcons.windowMaximize, l10n.windowMaximize),
    };
    return Semantics(
      button: true,
      label: label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: () {
            setState(() => _pressed = false);
            unawaited(_activate());
          },
          child: SizedBox(
            width: WindowFrame.headerBarButtonSlot,
            child: Center(
              child: Container(
                width: AppIconSize.lg + AppSpacing.xs,
                height: AppIconSize.lg + AppSpacing.xs,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Adwaita's circular buttons: a faint fill that deepens
                  // under the pointer and again while pressed.
                  color: _pressed
                      ? colors.selectionMuted
                      : _hovered
                      ? colors.pressedFill
                      : colors.hoverFill,
                ),
                child: Icon(
                  icon,
                  size: AppIconSize.xs,
                  color: context.colors.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
