import 'package:flutter/material.dart';

import '../extensions/app_colors_ext.dart';

/// Ferryx's Balanced palette: blue accents, quiet surfaces and soft row
/// selection. Geometry and typography remain native through AppMetrics and
/// AppTypography; colour roles are shared across desktops.
///
/// Both palettes are constants. Theme rebuilds and row painting reuse them.
@immutable
class AppPalette {
  const AppPalette({
    required this.surface,
    required this.onSurface,
    required this.colors,
  });

  factory AppPalette.of(Brightness brightness) => switch (brightness) {
    Brightness.light => _light,
    Brightness.dark => _dark,
  };

  /// The content's background: documents, lists, menus, popovers.
  final Color surface;

  /// Text and icons on [surface].
  final Color onSurface;
  final AppColorsExt colors;

  // Document markings keep their own semantic colours.
  static const _markers = [
    Color(0xFFFDE68A),
    Color(0xFFBFDBFE),
    Color(0xFFBBF7D0),
    Color(0xFFFBCFE8),
    Color(0xFFFED7AA),
    Color(0xFFDDD6FE),
  ];
  static const _highlightLight = Color(0xFFFDE68A);

  // The system yellows; on a light bar the fill is too pale to stand as an
  // icon's shape, so a deeper gold draws its edge.
  static const _starLight = Color(0xFFFFCC00);
  static const _starEdgeLight = Color(0xFFB88200);
  static const _starDark = Color(0xFFFFD60A);

  /// Text colours of `[text]{.red}` (red, orange, yellow, green, blue,
  /// purple), paired with the content surface.
  static const _inksLight = [
    Color(0xFFB8231A),
    Color(0xFFB04A00),
    Color(0xFF7A5A00),
    Color(0xFF1B7A33),
    Color(0xFF1D62CF),
    Color(0xFF8634C4),
  ];
  static const _inksDark = [
    Color(0xFFFF7A70),
    Color(0xFFFFA552),
    Color(0xFFEBC63E),
    Color(0xFF55CF7E),
    Color(0xFF6EA9FF),
    Color(0xFFC69CFF),
  ];

  /// Backgrounds of `[text]{.bg-red}` and of a coloured rem, in the same
  /// order; yellow is the `==highlight==` colour.
  static const _washesLight = [
    Color(0xFFFDDEDC),
    Color(0xFFFDE6CC),
    _highlightLight,
    Color(0xFFD3F2DA),
    Color(0xFFD9E7FD),
    Color(0xFFEADCFC),
  ];
  static const _washesDark = [
    Color(0xFF5E2723),
    Color(0xFF5B3A17),
    _highlightDark,
    Color(0xFF1F4A2C),
    Color(0xFF1D3A60),
    Color(0xFF3F2B60),
  ];

  /// Selected text on a white document page, the same in both themes.
  static const _pageSelection = Color(0xFFB3D7FF);

  /// The page's selection and the keyboard's frame on it while the focus
  /// is elsewhere: the same greys on every style, as the page is white.
  static const _pageSelectionMuted = Color(0xFFDCDCDC);
  static const _pageRingMuted = Color(0xFF8E8E93);
  static const _highlightDark = Color(0xFF57491A);
  static const _hintLight = Color(0xFFFFE58A);
  static const _hintDark = Color(0xFF8A6D1D);
  static const _hintBorder = Color(0xFFD9B946);
  static const _hintInk = Color(0xFF1B1B1A);
  static const _toastError = Color(0xFF7A1A12);

  static const _light = AppPalette(
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF253449),
    colors: AppColorsExt(
      window: Color(0xFFF1F5FB),
      sidebar: Color(0xFFF3F6FB),
      windowChrome: Color(0xFFF7F9FC),
      surfaceRaised: Color(0xFFFAFCFF),
      surfaceSunken: Color(0xFFF1F5FB),
      hoverFill: Color(0xFFF0F5FC),
      pressedFill: Color(0xFFE0E9F5),
      selectionFill: Color(0xFFEDF0F5),
      controlFill: Color(0xFFFFFFFF),
      controlBorder: Color(0xFFCCD8E8),
      line: Color(0xFFDCE4EF),
      textMuted: Color(0xFF566880),
      textFaint: Color(0xFF6F8097),
      accent: Color(0xFF174DA7),
      onAccent: Color(0xFFFFFFFF),
      onSelection: Color(0xFF253449),
      onSelectionMuted: Color(0xFF566880),
      selectionAccent: Color(0xFFE5EFFE),
      selectionMuted: Color(0xFFEDF0F5),
      link: Color(0xFF174DA7),
      accentSoft: Color(0xFFD8E7FC),
      selection: Color(0xFFE5EFFE),
      focusRing: Color(0x99174DA7),
      cardMarker: Color(0xFFC93400),
      cardMarkerSoft: Color(0x24FF9500),
      ratingAgain: Color(0xFFD70015),
      ratingHard: Color(0xFFC93400),
      ratingGood: Color(0xFF248A3D),
      ratingEasy: Color(0xFF0040DD),
      ratingAgainSoft: Color(0x24FF3B30),
      ratingHardSoft: Color(0x29FF9500),
      ratingGoodSoft: Color(0x2928CD41),
      ratingEasySoft: Color(0x24007AFF),
      danger: Color(0xFFD70015),
      highlight: _highlightLight,
      hintBackground: _hintLight,
      hintBorder: _hintBorder,
      hintForeground: _hintInk,
      toastBackground: Color(0xF5F7F9FC),
      toastForeground: Color(0xFF253449),
      toastLink: Color(0xFF174DA7),
      toastError: _toastError,
      markers: _markers,
      inks: _inksLight,
      starFill: _starLight,
      starEdge: _starEdgeLight,
      washes: _washesLight,
      pageSelection: _pageSelection,
      pageSelectionMuted: _pageSelectionMuted,
      pageRingMuted: _pageRingMuted,
      switchKnob: Color(0xFFFFFFFF),
      switchTrack: Color(0xFF174DA7),
    ),
  );

  static const _dark = AppPalette(
    surface: Color(0xFF0E1829),
    onSurface: Color(0xFFD8E5FB),
    colors: AppColorsExt(
      window: Color(0xFF121F33),
      sidebar: Color(0xFF101C2F),
      windowChrome: Color(0xFF121F33),
      surfaceRaised: Color(0xFF17273F),
      surfaceSunken: Color(0xFF142238),
      hoverFill: Color(0xFF182942),
      pressedFill: Color(0xFF243B5A),
      selectionFill: Color(0xFF1B2A40),
      controlFill: Color(0xFF17273F),
      controlBorder: Color(0xFF45638F),
      line: Color(0xFF263C5C),
      textMuted: Color(0xFF9AACCB),
      textFaint: Color(0xFF7E94B4),
      accent: Color(0xFF8AB4FF),
      onAccent: Color(0xFF102140),
      onSelection: Color(0xFFD8E5FB),
      onSelectionMuted: Color(0xFF9AACCB),
      selectionAccent: Color(0xFF203C62),
      selectionMuted: Color(0xFF1B2A40),
      link: Color(0xFF8AB4FF),
      accentSoft: Color(0xFF243F64),
      selection: Color(0xFF203C62),
      focusRing: Color(0x998AB4FF),
      cardMarker: Color(0xFFFFB340),
      cardMarkerSoft: Color(0x33FF9F0A),
      ratingAgain: Color(0xFFFF6961),
      ratingHard: Color(0xFFFFB340),
      ratingGood: Color(0xFF30DB5B),
      ratingEasy: Color(0xFF409CFF),
      ratingAgainSoft: Color(0x33FF453A),
      ratingHardSoft: Color(0x33FF9F0A),
      ratingGoodSoft: Color(0x3332D74B),
      ratingEasySoft: Color(0x330A84FF),
      danger: Color(0xFFFF6961),
      highlight: _highlightDark,
      hintBackground: _hintDark,
      hintBorder: _hintBorder,
      hintForeground: Color(0xFFFFFFFF),
      toastBackground: Color(0xF5121F33),
      toastForeground: Color(0xFFD8E5FB),
      toastLink: Color(0xFF8AB4FF),
      toastError: _toastError,
      markers: _markers,
      inks: _inksDark,
      starFill: _starDark,
      starEdge: _starDark,
      washes: _washesDark,
      pageSelection: _pageSelection,
      pageSelectionMuted: _pageSelectionMuted,
      pageRingMuted: _pageRingMuted,
      switchKnob: Color(0xFFD8E5FB),
      switchTrack: Color(0xFF8AB4FF),
    ),
  );
}
