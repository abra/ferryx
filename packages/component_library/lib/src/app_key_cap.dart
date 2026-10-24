import 'package:flutter/material.dart';

import 'app_icons.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_icon_size.dart';
import 'theme/tokens/app_spacing.dart';
import 'theme/hairlines.dart';

/// Symbols of a chord label that are drawn as icons: the bundled faces have
/// no glyphs for them, and a fallback font shifts the baseline.
const _keySymbols = <String, IconData>{
  '⌘': AppIcons.keyCommand,
  '⇧': AppIcons.keyShift,
  '⌥': AppIcons.keyOption,
  '⌃': AppIcons.keyControl,
  '↩': AppIcons.keyEnter,
  '⌫': AppIcons.keyBackspace,
  '⇥': AppIcons.keyTab,
  '↑': AppIcons.keyUp,
  '↓': AppIcons.keyDown,
  '←': AppIcons.keyLeft,
  '→': AppIcons.keyRight,
};

/// The label split into runs of text and icon symbols, one line of [style]
/// high whatever it holds and with the symbols sized with the text, so a
/// cap of arrows stands as tall as a cap of letters at every text size.
class _KeyCapRow extends StatelessWidget {
  const _KeyCapRow(this.label, {required this.style, required this.color});

  final String label;
  final TextStyle style;

  /// The symbols' colour, the text's.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final iconSize = scaler.scale(AppIconSize.xs);
    final out = <Widget>[];
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isEmpty) return;
      out.add(
        Text(buffer.toString(), style: style, maxLines: 1, softWrap: false),
      );
      buffer.clear();
    }

    for (final rune in label.runes) {
      final char = String.fromCharCode(rune);
      final icon = _keySymbols[char];
      if (icon == null) {
        buffer.write(char);
        continue;
      }
      flush();
      out.add(Icon(icon, size: iconSize, color: color));
    }
    flush();
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: scaler.scale(style.fontSize!) * (style.height ?? 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: out),
    );
  }
}

/// A keyboard key cap, e.g. `⌘K`: a small raised key with a deeper bottom
/// edge, in the platform's interface face.
///
/// [emphasized] draws it on the accent, for "press a shortcut" prompts and
/// the key just pressed; [muted] faint, for a key that does nothing now.
class AppKeyCap extends StatelessWidget {
  const AppKeyCap(
    this.label, {
    this.emphasized = false,
    this.muted = false,
    this.typed = false,
    super.key,
  });

  final String label;
  final bool emphasized;
  final bool muted;

  /// The label is text one types (Vim's `l`, `gg`, `/`), not a key's
  /// name: in the monospace face, where `l`, `I` and `1` tell apart.
  final bool typed;

  /// The cap's face: the key caps' own, or the monospace one at its size
  /// and line for [typed] text, so the caps stand alike.
  TextStyle _faceOf(BuildContext context) {
    final caps = context.metrics.typeScale.keyCap;
    return typed
        ? context.metrics.typeScale.mono.copyWith(
            fontSize: caps.fontSize,
            height: caps.height,
          )
        : caps;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final edge = emphasized
        ? colors.accent
        : muted
        ? colors.line
        : colors.controlBorder;
    final ink = emphasized
        ? colors.accent
        : muted
        ? colors.textFaint
        : colors.textMuted;
    final side = BorderSide(color: edge);
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: colors.controlFill,
          borderRadius: BorderRadius.circular(context.metrics.radius.chip),
          border: AppBorder(
            top: side,
            left: side,
            right: side,
            bottom: side.copyWith(width: 2),
          ),
        ),
        child: _KeyCapRow(
          label,
          style: _faceOf(context).copyWith(color: ink),
          color: ink,
        ),
      ),
    );
  }
}

/// A shortcut as menus show it on every desktop: plain secondary text after
/// the item (`⌘K`, `Ctrl+K`), no key caps.
class AppShortcutLabel extends StatelessWidget {
  const AppShortcutLabel(this.label, {this.color, super.key});

  final String label;

  /// The text colour; the faint text colour by default.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? context.appColors.textMuted;
    // NSMenu sets a key equivalent in the menu's own font; the others in
    // their caption size.
    final style = context.metrics.menuHighlightAccent
        ? context.text.bodyMedium!.copyWith(color: ink)
        : context.metrics.typeScale.keyCap.copyWith(color: ink);
    return Semantics(
      label: label,
      child: _KeyCapRow(label, style: style, color: ink),
    );
  }
}

/// A row of key caps separated by [AppSpacing.xs].
class AppKeyCaps extends StatelessWidget {
  const AppKeyCaps(this.labels, {super.key});

  final List<String> labels;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < labels.length; i++) ...[
        if (i > 0) const SizedBox(width: AppSpacing.xs),
        AppKeyCap(labels[i]),
      ],
    ],
  );
}
