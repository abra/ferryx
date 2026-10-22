import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:preferences_service/preferences_service.dart';

import '../settings_rows.dart';

/// The integrated terminal: the shell it runs, its type size, and how much
/// it keeps to scroll back.
class TerminalPage extends StatelessWidget {
  const TerminalPage({
    required this.prefs,
    required this.service,
    required this.defaultShell,
    super.key,
  });

  final Preferences prefs;
  final PreferencesService service;

  /// The shell a session runs when none is set here.
  final String defaultShell;

  /// The scrollback lengths offered; a value set otherwise shows too.
  static const scrollbacks = [1000, 5000, 10000, 50000, 100000];

  Future<void> _update(
    TerminalPreferences Function(TerminalPreferences) change,
  ) => service.update((p) => p.copyWith(terminal: change(p.terminal)));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final terminal = prefs.terminal;
    final fontSize = terminal.fontSize.round();
    return SettingsPage(
      children: [
        SettingsGroup(
          children: [
            AppControlRow(
              label: l10n.terminalShellLabel,
              note: l10n.terminalShellNote,
              control: SizedBox(
                width: AppSizes.settingsSliderWidth,
                child: ShellField(
                  value: terminal.shell,
                  hint: defaultShell.isEmpty
                      ? null
                      : l10n.terminalShellDefault(defaultShell),
                  onCommit: (shell) =>
                      _update((t) => t.copyWith(shell: shell.trim())),
                ),
              ),
            ),
            SliderRow(
              label: l10n.terminalFontSizeLabel,
              value: terminal.fontSize,
              min: TerminalPreferences.minFontSize,
              max: TerminalPreferences.maxFontSize,
              divisions:
                  (TerminalPreferences.maxFontSize -
                          TerminalPreferences.minFontSize)
                      .round(),
              display: switch (context.metrics.lengthUnit) {
                AppLengthUnit.points => l10n.lengthPoints(fontSize),
                AppLengthUnit.pixels => l10n.lengthPixels(fontSize),
              },
              onChanged: (value) =>
                  _update((t) => t.copyWith(fontSize: value.roundToDouble())),
            ),
            ChoiceRow<int>(
              label: l10n.terminalScrollbackLabel,
              value: terminal.scrollback,
              items: [
                for (final lines in {
                  ...scrollbacks,
                  terminal.scrollback,
                }.toList()..sort())
                  (lines, l10n.terminalLineCount(lines)),
              ],
              onChanged: (lines) =>
                  _update((t) => t.copyWith(scrollback: lines)),
            ),
          ],
        ),
      ],
    );
  }
}

/// The shell's path: written when Return is pressed or the field is left,
/// not at every key, as the preferences are saved whole.
class ShellField extends StatefulWidget {
  const ShellField({
    required this.value,
    required this.hint,
    required this.onCommit,
    super.key,
  });

  final String value;
  final String? hint;
  final ValueChanged<String> onCommit;

  @override
  State<ShellField> createState() => _ShellFieldState();
}

class _ShellFieldState extends State<ShellField> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode(debugLabel: 'shell');

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(ShellField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value &&
        !_focus.hasFocus &&
        _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    if (_controller.text.trim() != widget.value) {
      widget.onCommit(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    focusNode: _focus,
    style: context.mono,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(hintText: widget.hint),
    onSubmitted: (_) => _commit(),
  );
}
