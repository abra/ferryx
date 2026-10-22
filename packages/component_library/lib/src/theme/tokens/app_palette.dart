import 'package:flutter/material.dart';

import '../app_platform_style.dart';
import '../extensions/app_colors_ext.dart';

/// The colours of one platform style and brightness: the content surface,
/// its text, and every other role in [colors].
///
/// Values follow each platform's system colours:
/// - macOS: AppKit's dynamic colours (label alphas .85/.55, separator .1,
///   systemBlue accent, the accessible variants of the system colours for
///   text such as ratings).
/// - Windows 11: Fluent's tokens (Mica backdrop, layer and card fills, text
///   alphas .894/.606/.447, the default accent #005FB8 / #60CDFF).
/// - GNOME: libadwaita 1.6's named colours (window, view, header bar and
///   sidebar backgrounds, `#3584e4` accent, text at .8 and dim .55).
///
/// The PDF markers, `==highlight==` and the click hints stay the same on
/// every platform: they belong to the document, not to the desktop.
@immutable
class AppPalette {
  const AppPalette({
    required this.surface,
    required this.onSurface,
    required this.colors,
  });

  /// The palette of [style] at [brightness].
  factory AppPalette.of(AppPlatformStyle style, Brightness brightness) =>
      switch ((style, brightness)) {
        (AppPlatformStyle.macos, Brightness.light) => _macosLight,
        (AppPlatformStyle.macos, Brightness.dark) => _macosDark,
        (AppPlatformStyle.windows, Brightness.light) => _windowsLight,
        (AppPlatformStyle.windows, Brightness.dark) => _windowsDark,
        (AppPlatformStyle.gnome, Brightness.light) => _gnomeLight,
        (AppPlatformStyle.gnome, Brightness.dark) => _gnomeDark,
      };

  /// The content's background: documents, lists, menus, popovers.
  final Color surface;

  /// Text and icons on [surface].
  final Color onSurface;
  final AppColorsExt colors;

  // Shared across platforms: document colours, not desktop ones.
  static const _markers = [
    Color(0xFFFDE68A),
    Color(0xFFBFDBFE),
    Color(0xFFBBF7D0),
    Color(0xFFFBCFE8),
    Color(0xFFFED7AA),
    Color(0xFFDDD6FE),
  ];
  static const _highlightLight = Color(0xFFFDE68A);

  /// Text colours of `[text]{.red}` (red, orange, yellow, green, blue,
  /// purple): 5.4:1 or more on the light page, 6.5:1 on the dark one.
  // The system yellows; on a light bar the fill is too pale to stand as an
  // icon's shape, so a deeper gold draws its edge.
  static const _starLight = Color(0xFFFFCC00);
  static const _starEdgeLight = Color(0xFFB88200);
  static const _starDark = Color(0xFFFFD60A);

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

  /// Selected text on a white page, the same in both themes of a style:
  /// NSColor.selectedTextBackgroundColor, and 30 % of the Fluent and
  /// libadwaita light accents over white.
  static const _pageSelectionMacos = Color(0xFFB3D7FF);
  static const _pageSelectionWindows = Color(0xFFB3CFEA);
  static const _pageSelectionGnome = Color(0xFFC2D9F7);

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

  static const _macosLight = AppPalette(
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xD9000000),
    colors: AppColorsExt(
      window: Color(0xFFECECEC),
      sidebar: Color(0xFFE9E9EB),
      windowChrome: Color(0xFFF6F6F6),
      surfaceRaised: Color(0xFFF5F5F7),
      surfaceSunken: Color(0x0D000000),
      hoverFill: Color(0x0D000000),
      pressedFill: Color(0x1A000000),
      selectionFill: Color(0x1A000000),
      controlFill: Color(0xFFFFFFFF),
      controlBorder: Color(0x26000000),
      line: Color(0x1A000000),
      textMuted: Color(0x8C000000),
      textFaint: Color(0x6B000000),
      accent: Color(0xFF007AFF),
      onAccent: Color(0xFFFFFFFF),
      onAccentMuted: Color(0xD9FFFFFF),
      selectionAccent: Color(0xFF0064E1),
      selectionMuted: Color(0x24000000),
      link: Color(0xFF0068DA),
      accentSoft: Color(0x1F007AFF),
      selection: Color(0x29007AFF),
      focusRing: Color(0x80007AFF),
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
      toastBackground: Color(0xF5F6F6F6),
      toastForeground: Color(0xD9000000),
      toastLink: Color(0xFF0068DA),
      toastError: _toastError,
      markers: _markers,
      inks: _inksLight,
      starFill: _starLight,
      starEdge: _starEdgeLight,
      washes: _washesLight,
      pageSelection: _pageSelectionMacos,
      pageSelectionMuted: _pageSelectionMuted,
      pageRingMuted: _pageRingMuted,
      switchKnob: Color(0xFFFFFFFF),
      switchTrack: Color(0xFF007AFF),
    ),
  );

  static const _macosDark = AppPalette(
    surface: Color(0xFF1E1E1E),
    onSurface: Color(0xD9FFFFFF),
    colors: AppColorsExt(
      window: Color(0xFF323232),
      sidebar: Color(0xFF2B2B2D),
      windowChrome: Color(0xFF2A2A2A),
      surfaceRaised: Color(0xFF262628),
      surfaceSunken: Color(0x12FFFFFF),
      hoverFill: Color(0x12FFFFFF),
      pressedFill: Color(0x21FFFFFF),
      selectionFill: Color(0x1FFFFFFF),
      controlFill: Color(0x40FFFFFF),
      controlBorder: Color(0x1FFFFFFF),
      line: Color(0x1AFFFFFF),
      textMuted: Color(0x8CFFFFFF),
      textFaint: Color(0x66FFFFFF),
      accent: Color(0xFF0A84FF),
      onAccent: Color(0xFFFFFFFF),
      onAccentMuted: Color(0xD9FFFFFF),
      selectionAccent: Color(0xFF0058D0),
      selectionMuted: Color(0x2EFFFFFF),
      link: Color(0xFF419CFF),
      accentSoft: Color(0x380A84FF),
      selection: Color(0x420A84FF),
      focusRing: Color(0x990A84FF),
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
      toastBackground: Color(0xF52E2E2E),
      toastForeground: Color(0xD9FFFFFF),
      toastLink: Color(0xFF419CFF),
      toastError: _toastError,
      markers: _markers,
      inks: _inksDark,
      starFill: _starDark,
      starEdge: _starDark,
      washes: _washesDark,
      pageSelection: _pageSelectionMacos,
      pageSelectionMuted: _pageSelectionMuted,
      pageRingMuted: _pageRingMuted,
      switchKnob: Color(0xFFCCCCCC),
      switchTrack: Color(0xFF1663D8),
    ),
  );

  static const _windowsLight = AppPalette(
    surface: Color(0xFFFCFCFC),
    onSurface: Color(0xE4000000),
    colors: AppColorsExt(
      window: Color(0xFFF3F3F3),
      sidebar: Color(0xFFF3F3F3),
      windowChrome: Color(0xFFFCFCFC),
      surfaceRaised: Color(0xFFF7F7F7),
      surfaceSunken: Color(0x0D000000),
      hoverFill: Color(0x0A000000),
      pressedFill: Color(0x06000000),
      selectionFill: Color(0x0A000000),
      controlFill: Color(0xB3FFFFFF),
      controlBorder: Color(0x24000000),
      line: Color(0x14000000),
      textMuted: Color(0x9B000000),
      textFaint: Color(0x72000000),
      accent: Color(0xFF005FB8),
      onAccent: Color(0xFFFFFFFF),
      onAccentMuted: Color(0xD9FFFFFF),
      selectionAccent: Color(0xFF005FB8),
      selectionMuted: Color(0x0F000000),
      link: Color(0xFF005FB8),
      accentSoft: Color(0x1F005FB8),
      selection: Color(0x24005FB8),
      focusRing: Color(0xE4000000),
      cardMarker: Color(0xFF9D5D00),
      cardMarkerSoft: Color(0xFFFFF4CE),
      ratingAgain: Color(0xFFC42B1C),
      ratingHard: Color(0xFF9D5D00),
      ratingGood: Color(0xFF0F7B0F),
      ratingEasy: Color(0xFF005FB8),
      ratingAgainSoft: Color(0xFFFDE7E9),
      ratingHardSoft: Color(0xFFFFF4CE),
      ratingGoodSoft: Color(0xFFDFF6DD),
      ratingEasySoft: Color(0x1A005FB8),
      danger: Color(0xFFC42B1C),
      highlight: _highlightLight,
      hintBackground: _hintLight,
      hintBorder: _hintBorder,
      hintForeground: _hintInk,
      toastBackground: Color(0xF22C2C2C),
      toastForeground: Color(0xFFFFFFFF),
      toastLink: Color(0xFF99EBFF),
      toastError: _toastError,
      markers: _markers,
      inks: _inksLight,
      starFill: _starLight,
      starEdge: _starEdgeLight,
      washes: _washesLight,
      pageSelection: _pageSelectionWindows,
      pageSelectionMuted: _pageSelectionMuted,
      pageRingMuted: _pageRingMuted,
      switchKnob: Color(0xFFFFFFFF),
      switchTrack: Color(0xFF005FB8),
    ),
  );

  static const _windowsDark = AppPalette(
    surface: Color(0xFF282828),
    onSurface: Color(0xFFFFFFFF),
    colors: AppColorsExt(
      window: Color(0xFF202020),
      sidebar: Color(0xFF202020),
      windowChrome: Color(0xFF282828),
      surfaceRaised: Color(0xFF2C2C2C),
      surfaceSunken: Color(0x0FFFFFFF),
      hoverFill: Color(0x0FFFFFFF),
      pressedFill: Color(0x0AFFFFFF),
      selectionFill: Color(0x0FFFFFFF),
      controlFill: Color(0x0FFFFFFF),
      controlBorder: Color(0x1FFFFFFF),
      line: Color(0x15FFFFFF),
      textMuted: Color(0xC8FFFFFF),
      textFaint: Color(0x8BFFFFFF),
      accent: Color(0xFF60CDFF),
      onAccent: Color(0xFF000000),
      onAccentMuted: Color(0xD9000000),
      selectionAccent: Color(0xFF60CDFF),
      selectionMuted: Color(0x14FFFFFF),
      link: Color(0xFF99EBFF),
      accentSoft: Color(0x2960CDFF),
      selection: Color(0x3360CDFF),
      focusRing: Color(0xFFFFFFFF),
      cardMarker: Color(0xFFFCE100),
      cardMarkerSoft: Color(0xFF433519),
      ratingAgain: Color(0xFFFF99A4),
      ratingHard: Color(0xFFFCE100),
      ratingGood: Color(0xFF6CCB5F),
      ratingEasy: Color(0xFF60CDFF),
      ratingAgainSoft: Color(0xFF442726),
      ratingHardSoft: Color(0xFF433519),
      ratingGoodSoft: Color(0xFF393D1B),
      ratingEasySoft: Color(0x2660CDFF),
      danger: Color(0xFFFF99A4),
      highlight: _highlightDark,
      hintBackground: _hintDark,
      hintBorder: _hintBorder,
      hintForeground: Color(0xFFFFFFFF),
      toastBackground: Color(0xF5F3F3F3),
      toastForeground: Color(0xFF1A1A1A),
      toastLink: Color(0xFF005FB8),
      toastError: _toastError,
      markers: _markers,
      inks: _inksDark,
      starFill: _starDark,
      starEdge: _starDark,
      washes: _washesDark,
      pageSelection: _pageSelectionWindows,
      pageSelectionMuted: _pageSelectionMuted,
      pageRingMuted: _pageRingMuted,
      switchKnob: Color(0xFF000000),
      switchTrack: Color(0xFF60CDFF),
    ),
  );

  static const _gnomeLight = AppPalette(
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xCC000006),
    colors: AppColorsExt(
      window: Color(0xFFFAFAFB),
      sidebar: Color(0xFFEBEBED),
      windowChrome: Color(0xFFFFFFFF),
      surfaceRaised: Color(0xFFFAFAFB),
      surfaceSunken: Color(0x12000006),
      hoverFill: Color(0x12000006),
      pressedFill: Color(0x29000006),
      selectionFill: Color(0x1A000006),
      controlFill: Color(0x1A000006),
      controlBorder: Color(0x26000006),
      line: Color(0x1F000006),
      textMuted: Color(0x8C000006),
      textFaint: Color(0x73000006),
      accent: Color(0xFF3584E4),
      onAccent: Color(0xFFFFFFFF),
      onAccentMuted: Color(0xD9FFFFFF),
      selectionAccent: Color(0xFF3584E4),
      selectionMuted: Color(0x1A000006),
      link: Color(0xFF1C71D8),
      accentSoft: Color(0x263584E4),
      selection: Color(0x2E3584E4),
      focusRing: Color(0x803584E4),
      cardMarker: Color(0xFF9C6E03),
      cardMarkerSoft: Color(0x26E5A50A),
      ratingAgain: Color(0xFFC01C28),
      ratingHard: Color(0xFF9C6E03),
      ratingGood: Color(0xFF1B8553),
      ratingEasy: Color(0xFF1C71D8),
      ratingAgainSoft: Color(0x1FE01B24),
      ratingHardSoft: Color(0x26E5A50A),
      ratingGoodSoft: Color(0x262EC27E),
      ratingEasySoft: Color(0x213584E4),
      danger: Color(0xFFC01C28),
      highlight: _highlightLight,
      hintBackground: _hintLight,
      hintBorder: _hintBorder,
      hintForeground: _hintInk,
      toastBackground: Color(0xF23D3D3D),
      toastForeground: Color(0xFFFFFFFF),
      toastLink: Color(0xFF99C1F1),
      toastError: _toastError,
      markers: _markers,
      inks: _inksLight,
      starFill: _starLight,
      starEdge: _starEdgeLight,
      washes: _washesLight,
      pageSelection: _pageSelectionGnome,
      pageSelectionMuted: _pageSelectionMuted,
      pageRingMuted: _pageRingMuted,
      switchKnob: Color(0xFFFFFFFF),
      switchTrack: Color(0xFF3584E4),
    ),
  );

  static const _gnomeDark = AppPalette(
    surface: Color(0xFF1D1D20),
    onSurface: Color(0xFFFFFFFF),
    colors: AppColorsExt(
      window: Color(0xFF222226),
      sidebar: Color(0xFF2E2E32),
      windowChrome: Color(0xFF2E2E32),
      surfaceRaised: Color(0xFF29292D),
      surfaceSunken: Color(0x12FFFFFF),
      hoverFill: Color(0x12FFFFFF),
      pressedFill: Color(0x29FFFFFF),
      selectionFill: Color(0x1AFFFFFF),
      controlFill: Color(0x1AFFFFFF),
      controlBorder: Color(0x26FFFFFF),
      line: Color(0x1FFFFFFF),
      textMuted: Color(0x99FFFFFF),
      textFaint: Color(0x73FFFFFF),
      accent: Color(0xFF3584E4),
      onAccent: Color(0xFFFFFFFF),
      onAccentMuted: Color(0xD9FFFFFF),
      selectionAccent: Color(0xFF3584E4),
      selectionMuted: Color(0x1AFFFFFF),
      link: Color(0xFF78AEED),
      accentSoft: Color(0x403584E4),
      selection: Color(0x4D3584E4),
      focusRing: Color(0x8078AEED),
      cardMarker: Color(0xFFF8E45C),
      cardMarkerSoft: Color(0x33F6D32D),
      ratingAgain: Color(0xFFFF7B63),
      ratingHard: Color(0xFFF8E45C),
      ratingGood: Color(0xFF8FF0A4),
      ratingEasy: Color(0xFF78AEED),
      ratingAgainSoft: Color(0x33E01B24),
      ratingHardSoft: Color(0x33F6D32D),
      ratingGoodSoft: Color(0x332EC27E),
      ratingEasySoft: Color(0x333584E4),
      danger: Color(0xFFFF7B63),
      highlight: _highlightDark,
      hintBackground: _hintDark,
      hintBorder: _hintBorder,
      hintForeground: Color(0xFFFFFFFF),
      toastBackground: Color(0xF5F0F0F2),
      toastForeground: Color(0xFF1D1D20),
      toastLink: Color(0xFF1C71D8),
      toastError: _toastError,
      markers: _markers,
      inks: _inksDark,
      starFill: _starDark,
      starEdge: _starDark,
      washes: _washesDark,
      pageSelection: _pageSelectionGnome,
      pageSelectionMuted: _pageSelectionMuted,
      pageRingMuted: _pageRingMuted,
      switchKnob: Color(0xFFFFFFFF),
      switchTrack: Color(0xFF3584E4),
    ),
  );
}
