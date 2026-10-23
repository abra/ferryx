import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'channel_platform_services.dart';
import 'desktop_platform_services.dart';
import 'file_drag_request.dart';
import 'platform_capabilities.dart';
import 'quick_look.dart';

/// What only some desktops offer, behind one service the composition root
/// creates and hands to the screens: Quick Look, the share picker, files
/// dragged to and from other applications. Features ask [capabilities]
/// (the commands without one are hidden) and never the platform.
abstract class PlatformServices {
  const PlatformServices();

  /// The implementation for [platform]: the runner's channel on macOS,
  /// the desktop's drags alone elsewhere.
  factory PlatformServices.forPlatform(TargetPlatform platform) =>
      platform == TargetPlatform.macOS
      ? ChannelPlatformServices()
      : DesktopPlatformServices();

  PlatformCapabilities get capabilities;

  /// Whether the keyboard layout types Latin letters (U.S., German) rather
  /// than another script (Russian, Greek), whose chords are found by the
  /// keys' places (`ChordLayout` in packages/shortcuts). Always `true`
  /// where the desktop does not say.
  ValueListenable<bool> get latinKeyboard;

  // ─── Quick Look ───

  /// Whether the Quick Look panel is open; it may close by itself (its
  /// close button, Esc while it has the keys), which also sends
  /// [QuickLookClosed].
  ValueListenable<bool> get quickLookOpen;

  /// What the open panel reports: it closed, ↑ or ↓ pressed on it.
  Stream<QuickLookEvent> get quickLookEvents;

  /// Opens the panel on [items], or shows them in the panel already open.
  Future<void> showQuickLook(QuickLookItems items);

  /// Turns the open panel to item [index] of what it shows, without
  /// sending the list again: the cursor moved in the panel.
  Future<void> selectQuickLookItem(int index);

  Future<void> closeQuickLook();

  // ─── Share ───

  /// The share picker for [paths], pointing at [anchor] (the window's
  /// logical coordinates: the cursor's row, or where a menu was opened).
  Future<void> share(List<String> paths, {required Rect anchor});

  // ─── Drag and drop ───

  /// Starts dragging files out of [context]'s window through the desktop's
  /// own session. Drops come back through `PlatformDropArea`.
  Future<void> startFileDrag(BuildContext context, FileDragRequest request);

  Future<void> dispose();
}
