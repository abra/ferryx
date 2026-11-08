import 'dart:ui' as ui;

import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// The emulator's type and colours from the theme, made once per change:
/// xterm.dart drops its glyph cache whenever it is handed another theme or
/// style object, so equal inputs must give the same instances.
class TerminalLook {
  /// The line height of the emulator's text, as the view lays it out.
  static const lineHeightFactor = AppTypography.terminalLineHeightFactor;

  TerminalTheme? _theme;
  List<Object?>? _themeKey;
  TerminalStyle? _style;
  List<Object?>? _styleKey;
  Size? _cell;

  /// The colours: text and background of the content surface, the cursor
  /// in the accent (translucent, so the letter under it shows), the
  /// selection in the selection colours, emphasized where the keys are
  /// ([active]) and grey elsewhere, the sixteen ANSI colours of
  /// [AppTerminalColors], search hits in the highlight colour.
  TerminalTheme themeOf(BuildContext context, {required bool active}) {
    final scheme = context.colors;
    final app = context.appColors;
    final ansi = context.terminalColors;
    final selection = active
        ? app.selectionAccent.withValues(alpha: 0.35)
        : app.selectionMuted;
    final key = [
      scheme.surface,
      scheme.onSurface,
      app.accent,
      selection,
      app.highlight,
      ...ansi.ansi,
    ];
    final cached = _theme;
    if (cached != null && _sameAs(_themeKey, key)) return cached;
    _themeKey = key;
    return _theme = TerminalTheme(
      cursor: app.accent.withValues(alpha: 0.7),
      selection: selection,
      foreground: scheme.onSurface,
      background: scheme.surface,
      black: ansi.black,
      red: ansi.red,
      green: ansi.green,
      yellow: ansi.yellow,
      blue: ansi.blue,
      magenta: ansi.magenta,
      cyan: ansi.cyan,
      white: ansi.white,
      brightBlack: ansi.brightBlack,
      brightRed: ansi.brightRed,
      brightGreen: ansi.brightGreen,
      brightYellow: ansi.brightYellow,
      brightBlue: ansi.brightBlue,
      brightMagenta: ansi.brightMagenta,
      brightCyan: ansi.brightCyan,
      brightWhite: ansi.brightWhite,
      searchHitBackground: app.highlight,
      searchHitBackgroundCurrent: app.accentSoft,
      searchHitForeground: scheme.onSurface,
    );
  }

  /// The chosen face at [fontSize], or the platform's monospace default.
  TerminalStyle styleOf(
    BuildContext context,
    double fontSize, {
    String fontFamily = '',
  }) {
    final type = context.metrics.typeScale;
    final family = fontFamily.isEmpty ? type.monoFamily : fontFamily;
    final key = [family, type.monoFamily, ...type.monoFallback, fontSize];
    final cached = _style;
    if (cached != null && _sameAs(_styleKey, key)) return cached;
    _styleKey = key;
    _cell = null;
    return _style = TerminalStyle(
      fontSize: fontSize,
      height: lineHeightFactor,
      fontFamily: family,
      fontFamilyFallback: [
        if (family != type.monoFamily) type.monoFamily,
        ...type.monoFallback,
        ...symbolFonts,
      ],
    );
  }

  /// Faces with the icons shell prompts draw (Powerline, Nerd Fonts) in
  /// the Private Use Area, which no system face has: used when one is
  /// installed, for those glyphs only.
  static const symbolFonts = [
    'MesloLGS NF',
    'MesloLGS Nerd Font Mono',
    'Symbols Nerd Font Mono',
    'JetBrainsMono Nerd Font Mono',
    'Hack Nerd Font Mono',
    'FiraCode Nerd Font Mono',
  ];

  /// One character cell of [style], measured as the view measures it (ten
  /// `m`s, unscaled: the terminal's font size is its own setting).
  Size cellOf(TerminalStyle style) {
    if (identical(style, _style) && _cell != null) return _cell!;
    final text = style.toTextStyle();
    final builder = ui.ParagraphBuilder(text.getParagraphStyle())
      ..pushStyle(text.getTextStyle(textScaler: TextScaler.noScaling))
      ..addText('mmmmmmmmmm');
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    final cell = Size(paragraph.maxIntrinsicWidth / 10, paragraph.height);
    paragraph.dispose();
    if (identical(style, _style)) _cell = cell;
    return cell;
  }

  static bool _sameAs(List<Object?>? a, List<Object?> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
