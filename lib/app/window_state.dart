// Remembers where the window was: its bounds and whether it was maximised
// go into preferences after every move or resize, and the first show
// restores them so the window never has to be laid out again by hand,
// fitted to the screens there are now.

import 'dart:async';
import 'dart:math' as math;

import 'package:component_library/component_library.dart';
import 'package:flutter/widgets.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// Applies the remembered bounds, fitted to the screens, then shows the
/// window. On a hot restart the window is already up: placing it again
/// would only make the engine wait for a frame it cannot draw yet
/// ("Resize timed out").
Future<void> showWindow(Preferences preferences) async {
  if (await windowManager.isVisible()) return;
  final saved = preferences.windowBounds;
  final bounds = fitWindow(
    wanted: saved == null
        ? null
        : Rect.fromLTWH(saved.x, saved.y, saved.width, saved.height),
    workAreas: await _workAreas(),
  );
  if (bounds != null) await windowManager.setBounds(bounds);
  if (preferences.windowMaximized) await windowManager.maximize();
  await windowManager.show();
  await windowManager.focus();
}

/// The size a first run opens at: the three columns side by side.
const Size firstWindowSize = Size(1280, 800);

/// Where the window opens: the [wanted] frame (the remembered one; null on
/// a first run, which takes [firstWindowSize], centred) moved and shrunk
/// into the work area (the screen less its menu bar, dock or taskbar) of
/// the screen it is mostly on. A frame on no screen, one since unplugged,
/// opens centred on the first, the main screen. A work area smaller than
/// the minimum gets the minimum at its top left, so the title bar stays in
/// reach. Null when there is no screen to fit: the window stays as set up.
Rect? fitWindow({required Rect? wanted, required List<Rect> workAreas}) {
  const minimum = Size(AppSizes.minWindowWidth, AppSizes.minWindowHeight);
  if (workAreas.isEmpty) {
    if (wanted == null) return null;
    return wanted.topLeft &
        Size(
          math.max(wanted.width, minimum.width),
          math.max(wanted.height, minimum.height),
        );
  }
  var area = workAreas.first;
  var overlap = 0.0;
  if (wanted != null) {
    for (final candidate in workAreas) {
      final common = candidate.intersect(wanted);
      final size = common.isEmpty ? 0.0 : common.width * common.height;
      if (size > overlap) (area, overlap) = (candidate, size);
    }
  }
  final width = math.max(
    minimum.width,
    math.min(wanted?.width ?? firstWindowSize.width, area.width),
  );
  final height = math.max(
    minimum.height,
    math.min(wanted?.height ?? firstWindowSize.height, area.height),
  );
  final centred = wanted == null || overlap == 0;
  final left = centred ? area.left + (area.width - width) / 2 : wanted.left;
  final top = centred ? area.top + (area.height - height) / 2 : wanted.top;
  return Rect.fromLTWH(
    math.max(area.left, math.min(left, area.right - width)),
    math.max(area.top, math.min(top, area.bottom - height)),
    width,
    height,
  );
}

/// The screens' work areas, the main screen first; none when the system
/// does not say.
Future<List<Rect>> _workAreas() async {
  try {
    final main = await screenRetriever.getPrimaryDisplay();
    final all = await screenRetriever.getAllDisplays();
    return [
      for (final display in [main, ...all.where((d) => d.id != main.id)])
        (display.visiblePosition ?? Offset.zero) &
            (display.visibleSize ?? display.size),
    ];
  } on Exception {
    return const [];
  }
}

/// Writes bounds and the maximised flag to preferences, debounced so a drag
/// costs one write.
class WindowStateSaver with WindowListener {
  WindowStateSaver(this._preferences) {
    windowManager.addListener(this);
  }

  final PreferencesService _preferences;
  Timer? _debounce;

  @override
  void onWindowResized() => _schedule();

  @override
  void onWindowMoved() => _schedule();

  @override
  void onWindowMaximize() => _schedule();

  @override
  void onWindowUnmaximize() => _schedule();

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_save()),
    );
  }

  Future<void> _save() async {
    final maximized = await windowManager.isMaximized();
    // While maximised the normal bounds are kept as they were.
    final bounds = maximized ? null : await windowManager.getBounds();
    await _preferences.update(
      (p) => p.copyWith(
        windowMaximized: maximized,
        windowBounds: bounds == null
            ? null
            : WindowBounds(
                x: bounds.left,
                y: bounds.top,
                width: bounds.width,
                height: bounds.height,
              ),
      ),
    );
  }

  void dispose() {
    _debounce?.cancel();
    windowManager.removeListener(this);
  }
}
