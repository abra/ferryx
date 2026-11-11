import 'package:flutter/material.dart';

/// Colour roles beyond [ColorScheme]: surfaces of the window, fills of
/// interactive states, editor accents, ratings, hints, plates.
///
/// One instance per brightness (`AppPalette`), shared across desktops; read
/// through `context.appColors`. Soft row selections and filled accent
/// controls have separate foreground roles to keep both readable.
@immutable
class AppColorsExt extends ThemeExtension<AppColorsExt> {
  const AppColorsExt({
    required this.window,
    required this.sidebar,
    required this.windowChrome,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.hoverFill,
    required this.pressedFill,
    required this.selectionFill,
    required this.controlFill,
    required this.controlBorder,
    required this.line,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.onAccent,
    required this.onSelection,
    required this.onSelectionMuted,
    required this.selectionAccent,
    required this.selectionMuted,
    required this.cursorFill,
    required this.onCursor,
    required this.onCursorMuted,
    required this.recentHour,
    required this.recentDay,
    required this.recentBorder,
    required this.link,
    required this.accentSoft,
    required this.selection,
    required this.focusRing,
    required this.cardMarker,
    required this.cardMarkerSoft,
    required this.ratingAgain,
    required this.ratingHard,
    required this.ratingGood,
    required this.ratingEasy,
    required this.ratingAgainSoft,
    required this.ratingHardSoft,
    required this.ratingGoodSoft,
    required this.ratingEasySoft,
    required this.danger,
    required this.highlight,
    required this.hintBackground,
    required this.hintBorder,
    required this.hintForeground,
    required this.toastBackground,
    required this.toastForeground,
    required this.toastLink,
    required this.toastError,
    required this.markers,
    required this.inks,
    required this.starFill,
    required this.starEdge,
    required this.washes,
    required this.pageSelection,
    required this.pageSelectionMuted,
    required this.pageRingMuted,
    required this.switchKnob,
    required this.switchTrack,
  });

  /// The window's own background: behind the panes on Windows (Mica), the
  /// frame of dialogs and alerts.
  final Color window;

  /// The sidebar's background.
  final Color sidebar;

  /// Fill of the window's top row: pane bars, title strip, header bar.
  final Color windowChrome;

  /// Panels inside the content: the details panel, references, find bars.
  final Color surfaceRaised;

  /// Quiet fills: chips, tags, code spans, a pressed toggle track.
  final Color surfaceSunken;

  /// A control or row under the pointer.
  final Color hoverFill;

  /// A control while pressed.
  final Color pressedFill;

  /// A selected row that does not stand out with the accent: the macOS
  /// source list without focus, the Fluent and libadwaita sidebars.
  final Color selectionFill;

  /// Push buttons, text fields, key caps.
  final Color controlFill;

  /// Edge of bordered controls.
  final Color controlBorder;

  /// Hairlines and separators.
  final Color line;
  final Color textMuted;
  final Color textFaint;

  /// Filled controls and the keyboard focus indicator.
  final Color accent;

  /// Text and icons on [accent].
  final Color onAccent;

  /// Text and icons on [selectionAccent], independently of button text.
  final Color onSelection;

  /// Secondary text on [selectionAccent]: file metadata and command keys.
  final Color onSelectionMuted;

  /// A soft selection in the area with keyboard focus. Pair with
  /// [onSelection] and [onSelectionMuted], not [onAccent].
  final Color selectionAccent;

  /// Neutral selection where the focus is in another panel or window.
  final Color selectionMuted;

  /// The current file in the active panel, stronger than marked rows.
  final Color cursorFill;

  /// File name and icons on [cursorFill].
  final Color onCursor;

  /// File metadata on [cursorFill].
  final Color onCursorMuted;

  /// File rows added within the last hour and between one and 24 hours ago.
  final Color recentHour;
  final Color recentDay;

  /// The age legend's swatches, distinct even against pale window chrome.
  final Color recentBorder;

  /// Links and references in text: the accent darkened enough to read.
  final Color link;

  /// Cloze background, reference underline.
  final Color accentSoft;

  /// Selected rem in block mode.
  final Color selection;

  /// The keyboard focus ring.
  final Color focusRing;

  /// Card marker next to a rem; separator glyphs.
  final Color cardMarker;
  final Color cardMarkerSoft;
  final Color ratingAgain;
  final Color ratingHard;
  final Color ratingGood;
  final Color ratingEasy;

  /// Fills of the answer buttons; the strong rating colour is the text.
  final Color ratingAgainSoft;
  final Color ratingHardSoft;
  final Color ratingGoodSoft;
  final Color ratingEasySoft;
  final Color danger;

  /// `==highlight==` background.
  final Color highlight;

  /// Click-hint labels (⌘J).
  final Color hintBackground;
  final Color hintBorder;
  final Color hintForeground;
  final Color toastBackground;
  final Color toastForeground;
  final Color toastLink;
  final Color toastError;

  /// The PDF marker colours (yellow, blue, green, pink, orange, purple),
  /// indexed like `HighlightColor`: pastel enough to multiply over a page
  /// and keep the text readable.
  final List<Color> markers;

  /// The marker colour at [index], clamped to the palette.
  Color marker(int index) => markers[index.clamp(0, markers.length - 1)];

  /// A bookmark's star while it is on: a bright gold inside an edge that
  /// stands out from the bar (3:1 at least), as an icon must.
  final Color starFill;
  final Color starEdge;

  /// Text colours of the tag palette (red, orange, yellow, green, blue,
  /// purple), readable on the page in this brightness.
  final List<Color> inks;

  /// Backgrounds of the tag palette, in the same order.
  final List<Color> washes;

  /// The text colour of the tag colour at [index], clamped to the palette.
  Color ink(int index) => inks[index.clamp(0, inks.length - 1)];

  /// The background of the tag colour at [index], clamped to the palette.
  Color wash(int index) => washes[index.clamp(0, washes.length - 1)];

  /// Selected text on a document page. A PDF page stays white in both
  /// themes, so this is the light accent's tint in both (macOS's
  /// selected-text colour, the Fluent and libadwaita selection tint), to be
  /// painted with `BlendMode.multiply`: the glyphs keep their ink.
  final Color pageSelection;

  /// [pageSelection] while the focus is in another part of the window:
  /// grey, as macOS greys a selection without focus
  /// (unemphasizedSelectedTextBackgroundColor).
  final Color pageSelectionMuted;

  /// The keyboard's frame on a page (the line cursor, the open mark's
  /// ring, the frame being drawn), which is the accent, while the focus is
  /// in another part of the window: a grey that keeps 3:1 on the white
  /// page.
  final Color pageRingMuted;

  /// The knob on a neutral off track. The on track uses [onAccent].
  /// Fluent's outlined off track uses [textMuted] instead.
  final Color switchKnob;

  /// The track of a switch that is on, paired with [onAccent].
  final Color switchTrack;

  /// The palette is fixed per brightness; another one is a new
  /// palette, not a copy.
  @override
  AppColorsExt copyWith() => this;

  @override
  AppColorsExt lerp(AppColorsExt? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColorsExt(
      window: mix(window, other.window),
      sidebar: mix(sidebar, other.sidebar),
      windowChrome: mix(windowChrome, other.windowChrome),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      surfaceSunken: mix(surfaceSunken, other.surfaceSunken),
      hoverFill: mix(hoverFill, other.hoverFill),
      pressedFill: mix(pressedFill, other.pressedFill),
      selectionFill: mix(selectionFill, other.selectionFill),
      controlFill: mix(controlFill, other.controlFill),
      controlBorder: mix(controlBorder, other.controlBorder),
      line: mix(line, other.line),
      textMuted: mix(textMuted, other.textMuted),
      textFaint: mix(textFaint, other.textFaint),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      onSelection: mix(onSelection, other.onSelection),
      onSelectionMuted: mix(onSelectionMuted, other.onSelectionMuted),
      selectionAccent: mix(selectionAccent, other.selectionAccent),
      selectionMuted: mix(selectionMuted, other.selectionMuted),
      cursorFill: mix(cursorFill, other.cursorFill),
      onCursor: mix(onCursor, other.onCursor),
      onCursorMuted: mix(onCursorMuted, other.onCursorMuted),
      recentHour: mix(recentHour, other.recentHour),
      recentDay: mix(recentDay, other.recentDay),
      recentBorder: mix(recentBorder, other.recentBorder),
      link: mix(link, other.link),
      accentSoft: mix(accentSoft, other.accentSoft),
      selection: mix(selection, other.selection),
      focusRing: mix(focusRing, other.focusRing),
      cardMarker: mix(cardMarker, other.cardMarker),
      cardMarkerSoft: mix(cardMarkerSoft, other.cardMarkerSoft),
      ratingAgain: mix(ratingAgain, other.ratingAgain),
      ratingHard: mix(ratingHard, other.ratingHard),
      ratingGood: mix(ratingGood, other.ratingGood),
      ratingEasy: mix(ratingEasy, other.ratingEasy),
      ratingAgainSoft: mix(ratingAgainSoft, other.ratingAgainSoft),
      ratingHardSoft: mix(ratingHardSoft, other.ratingHardSoft),
      ratingGoodSoft: mix(ratingGoodSoft, other.ratingGoodSoft),
      ratingEasySoft: mix(ratingEasySoft, other.ratingEasySoft),
      danger: mix(danger, other.danger),
      highlight: mix(highlight, other.highlight),
      hintBackground: mix(hintBackground, other.hintBackground),
      hintBorder: mix(hintBorder, other.hintBorder),
      hintForeground: mix(hintForeground, other.hintForeground),
      toastBackground: mix(toastBackground, other.toastBackground),
      toastForeground: mix(toastForeground, other.toastForeground),
      toastLink: mix(toastLink, other.toastLink),
      toastError: mix(toastError, other.toastError),
      markers: [
        for (var i = 0; i < markers.length; i++)
          mix(markers[i], other.marker(i)),
      ],
      inks: [for (var i = 0; i < inks.length; i++) mix(inks[i], other.inks[i])],
      starFill: mix(starFill, other.starFill),
      starEdge: mix(starEdge, other.starEdge),
      washes: [
        for (var i = 0; i < washes.length; i++) mix(washes[i], other.washes[i]),
      ],
      pageSelection: mix(pageSelection, other.pageSelection),
      pageSelectionMuted: mix(pageSelectionMuted, other.pageSelectionMuted),
      pageRingMuted: mix(pageRingMuted, other.pageRingMuted),
      switchKnob: mix(switchKnob, other.switchKnob),
      switchTrack: mix(switchTrack, other.switchTrack),
    );
  }
}
