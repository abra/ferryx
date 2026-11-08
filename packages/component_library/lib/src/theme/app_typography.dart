import 'package:flutter/material.dart';

import 'app_platform_style.dart';

/// Type of one platform style: the system's interface face, the platform's
/// type ramp for the interface and the editor's metrics.
///
/// Every face ends its fallback list with the bundled Inter (sans) or Geist
/// Mono (mono): they cover a desktop that lacks the system face and are what
/// widget tests render with, since tests see no system fonts.
@immutable
class AppTypeScale {
  const AppTypeScale({
    required this.sansFamily,
    required this.sansFallback,
    required this.displayFamily,
    required this.monoFamily,
    required this.monoFallback,
    required this.textTheme,
    required this.editorTitle,
    required this.editorBody,
    required this.editorHeading1,
    required this.editorHeading2,
    required this.editorHeading3,
    required this.editorCode,
    required this.mono,
    required this.keyCap,
  });

  final String sansFamily;
  final List<String> sansFallback;

  /// The optical size for large text where the platform has one (Segoe UI
  /// Variable Display); the sans family elsewhere.
  final String displayFamily;
  final String monoFamily;
  final List<String> monoFallback;

  /// The interface ramp, without colour.
  final TextTheme textTheme;

  /// Document title.
  final TextStyle editorTitle;

  /// A rem's text.
  final TextStyle editorBody;
  final TextStyle editorHeading1;
  final TextStyle editorHeading2;
  final TextStyle editorHeading3;

  /// Code block: monospace on the body's line, so bullets stay aligned.
  final TextStyle editorCode;

  /// Paths, chord tables, code in the interface.
  final TextStyle mono;

  /// Key labels: in the system face, as the platforms show them in menus.
  final TextStyle keyCap;
}

/// The type ramps of the three platform styles.
///
/// - macOS: SF Pro (`.AppleSystemUIFont`, which keeps the optical sizes) on
///   AppKit's ramp: 13 pt body, 11 pt small text, 13 pt bold headlines.
/// - Windows 11: Segoe UI Variable on the Fluent ramp: 14 px body, 12 px
///   caption, 20/28 px subtitles and titles in semibold.
/// - GNOME: Adwaita Sans (Cantarell before GNOME 48) on libadwaita's ramp:
///   11 pt (14.67 px) body, 9 pt captions, bold headings, extra-bold titles.
///
/// The editor reads at 15 px on a 22 px line on every platform, a step
/// above the interface text as in native note-taking apps. `bodyLarge` is
/// the body too: Material's text fields take it, and native fields are set
/// in the body size. Monospace sits on the body's line, so a path field or
/// a code chip lines up with the text and controls beside it.
///
/// Every style sets `height` with the leading split evenly, as CSS does, so
/// text centres in its line box whatever the face's ascent and descent. The
/// bundled faces are variable fonts: weights also set the `wght` axis
/// (harmless on static faces), so use [AppFontWeightX] instead of
/// `copyWith(fontWeight:)`.
abstract final class AppTypography {
  static const String bundledSans = 'Inter';
  static const String bundledMono = 'Geist Mono';

  /// Shared by the terminal's cells and its font preview in Settings.
  static const double terminalLineHeightFactor = 1.2;

  /// The `wght` axis setting for [weight].
  static List<FontVariation> variations(FontWeight weight) => [
    FontVariation('wght', weight.value.toDouble()),
  ];

  static final _scales = <AppPlatformStyle, AppTypeScale>{};

  /// The type of [style]; built once.
  static AppTypeScale of(AppPlatformStyle style) =>
      _scales[style] ??= switch (style) {
        AppPlatformStyle.macos => _macos(),
        AppPlatformStyle.windows => _windows(),
        AppPlatformStyle.gnome => _gnome(),
      };

  static AppTypeScale _macos() {
    const sans = '.AppleSystemUIFont';
    const sansFallback = [bundledSans];
    const mono = '.AppleSystemUIFontMonospaced';
    const monoFallback = ['Menlo', bundledMono];
    TextStyle s(double size, double line, FontWeight weight, [double ls = 0]) =>
        _style(sans, sansFallback, size, line, weight, ls);
    return AppTypeScale(
      sansFamily: sans,
      sansFallback: sansFallback,
      displayFamily: sans,
      monoFamily: mono,
      monoFallback: monoFallback,
      textTheme: TextTheme(
        displayLarge: s(28, 34, FontWeight.w600, -0.3),
        displayMedium: s(26, 32, FontWeight.w700, -0.3),
        displaySmall: s(22, 28, FontWeight.w700, -0.2),
        headlineLarge: s(26, 32, FontWeight.w700, -0.3),
        headlineMedium: s(20, 26, FontWeight.w600, -0.2),
        headlineSmall: s(17, 22, FontWeight.w600),
        titleLarge: s(17, 22, FontWeight.w600),
        titleMedium: s(15, 20, FontWeight.w600),
        titleSmall: s(13, 16, FontWeight.w700),
        // Material's text field style: the platforms' fields use the body.
        bodyLarge: s(13, 16, FontWeight.w400),
        bodyMedium: s(13, 16, FontWeight.w400),
        bodySmall: s(11, 14, FontWeight.w400),
        labelLarge: s(13, 16, FontWeight.w400),
        labelMedium: s(11, 14, FontWeight.w500),
        labelSmall: s(11, 14, FontWeight.w600),
      ),
      editorTitle: s(26, 32, FontWeight.w700, -0.3),
      editorBody: s(15, 22, FontWeight.w400),
      editorHeading1: s(22, 28, FontWeight.w700, -0.2),
      editorHeading2: s(18, 24, FontWeight.w600),
      editorHeading3: s(16, 22, FontWeight.w600),
      editorCode: _style(mono, monoFallback, 13, 22, FontWeight.w400),
      mono: _style(mono, monoFallback, 12, 16, FontWeight.w400),
      keyCap: s(11, 14, FontWeight.w500),
    );
  }

  static AppTypeScale _windows() {
    const sans = 'Segoe UI Variable Text';
    const display = 'Segoe UI Variable Display';
    const sansFallback = ['Segoe UI', bundledSans];
    const mono = 'Cascadia Mono';
    const monoFallback = ['Consolas', bundledMono];
    TextStyle s(double size, double line, FontWeight weight) =>
        _style(sans, sansFallback, size, line, weight);
    TextStyle d(double size, double line, FontWeight weight) =>
        _style(display, sansFallback, size, line, weight);
    return AppTypeScale(
      sansFamily: sans,
      sansFallback: sansFallback,
      displayFamily: display,
      monoFamily: mono,
      monoFallback: monoFallback,
      textTheme: TextTheme(
        displayLarge: d(32, 40, FontWeight.w600),
        displayMedium: d(28, 36, FontWeight.w600),
        displaySmall: d(24, 32, FontWeight.w600),
        headlineLarge: d(28, 36, FontWeight.w600),
        headlineMedium: d(20, 28, FontWeight.w600),
        headlineSmall: d(20, 28, FontWeight.w600),
        titleLarge: d(20, 28, FontWeight.w600),
        titleMedium: s(16, 22, FontWeight.w600),
        titleSmall: s(14, 20, FontWeight.w600),
        bodyLarge: s(14, 20, FontWeight.w400),
        bodyMedium: s(14, 20, FontWeight.w400),
        bodySmall: s(12, 16, FontWeight.w400),
        labelLarge: s(14, 20, FontWeight.w400),
        labelMedium: s(12, 16, FontWeight.w400),
        labelSmall: s(12, 16, FontWeight.w600),
      ),
      editorTitle: d(28, 36, FontWeight.w600),
      editorBody: s(15, 22, FontWeight.w400),
      editorHeading1: d(22, 30, FontWeight.w600),
      editorHeading2: s(18, 26, FontWeight.w600),
      editorHeading3: s(16, 22, FontWeight.w600),
      editorCode: _style(mono, monoFallback, 13, 22, FontWeight.w400),
      mono: _style(mono, monoFallback, 13, 20, FontWeight.w400),
      keyCap: s(12, 16, FontWeight.w400),
    );
  }

  static AppTypeScale _gnome() {
    const sans = 'Adwaita Sans';
    const sansFallback = ['Cantarell', 'Ubuntu', 'Noto Sans', bundledSans];
    const mono = 'Adwaita Mono';
    const monoFallback = [
      'Source Code Pro',
      'Ubuntu Mono',
      'DejaVu Sans Mono',
      bundledMono,
    ];
    // 11 pt at 96 dpi: libadwaita's body; captions are 9 pt.
    const body = 14.67;
    TextStyle s(double size, double line, FontWeight weight) =>
        _style(sans, sansFallback, size, line, weight);
    return AppTypeScale(
      sansFamily: sans,
      sansFallback: sansFallback,
      displayFamily: sans,
      monoFamily: mono,
      monoFallback: monoFallback,
      textTheme: TextTheme(
        displayLarge: s(30, 36, FontWeight.w700),
        displayMedium: s(26.67, 32, FontWeight.w800),
        displaySmall: s(24, 30, FontWeight.w800),
        headlineLarge: s(26.67, 32, FontWeight.w800),
        headlineMedium: s(20, 26, FontWeight.w700),
        headlineSmall: s(20, 26, FontWeight.w800),
        titleLarge: s(20, 26, FontWeight.w800),
        titleMedium: s(17.33, 24, FontWeight.w700),
        titleSmall: s(body, 20, FontWeight.w700),
        bodyLarge: s(body, 20, FontWeight.w400),
        bodyMedium: s(body, 20, FontWeight.w400),
        bodySmall: s(12, 16, FontWeight.w400),
        labelLarge: s(body, 20, FontWeight.w700),
        labelMedium: s(12, 16, FontWeight.w700),
        labelSmall: s(12, 16, FontWeight.w700),
      ),
      editorTitle: s(26.67, 32, FontWeight.w800),
      editorBody: s(15, 22, FontWeight.w400),
      editorHeading1: s(22, 28, FontWeight.w800),
      editorHeading2: s(18, 24, FontWeight.w700),
      editorHeading3: s(16, 22, FontWeight.w700),
      editorCode: _style(mono, monoFallback, 13, 22, FontWeight.w400),
      mono: _style(mono, monoFallback, 13, 20, FontWeight.w400),
      keyCap: s(12, 16, FontWeight.w400),
    );
  }

  static TextStyle _style(
    String family,
    List<String> fallback,
    double size,
    double line,
    FontWeight weight, [
    double letterSpacing = 0,
  ]) => TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: size,
    height: line / size,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: weight,
    fontVariations: variations(weight),
    // Always set: Material's own ramp under the theme would otherwise lend
    // its web tracking (0.25 on body text) to the system face.
    letterSpacing: letterSpacing,
  );
}

/// Sets a weight on a style together with the matching `wght` axis.
extension AppFontWeightX on TextStyle {
  TextStyle weight(FontWeight weight) => copyWith(
    fontWeight: weight,
    fontVariations: AppTypography.variations(weight),
  );
}
