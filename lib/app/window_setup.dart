import 'package:component_library/component_library.dart';
import 'package:ferryx/app/window_frame.dart';
import 'package:ferryx/app/window_state.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop window defaults: a size that fits two panels and a minimum
/// below which they stop being usable. The window stays hidden here;
/// `showWindow` (window_state.dart) shows it once preferences are loaded,
/// at the remembered frame fitted to the screens.
///
/// Where the app draws the title bar itself ([WindowFrame.integrated]:
/// macOS, GNOME), the system's is hidden; elsewhere the native bar stays
/// with the window menu. Returns the frame for the screens to lay out by.
Future<WindowFrame> configureWindow() async {
  await windowManager.ensureInitialized();
  final frame = await WindowFrame.detect();
  final options = WindowOptions(
    size: firstWindowSize,
    minimumSize: const Size(AppSizes.minWindowWidth, AppSizes.minWindowHeight),
    center: true,
    title: 'Ferryx',
    titleBarStyle: frame.integrated
        ? TitleBarStyle.hidden
        : TitleBarStyle.normal,
    windowButtonVisibility: true,
  );
  await windowManager.waitUntilReadyToShow(options);
  return frame;
}
