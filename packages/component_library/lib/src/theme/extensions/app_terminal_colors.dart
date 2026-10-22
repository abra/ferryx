import 'package:flutter/material.dart';

/// The sixteen ANSI colours of the integrated terminal, per brightness;
/// read through `context.terminalColors`.
///
/// Tuned for the content surfaces of every style (white to `#FCFCFC` in
/// light, `#1D1D20` to `#282828` in dark), with the hues of the tag inks:
/// the eight normal colours and the bright ones read at 4.5:1 or more but
/// for the two that are the background's own (black in dark, white in
/// light) and bright white in light. The terminal's background, text,
/// cursor and selection are the theme's roles, not these.
@immutable
class AppTerminalColors extends ThemeExtension<AppTerminalColors> {
  const AppTerminalColors({required this.ansi});

  factory AppTerminalColors.forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  /// Black, red, green, yellow, blue, magenta, cyan, white, then the same
  /// eight bright: the order of the escape codes 30–37 and 90–97.
  final List<Color> ansi;

  Color get black => ansi[0];
  Color get red => ansi[1];
  Color get green => ansi[2];
  Color get yellow => ansi[3];
  Color get blue => ansi[4];
  Color get magenta => ansi[5];
  Color get cyan => ansi[6];
  Color get white => ansi[7];
  Color get brightBlack => ansi[8];
  Color get brightRed => ansi[9];
  Color get brightGreen => ansi[10];
  Color get brightYellow => ansi[11];
  Color get brightBlue => ansi[12];
  Color get brightMagenta => ansi[13];
  Color get brightCyan => ansi[14];
  Color get brightWhite => ansi[15];

  static const _light = AppTerminalColors(
    ansi: [
      Color(0xFF1F2328),
      Color(0xFFB8231A),
      Color(0xFF1B7A33),
      Color(0xFF7A5A00),
      Color(0xFF1D62CF),
      Color(0xFF8634C4),
      Color(0xFF0E7480),
      Color(0xFF6E7781),
      Color(0xFF57606A),
      Color(0xFFD1242F),
      Color(0xFF1A7F37),
      Color(0xFF946200),
      Color(0xFF0969DA),
      Color(0xFFA044D6),
      Color(0xFF0F7C89),
      Color(0xFF8C959F),
    ],
  );

  static const _dark = AppTerminalColors(
    ansi: [
      Color(0xFF545A63),
      Color(0xFFFF7A70),
      Color(0xFF55CF7E),
      Color(0xFFEBC63E),
      Color(0xFF6EA9FF),
      Color(0xFFC69CFF),
      Color(0xFF4FD0D9),
      Color(0xFFC9D1D9),
      Color(0xFF8B949E),
      Color(0xFFFFA198),
      Color(0xFF7EE2A0),
      Color(0xFFF5D96B),
      Color(0xFF9AC4FF),
      Color(0xFFDBBEFF),
      Color(0xFF86E5EA),
      Color(0xFFFFFFFF),
    ],
  );

  /// Fixed per brightness; another one is a new palette, not a copy.
  @override
  AppTerminalColors copyWith() => this;

  @override
  AppTerminalColors lerp(AppTerminalColors? other, double t) {
    if (other == null) return this;
    return AppTerminalColors(
      ansi: [
        for (var i = 0; i < ansi.length; i++)
          Color.lerp(ansi[i], other.ansi[i], t)!,
      ],
    );
  }
}
