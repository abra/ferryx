// How the window is framed on this desktop, decided once at start-up and
// handed to the screens as a `WindowDecor`.
//
// - macOS: the system title bar is hidden; the traffic lights stay over the
//   content, centred in the app's 52 pt top row by the runner
//   (macos/Runner/MainFlutterWindow.swift), as in a unified toolbar.
// - GNOME (and desktops built on GNOME Shell, such as Ubuntu's): the
//   system header bar is hidden and the app draws its own, with the window
//   buttons the user's `button-layout` asks for.
// - Windows, and Linux desktops that decorate windows themselves: the
//   system title bar stays. On Windows that keeps Snap Layouts and the
//   window menu, which no app-drawn caption can offer.

import 'dart:async';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

enum WindowButton { minimize, maximize, close }

/// The window buttons of an app-drawn header bar and their sides, in the
/// format of GNOME's `org.gnome.desktop.wm.preferences button-layout`:
/// `appmenu:minimize,maximize,close` puts the three at the right.
@immutable
class WindowButtonLayout {
  const WindowButtonLayout({
    this.leading = const [],
    this.trailing = const [WindowButton.close],
  });

  /// GNOME's default: a close button at the right.
  static const gnomeDefault = WindowButtonLayout();

  /// Reads a `button-layout` value, quoted as `gsettings get` prints it or
  /// bare. Names other than the three buttons (`appmenu`, `icon`, spacers)
  /// are skipped; without a colon every button is on the left.
  factory WindowButtonLayout.parse(String raw) {
    final value = raw.trim().replaceAll("'", '');
    List<WindowButton> side(String names) => [
      for (final name in names.split(','))
        ?switch (name.trim()) {
          'minimize' => WindowButton.minimize,
          'maximize' => WindowButton.maximize,
          'close' => WindowButton.close,
          _ => null,
        },
    ];
    final colon = value.indexOf(':');
    if (colon < 0) {
      return WindowButtonLayout(leading: side(value), trailing: const []);
    }
    return WindowButtonLayout(
      leading: side(value.substring(0, colon)),
      trailing: side(value.substring(colon + 1)),
    );
  }

  final List<WindowButton> leading;
  final List<WindowButton> trailing;

  @override
  bool operator ==(Object other) =>
      other is WindowButtonLayout &&
      listEquals(other.leading, leading) &&
      listEquals(other.trailing, trailing);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(leading), Object.hashAll(trailing));

  @override
  String toString() => 'WindowButtonLayout($leading : $trailing)';
}

enum WindowFrameKind {
  /// The system draws the title bar.
  system,

  /// macOS: hidden title bar, traffic lights over the content.
  trafficLights,

  /// GNOME: hidden system header bar, the app draws one.
  headerBar,
}

@immutable
class WindowFrame {
  const WindowFrame(
    this.kind, {
    this.buttons = WindowButtonLayout.gnomeDefault,
  });

  /// The frame a platform gets when nothing more is known about the
  /// desktop (tests, and the first guess before [detect]).
  factory WindowFrame.forPlatform(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.macOS => const WindowFrame(
          WindowFrameKind.trafficLights,
        ),
        TargetPlatform.linux => const WindowFrame(WindowFrameKind.headerBar),
        _ => const WindowFrame(WindowFrameKind.system),
      };

  final WindowFrameKind kind;

  /// Buttons of an app-drawn header bar.
  final WindowButtonLayout buttons;

  /// Where the runner draws the traffic lights: 20 pt from the left edge,
  /// three 14 pt buttons 6 pt apart, centred in the 52 pt top row.
  static const Rect trafficLights = Rect.fromLTWH(20, 19, 3 * 14 + 2 * 6, 14);

  /// The traffic lights' share of the top row: a 14 pt gap after them
  /// keeps the first control clear.
  static const double trafficLightsInset = 20 + 3 * 14 + 2 * 6 + 14;

  /// One button slot of the app's header bar: a 24 px circle in 34 px.
  static const double headerBarButtonSlot = 34;

  bool get integrated => kind != WindowFrameKind.system;

  double get leadingInset => switch (kind) {
    WindowFrameKind.trafficLights => trafficLightsInset,
    WindowFrameKind.headerBar => _slots(buttons.leading),
    WindowFrameKind.system => 0,
  };

  double get trailingInset =>
      kind == WindowFrameKind.headerBar ? _slots(buttons.trailing) : 0;

  static double _slots(List<WindowButton> side) =>
      side.isEmpty ? 0 : side.length * headerBarButtonSlot + 6;

  /// Reads the desktop. On Linux the app draws the header bar only under
  /// GNOME Shell (`XDG_CURRENT_DESKTOP` lists GNOME, as on Ubuntu and
  /// Fedora) and asks GNOME which buttons it shows; other desktops keep
  /// their own decorations.
  static Future<WindowFrame> detect({
    Map<String, String>? environment,
    Future<ProcessResult> Function(String, List<String>)? run,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.linux) {
      return WindowFrame.forPlatform(defaultTargetPlatform);
    }
    final desktop =
        (environment ?? Platform.environment)['XDG_CURRENT_DESKTOP'];
    final gnome = (desktop ?? '')
        .split(':')
        .any((name) => name.toUpperCase() == 'GNOME' || name == 'Unity');
    if (!gnome) return const WindowFrame(WindowFrameKind.system);
    return WindowFrame(
      WindowFrameKind.headerBar,
      buttons: await _buttonLayout(run ?? Process.run),
    );
  }

  static Future<WindowButtonLayout> _buttonLayout(
    Future<ProcessResult> Function(String, List<String>) run,
  ) async {
    try {
      final result = await run('gsettings', [
        'get',
        'org.gnome.desktop.wm.preferences',
        'button-layout',
      ]).timeout(const Duration(milliseconds: 500));
      if (result.exitCode == 0) {
        return WindowButtonLayout.parse('${result.stdout}');
      }
    } on Object {
      // No gsettings (a minimal session): GNOME's default.
    }
    return WindowButtonLayout.gnomeDefault;
  }

  @override
  bool operator ==(Object other) =>
      other is WindowFrame && other.kind == kind && other.buttons == buttons;

  @override
  int get hashCode => Object.hash(kind, buttons);
}
