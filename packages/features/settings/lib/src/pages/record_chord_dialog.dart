import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shortcuts/shortcuts.dart';

/// What the dialog answers: the chord saved and, when another command
/// had it, that command, whose key the caller takes away.
class RecordedChord {
  const RecordedChord(this.chord, {this.takenFrom});

  final Chord chord;
  final AppCommand? takenFrom;
}

/// Records the next key pressed as the chord of [command]; warns when
/// another command has it already and offers to take it over.
Future<RecordedChord?> showRecordChordDialog(
  BuildContext context, {
  required AppCommand command,
  required ShortcutMap map,
  required TargetPlatform platform,
  bool vim = false,
}) => showAppDialog<RecordedChord>(
  context,
  (context) => _RecordChordDialog(
    command: command,
    map: map,
    platform: platform,
    vim: vim,
  ),
);

/// The chord a key event stands for on [platform]: the key under its
/// unshifted name ([Chord.keyOf]: by its place on a layout of another
/// script) with the modifiers held; `null` for a modifier alone.
Chord? chordOfEvent(KeyEvent event, TargetPlatform platform) {
  final keyboard = HardwareKeyboard.instance;
  final key = Chord.keyOf(event, keyboard);
  if (_modifiers.contains(key)) return null;
  final isMac = platform == TargetPlatform.macOS;
  return Chord(
    Chord.unshifted(key),
    primary: isMac ? keyboard.isMetaPressed : keyboard.isControlPressed,
    control: isMac && keyboard.isControlPressed,
    alt: keyboard.isAltPressed,
    shift: keyboard.isShiftPressed,
  );
}

final _modifiers = <LogicalKeyboardKey>{
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.fn,
};

class _RecordChordDialog extends StatefulWidget {
  const _RecordChordDialog({
    required this.command,
    required this.map,
    required this.platform,
    required this.vim,
  });

  final AppCommand command;
  final ShortcutMap map;
  final TargetPlatform platform;

  /// Keys read as Vim writes them, as the panels take them.
  final bool vim;

  @override
  State<_RecordChordDialog> createState() => _RecordChordDialogState();
}

class _RecordChordDialogState extends State<_RecordChordDialog> {
  Chord? _chord;
  AppCommand? _conflict;
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && !_anyModifier) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter && !_anyModifier && _chord != null) {
      _save();
      return KeyEventResult.handled;
    }
    final chord = chordOfEvent(event, widget.platform);
    if (chord == null) return KeyEventResult.ignored;
    final other = widget.map
        .conflictsWith(widget.command, chord, widget.platform)
        .firstOrNull;
    setState(() {
      _chord = chord;
      _conflict = other == null || other == widget.command ? null : other;
    });
    return KeyEventResult.handled;
  }

  bool get _anyModifier {
    final k = HardwareKeyboard.instance;
    return k.isMetaPressed ||
        k.isControlPressed ||
        k.isAltPressed ||
        k.isShiftPressed;
  }

  void _save() {
    final chord = _chord;
    if (chord == null) return;
    Navigator.of(context).pop(RecordedChord(chord, takenFrom: _conflict));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final metrics = context.metrics;
    final chord = _chord;
    final conflict = _conflict;
    return AppDialog(
      title: l10n.hotkeysRecordTitle(l10n.commandLabel(widget.command)),
      width: AppSizes.compactDialogWidth,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A field-like box that takes the key: the ring shows it has
          // the focus, as a field's would.
          Focus(
            autofocus: true,
            onKeyEvent: _onKey,
            onFocusChange: (focused) => setState(() => _focused = focused),
            child: FocusRing(
              focused: _focused,
              radius: metrics.radius.control,
              child: Container(
                constraints: BoxConstraints(
                  minHeight: metrics.controlHeightLarge,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: appEdgedBox(
                  color: colors.controlFill,
                  edge: colors.controlBorder,
                  radius: metrics.radius.control,
                ),
                alignment: Alignment.centerLeft,
                child: chord == null
                    ? Text(
                        l10n.hotkeysRecord,
                        style: context.text.bodyMedium?.copyWith(
                          color: colors.textFaint,
                        ),
                      )
                    : AppKeyCap(
                        widget.vim
                            ? chord.vimLabel(widget.platform)
                            : chord.label(widget.platform),
                        emphasized: true,
                      ),
              ),
            ),
          ),
          if (conflict != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  AppIcons.warning,
                  size: AppIconSize.sm,
                  color: colors.danger,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    l10n.hotkeysConflict(l10n.commandLabel(conflict)),
                    style: context.text.bodySmall?.copyWith(
                      color: colors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        // With a conflict the key is taken over from the other command.
        FilledButton(
          onPressed: chord == null ? null : _save,
          child: Text(
            conflict == null ? l10n.actionSave : l10n.hotkeysReassign,
          ),
        ),
      ],
    );
  }
}
