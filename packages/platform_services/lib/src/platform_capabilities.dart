import 'package:flutter/foundation.dart';

/// What this desktop offers beyond the core. A command whose capability is
/// missing is not shown at all (menus, the palette, the cheat sheet, the
/// hotkeys), never shown and then failing.
@immutable
class PlatformCapabilities {
  const PlatformCapabilities({
    this.quickLook = false,
    this.share = false,
    this.fileDrags = false,
  });

  /// Nothing beyond the core: the fallback, and tests that need none.
  static const none = PlatformCapabilities();

  /// The system's Quick Look panel (macOS).
  final bool quickLook;

  /// The system's share picker (macOS's `NSSharingServicePicker`).
  final bool share;

  /// Files dragged out of the window to other applications and dropped
  /// into it from them, through the desktop's own drag session.
  final bool fileDrags;

  @override
  bool operator ==(Object other) =>
      other is PlatformCapabilities &&
      other.quickLook == quickLook &&
      other.share == share &&
      other.fileDrags == fileDrags;

  @override
  int get hashCode => Object.hash(quickLook, share, fileDrags);

  @override
  String toString() =>
      'PlatformCapabilities(quickLook: $quickLook, share: $share, '
      'fileDrags: $fileDrags)';
}
