import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// The desktop whose conventions the interface follows: Apple's Human
/// Interface Guidelines on macOS, Fluent on Windows 11, the GNOME HIG
/// (libadwaita) on Linux.
///
/// The layout is one for all three; type, colour, sizes, radii, window
/// chrome and the behaviour of shared controls come from the style. The
/// composition root picks it from the platform and builds the theme for it
/// (`AppTheme.of`); widgets read it through `context.metrics.style`, never
/// from `defaultTargetPlatform`.
enum AppPlatformStyle {
  macos(TargetPlatform.macOS),
  windows(TargetPlatform.windows),
  gnome(TargetPlatform.linux);

  const AppPlatformStyle(this.targetPlatform);

  /// What `ThemeData.platform` reports under this style, so Flutter's own
  /// platform conventions (chord labels, text editing keys) agree with it.
  final TargetPlatform targetPlatform;

  /// The style of [platform]. iOS reads as macOS; Android and Fuchsia, which
  /// only run under tests, read as the Linux desktop.
  static AppPlatformStyle of(TargetPlatform platform) => switch (platform) {
    TargetPlatform.macOS || TargetPlatform.iOS => macos,
    TargetPlatform.windows => windows,
    TargetPlatform.linux ||
    TargetPlatform.android ||
    TargetPlatform.fuchsia => gnome,
  };

  /// The style of the platform the app runs on; honours
  /// `debugDefaultTargetPlatformOverride` in tests.
  static AppPlatformStyle get current => of(defaultTargetPlatform);

  /// The desktop's file manager, for «Show in …».
  FileManager get fileManager => switch (this) {
    macos => FileManager.finder,
    windows => FileManager.explorer,
    gnome => FileManager.files,
  };
}

/// What shows files on each desktop: Finder, File Explorer, GNOME Files.
enum FileManager { finder, explorer, files }

/// The macOS releases whose controls differ in size and shape, as native
/// apps change with the system: through macOS 15 (Sequoia), and from
/// macOS 26 (Tahoe) on, whose controls are taller and rounder, the switch's
/// knob a pill and the search field a capsule. Only the macOS style reads
/// it; the composition root picks it from the running system.
enum MacGeneration {
  sequoia,
  tahoe;

  /// The generation of the system [operatingSystemVersion] describes
  /// (`Platform.operatingSystemVersion`: `Version 26.0 (Build 25A354)`);
  /// Sequoia when it names no version.
  static MacGeneration fromVersion(String operatingSystemVersion) {
    final major = RegExp(r'(\d+)').firstMatch(operatingSystemVersion);
    final version = major == null ? 0 : int.parse(major.group(1)!);
    return version >= 26 ? tahoe : sequoia;
  }

  /// In tests: the generation [current] answers, whatever runs them.
  static MacGeneration? debugOverride;

  /// The generation of the macOS the app runs on (Sequoia elsewhere).
  static MacGeneration get current =>
      debugOverride ??
      (Platform.isMacOS
          ? fromVersion(Platform.operatingSystemVersion)
          : sequoia);
}
