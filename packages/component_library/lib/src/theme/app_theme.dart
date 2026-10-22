import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_platform_style.dart';
import 'extensions/app_colors_ext.dart';
import 'extensions/app_metrics.dart';
import 'extensions/app_terminal_colors.dart';
import 'fluent_borders.dart';
import 'hairlines.dart';
import 'tokens/app_palette.dart';
import 'tokens/app_spacing.dart';
import '../focus_ring.dart';

/// Central theme assembly: one theme per platform style and brightness,
/// built on first use and kept, so `ThemeData` identity stays stable across
/// rebuilds and a switch of brightness costs nothing after the first.
///
/// Material components are restyled to the platform's own controls: no ink
/// splashes and an arrow cursor on buttons anywhere (desktops show a hand
/// only on links), AppKit push buttons on macOS, Fluent's accent and
/// standard buttons with their elevation edge on Windows, libadwaita's
/// suggested and flat buttons on GNOME.
abstract final class AppTheme {
  static final _themes =
      <(AppPlatformStyle, MacGeneration, Brightness), ThemeData>{};

  /// The theme of [style] at [brightness]; on macOS, of the system's
  /// [generation] (the other styles have one).
  static ThemeData of(
    AppPlatformStyle style,
    Brightness brightness, {
    MacGeneration generation = MacGeneration.sequoia,
  }) {
    final release = style == AppPlatformStyle.macos
        ? generation
        : MacGeneration.sequoia;
    return _themes[(style, release, brightness)] ??= _build(
      style,
      brightness,
      release,
    );
  }

  /// The light theme of [style], by default the running platform's.
  static ThemeData light([AppPlatformStyle? style]) =>
      of(style ?? AppPlatformStyle.current, Brightness.light);

  /// The dark theme of [style], by default the running platform's.
  static ThemeData dark([AppPlatformStyle? style]) =>
      of(style ?? AppPlatformStyle.current, Brightness.dark);

  static ThemeData _build(
    AppPlatformStyle style,
    Brightness brightness,
    MacGeneration generation,
  ) {
    final isDark = brightness == Brightness.dark;
    final palette = AppPalette.of(style, brightness);
    final ext = palette.colors;
    final metrics = AppMetrics.of(style, generation: generation);
    final type = metrics.typeScale;
    final surface = palette.surface;
    final foreground = palette.onSurface;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: ext.accent,
      onPrimary: ext.onAccent,
      primaryContainer: ext.accentSoft,
      onPrimaryContainer: foreground,
      secondary: ext.surfaceSunken,
      onSecondary: foreground,
      error: ext.danger,
      onError: Colors.white,
      surface: surface,
      onSurface: foreground,
      onSurfaceVariant: ext.textMuted,
      surfaceContainerLowest: surface,
      surfaceContainerLow: ext.surfaceRaised,
      surfaceContainer: ext.surfaceRaised,
      surfaceContainerHigh: ext.window,
      surfaceContainerHighest: ext.window,
      outline: ext.line,
      outlineVariant: ext.line,
      inverseSurface: ext.toastBackground,
      onInverseSurface: ext.toastForeground,
      inversePrimary: ext.toastLink,
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );

    final textTheme = type.textTheme.apply(
      bodyColor: foreground,
      displayColor: foreground,
    );
    final controls = _Controls(style, ext, metrics, textTheme, foreground);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      platform: style.targetPlatform,
      colorScheme: colorScheme,
      textTheme: textTheme,
      fontFamilyFallback: type.sansFallback,
      scaffoldBackgroundColor: metrics.contentLayer ? ext.window : surface,
      canvasColor: surface,
      dividerColor: ext.line,
      hoverColor: ext.hoverFill,
      focusColor: Colors.transparent,
      highlightColor: ext.pressedFill,
      splashColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      extensions: [
        ext,
        metrics,
        AppTerminalColors.forBrightness(brightness),
      ],
      iconTheme: IconThemeData(size: 16, color: ext.textMuted),
      dividerTheme: DividerThemeData(color: ext.line, thickness: 1, space: 1),
      textSelectionTheme: TextSelectionThemeData(
        // macOS draws the caret in the accent since Sonoma.
        cursorColor: style == AppPlatformStyle.macos ? ext.accent : foreground,
        selectionColor: switch (style) {
          AppPlatformStyle.macos =>
            isDark ? const Color(0xFF3F638B) : const Color(0xFFB3D7FF),
          AppPlatformStyle.windows => ext.accent.withValues(alpha: 0.35),
          AppPlatformStyle.gnome => ext.accent.withValues(alpha: 0.3),
        },
        selectionHandleColor: ext.accent,
      ),
      inputDecorationTheme: controls.input(isDark),
      filledButtonTheme: FilledButtonThemeData(style: controls.filled()),
      outlinedButtonTheme: OutlinedButtonThemeData(style: controls.outlined()),
      textButtonTheme: TextButtonThemeData(style: controls.text()),
      iconButtonTheme: IconButtonThemeData(style: controls.icon()),
      tooltipTheme: controls.tooltip(isDark),
      dialogTheme: DialogThemeData(
        backgroundColor: style == AppPlatformStyle.macos ? ext.window : surface,
        surfaceTintColor: Colors.transparent,
        elevation: 16,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.6 : 0.35),
        // A sheet or alert does not dim the window behind it on macOS.
        barrierColor: Colors.black.withValues(
          alpha: style == AppPlatformStyle.macos ? 0 : 0.3,
        ),
        shape: AppRoundedRectangleBorder(
          borderRadius: BorderRadius.circular(metrics.radius.dialog),
          side: BorderSide(color: ext.line),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: ext.textMuted),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.6 : 0.3),
        shape: AppRoundedRectangleBorder(
          borderRadius: BorderRadius.circular(metrics.radius.menu),
          side: BorderSide(color: ext.line),
        ),
        textStyle: textTheme.bodyMedium,
        menuPadding: const EdgeInsets.all(5),
      ),
      scrollbarTheme: controls.scrollbar(isDark),
      sliderTheme: controls.slider(isDark),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: ext.accent,
        linearTrackColor: ext.pressedFill,
        circularTrackColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        shape: AppRoundedRectangleBorder(
          borderRadius: BorderRadius.circular(metrics.radius.row),
        ),
        mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.basic),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ext.toastBackground,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: ext.toastForeground,
        ),
        actionTextColor: ext.toastLink,
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        // libadwaita's toasts are pills; the others are plates with a
        // hairline, as the plate follows the appearance.
        shape: style == AppPlatformStyle.gnome
            ? const AppStadiumBorder()
            : AppRoundedRectangleBorder(
                borderRadius: BorderRadius.circular(metrics.radius.card),
                side: BorderSide(color: ext.line),
              ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.macOS: _NoTransitionsBuilder(),
          TargetPlatform.windows: _NoTransitionsBuilder(),
          TargetPlatform.linux: _NoTransitionsBuilder(),
          TargetPlatform.android: _NoTransitionsBuilder(),
          TargetPlatform.iOS: _NoTransitionsBuilder(),
          TargetPlatform.fuchsia: _NoTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Builds the control themes of one style.
class _Controls {
  _Controls(this.style, this.ext, this.metrics, this.ramp, this.foreground);

  final AppPlatformStyle style;
  final AppColorsExt ext;
  final AppMetrics metrics;
  final TextTheme ramp;
  final Color foreground;

  BorderRadius get _radius => BorderRadius.circular(metrics.radius.control);

  // As a field's: the label's line plus this is the platform's control
  // height, and both grow alike with the text size, so a button beside a
  // field keeps its height.
  EdgeInsets get _padding {
    final label = ramp.labelLarge!;
    return EdgeInsets.symmetric(
      horizontal: style == AppPlatformStyle.gnome ? 16 : 12,
      vertical: math.max(
        0,
        (metrics.controlHeight - label.fontSize! * label.height!) / 2,
      ),
    );
  }

  OutlinedBorder _shape({bool elevated = false}) =>
      elevated && style == AppPlatformStyle.windows
      ? FluentElevationBorder(
          borderRadius: _radius,
          top: ext.line,
          bottom: ext.controlBorder,
        )
      : AppRoundedRectangleBorder(borderRadius: _radius);

  static WidgetStateProperty<T> _states<T>({
    required T normal,
    T? hovered,
    T? pressed,
    T? disabled,
  }) => WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.disabled)) return disabled ?? normal;
    if (states.contains(WidgetState.pressed)) return pressed ?? normal;
    if (states.contains(WidgetState.hovered)) return hovered ?? normal;
    return normal;
  });

  ButtonStyle _base({
    required Color background,
    required Color foreground,
    required OutlinedBorder shape,
    Color? hover,
    Color? pressed,
    Color? disabledBackground,
    BorderSide? side,
  }) => ButtonStyle(
    backgroundColor: _states(
      normal: background,
      disabled: disabledBackground ?? background,
    ),
    foregroundColor: _states(normal: foreground, disabled: ext.textFaint),
    overlayColor: _states(
      normal: Colors.transparent,
      hovered: hover ?? Colors.transparent,
      pressed: pressed ?? Colors.transparent,
    ),
    side: side == null ? null : WidgetStatePropertyAll(side),
    shape: WidgetStatePropertyAll(shape),
    minimumSize: WidgetStatePropertyAll(Size(0, metrics.controlHeight)),
    padding: WidgetStatePropertyAll(_padding),
    textStyle: WidgetStatePropertyAll(ramp.labelLarge),
    elevation: const WidgetStatePropertyAll(0),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.basic),
    splashFactory: NoSplash.splashFactory,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.standard,
    animationDuration: Duration.zero,
    // The keyboard focus ring, outside the button, while the keys are in
    // use (the painter draws nothing after a click).
    backgroundBuilder: (context, states, child) => CustomPaint(
      foregroundPainter: states.contains(WidgetState.focused)
          ? FocusRingPainter.of(context, radius: metrics.radius.control)
          : null,
      child: child,
    ),
  );

  /// The default (macOS), accent (Windows) or suggested (GNOME) button.
  ButtonStyle filled() => _base(
    background: ext.accent,
    foreground: ext.onAccent,
    shape: _shape(),
    hover: switch (style) {
      AppPlatformStyle.macos => null,
      _ => ext.onAccent.withValues(alpha: 0.1),
    },
    pressed: Colors.black.withValues(alpha: 0.15),
    disabledBackground: ext.controlFill,
  );

  /// The regular push button: bordered white on macOS, the standard
  /// button with its elevation edge on Windows, a filled flat button on
  /// GNOME.
  ButtonStyle outlined() => _base(
    background: ext.controlFill,
    foreground: foreground,
    shape: _shape(elevated: true),
    side: switch (style) {
      AppPlatformStyle.macos => BorderSide(color: ext.controlBorder),
      _ => BorderSide.none,
    },
    hover: switch (style) {
      AppPlatformStyle.macos => null,
      _ => ext.hoverFill,
    },
    pressed: ext.pressedFill,
  );

  /// Borderless: toolbar text buttons, links to actions.
  ButtonStyle text() => _base(
    background: Colors.transparent,
    foreground: ext.textMuted,
    shape: _shape(),
    hover: ext.hoverFill,
    pressed: ext.pressedFill,
  );

  ButtonStyle icon() => text().copyWith(
    minimumSize: WidgetStatePropertyAll(metrics.iconButtonSize),
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    iconSize: const WidgetStatePropertyAll(16),
  );

  InputDecorationThemeData input(bool isDark) {
    final radius = _radius;
    // The field's text line plus this padding is the platform's control
    // height, so a field lines up with the buttons beside it. (A minimum
    // height would not do: a dense field draws its border round the
    // content and leaves the rest below it.)
    final field = ramp.bodyLarge!;
    final vertical =
        (metrics.controlHeight - field.fontSize! * field.height!) / 2;
    final padding = EdgeInsets.symmetric(
      horizontal: style == AppPlatformStyle.macos ? 7 : 10,
      vertical: vertical,
    );
    final InputBorder enabled;
    final InputBorder focused;
    final InputBorder error;
    switch (style) {
      case AppPlatformStyle.macos:
        enabled = AppOutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: ext.controlBorder),
        );
        // The bezel stays; the focus ring is the accent halo outside it,
        // on any focus, as an NSTextField draws it.
        focused = AppOutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: ext.controlBorder),
          halo: BorderSide(
            color: ext.focusRing,
            width: metrics.focusRingWidth,
          ),
        );
        error = AppOutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: ext.danger),
          halo: BorderSide(
            color: ext.danger.withValues(alpha: 0.5),
            width: metrics.focusRingWidth,
          ),
        );
      case AppPlatformStyle.windows:
        enabled = FluentInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: ext.line),
          bottom: BorderSide(color: ext.textFaint),
        );
        focused = FluentInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: ext.line),
          bottom: BorderSide(color: ext.accent, width: 2),
        );
        error = FluentInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: ext.line),
          bottom: BorderSide(color: ext.danger, width: 2),
        );
      case AppPlatformStyle.gnome:
        enabled = AppOutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide.none,
        );
        focused = AppOutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: ext.focusRing, width: 2),
        );
        error = AppOutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: ext.danger, width: 2),
        );
    }
    return InputDecorationThemeData(
      isDense: true,
      filled: true,
      fillColor: switch (style) {
        AppPlatformStyle.macos =>
          isDark ? const Color(0x0DFFFFFF) : const Color(0xFFFFFFFF),
        _ => ext.controlFill,
      },
      hoverColor: Colors.transparent,
      contentPadding: padding,
      // The padding already is the platform's; the desktop's compact
      // density would take 4 px off each side again.
      visualDensity: VisualDensity.standard,
      // Material's 48 px icon boxes would make a search field a touch
      // target; a square of the control's height keeps it a control.
      prefixIconConstraints: BoxConstraints(
        minWidth: metrics.controlHeight,
        minHeight: 0,
      ),
      suffixIconConstraints: BoxConstraints(
        minWidth: metrics.controlHeight,
        minHeight: 0,
      ),
      hintStyle: ramp.bodyMedium?.copyWith(color: ext.textFaint),
      labelStyle: ramp.bodyMedium?.copyWith(color: ext.textMuted),
      border: enabled,
      enabledBorder: enabled,
      disabledBorder: enabled,
      focusedBorder: focused,
      errorBorder: error,
      focusedErrorBorder: error,
    );
  }

  TooltipThemeData tooltip(bool isDark) {
    final Color background;
    final Color ink;
    final BoxBorder? border;
    final double radius;
    switch (style) {
      case AppPlatformStyle.macos:
        background = isDark ? const Color(0xF23A3A3C) : const Color(0xF7F6F6F6);
        ink = foreground;
        border = AppBorder.all(color: ext.line);
        radius = 5;
      case AppPlatformStyle.windows:
        background = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF9F9F9);
        ink = foreground;
        border = AppBorder.all(color: ext.line);
        radius = 4;
      case AppPlatformStyle.gnome:
        // Adwaita's tooltips are dark plates in both styles.
        background = const Color(0xE6000000);
        ink = Colors.white;
        border = null;
        radius = 9;
    }
    return TooltipThemeData(
      // WinUI: twice the system's hover time (400 ms); GTK: 500 ms.
      waitDuration: Duration(
        milliseconds: switch (style) {
          AppPlatformStyle.macos => 700,
          AppPlatformStyle.windows => 800,
          AppPlatformStyle.gnome => 500,
        },
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
        border: border,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.14),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      // macOS 11 pt; Fluent's caption 12; GTK the body face.
      textStyle: switch (style) {
        AppPlatformStyle.macos => ramp.bodySmall,
        AppPlatformStyle.windows => ramp.labelMedium?.weight400,
        AppPlatformStyle.gnome => ramp.bodyMedium,
      }?.copyWith(color: ink),
      // ToolTip 9,6,9,8; Adwaita 10 by 6.
      padding: switch (style) {
        AppPlatformStyle.macos => const EdgeInsets.symmetric(
          horizontal: 7,
          vertical: 3,
        ),
        AppPlatformStyle.windows => const EdgeInsets.fromLTRB(9, 6, 9, 8),
        AppPlatformStyle.gnome => const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
      },
      // Off the window's sides, as the platforms keep their tooltips.
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    );
  }

  /// Overlay scrollbars on all three: they show while scrolling and under
  /// the pointer, and grow when hovered.
  ScrollbarThemeData scrollbar(bool isDark) {
    final (rest, hover, margin) = switch (style) {
      AppPlatformStyle.macos => (7.0, 10.0, 2.0),
      AppPlatformStyle.windows => (3.0, 8.0, 2.0),
      AppPlatformStyle.gnome => (3.0, 8.0, 3.0),
    };
    final thumb = foreground.withValues(alpha: isDark ? 0.4 : 0.35);
    return ScrollbarThemeData(
      thickness: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered) ? hover : rest,
      ),
      radius: const Radius.circular(8),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.dragged)
            ? foreground.withValues(alpha: isDark ? 0.55 : 0.5)
            : thumb,
      ),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
      trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
      crossAxisMargin: margin,
      mainAxisMargin: margin,
      minThumbLength: 32,
      interactive: true,
    );
  }

  SliderThemeData slider(bool isDark) => SliderThemeData(
    trackHeight: 4,
    activeTrackColor: ext.accent,
    // The groove the knob runs in, as the off track of a switch: AppKit
    // and libadwaita sink it a step, Fluent's rail is its strong fill.
    inactiveTrackColor: style == AppPlatformStyle.windows
        ? ext.textFaint
        : ext.pressedFill,
    thumbColor: style == AppPlatformStyle.gnome || !isDark
        ? Colors.white
        : const Color(0xFFDDDDDD),
    overlayColor: Colors.transparent,
    overlayShape: SliderComponentShape.noOverlay,
    thumbShape: _ThumbShape(
      radius: switch (style) {
        AppPlatformStyle.macos => 9,
        AppPlatformStyle.windows => 10,
        AppPlatformStyle.gnome => 10,
      },
      // Fluent's thumb carries an accent dot.
      core: style == AppPlatformStyle.windows ? ext.accent : null,
      edge: ext.controlBorder,
    ),
    trackShape: const _FullWidthTrackShape(),
    showValueIndicator: ShowValueIndicator.never,
    mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.basic),
  );
}

extension on TextStyle {
  TextStyle get weight400 => copyWith(
    fontWeight: FontWeight.w400,
    fontVariations: const [FontVariation('wght', 400)],
  );
}

/// A slider's bar from edge to edge of its box, as the platforms draw it,
/// so it lines up with the fields and buttons of its column; the knob
/// still travels the inset part, its edge at the box's edge at either end.
class _FullWidthTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const _FullWidthTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final travel = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final left = offset.dx;
    final right = offset.dx + parentBox.size.width;
    final end = Radius.circular(travel.height / 2);
    Color colour(Color? disabled, Color? enabled) =>
        ColorTween(begin: disabled, end: enabled).evaluate(enableAnimation)!;
    final active = colour(
      sliderTheme.disabledActiveTrackColor,
      sliderTheme.activeTrackColor,
    );
    final inactive = colour(
      sliderTheme.disabledInactiveTrackColor,
      sliderTheme.inactiveTrackColor,
    );
    final ltr = textDirection == TextDirection.ltr;
    final canvas = context.canvas;
    canvas
      ..drawRRect(
        RRect.fromLTRBAndCorners(
          left,
          travel.top,
          thumbCenter.dx,
          travel.bottom,
          topLeft: end,
          bottomLeft: end,
        ),
        Paint()..color = ltr ? active : inactive,
      )
      ..drawRRect(
        RRect.fromLTRBAndCorners(
          thumbCenter.dx,
          travel.top,
          right,
          travel.bottom,
          topRight: end,
          bottomRight: end,
        ),
        Paint()..color = ltr ? inactive : active,
      );
  }
}

/// A round slider knob with a hairline edge and a soft shadow, and the
/// accent dot Fluent puts in it.
class _ThumbShape extends SliderComponentShape {
  const _ThumbShape({required this.radius, required this.edge, this.core});

  final double radius;
  final Color edge;
  final Color? core;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(
      center.translate(0, 0.5),
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.drawCircle(center, radius, Paint()..color = sliderTheme.thumbColor!);
    canvas.drawCircle(
      center,
      radius - 0.5,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke,
    );
    final dot = core;
    if (dot != null) {
      canvas.drawCircle(
        center,
        radius * (activationAnimation.value > 0 ? 0.62 : 0.5),
        Paint()..color = dot,
      );
    }
  }
}

/// Desktop apps switch screens instantly; no slide or fade.
class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
