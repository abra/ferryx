import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:preferences_service/preferences_service.dart';

import '../settings_rows.dart';
import 'terminal_font_picker.dart';

/// The integrated terminal: the shell it runs, its type size, and how much
/// it keeps to scroll back.
class TerminalPage extends StatelessWidget {
  const TerminalPage({
    required this.prefs,
    required this.service,
    required this.defaultShell,
    this.loadMonospaceFonts,
    super.key,
  });

  final Preferences prefs;
  final PreferencesService service;

  /// The shell a session runs when none is set here.
  final String defaultShell;
  final Future<List<String>> Function()? loadMonospaceFonts;

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
            TerminalFontPicker(
              value: terminal.fontFamily,
              loadFonts: loadMonospaceFonts,
              onChanged: (family) =>
                  _update((t) => t.copyWith(fontFamily: family)),
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
            _FontPreview(
              family: terminal.fontFamily,
              size: terminal.fontSize,
            ),
            ChoiceRow<int>(
              label: l10n.terminalScrollbackLabel,
              note: l10n.terminalScrollbackNote,
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

class _FontPreview extends StatelessWidget {
  const _FontPreview({required this.family, required this.size});

  final String family;
  final double size;

  @override
  Widget build(BuildContext context) {
    final type = context.metrics.typeScale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.terminalFontPreview,
          style: context.text.bodySmall?.copyWith(
            color: context.appColors.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          context.l10n.terminalFontSample,
          textScaler: TextScaler.noScaling,
          style: context.mono.copyWith(
            fontFamily: family.isEmpty ? type.monoFamily : family,
            fontFamilyFallback: [type.monoFamily, ...type.monoFallback],
            fontSize: size,
            height: AppTypography.terminalLineHeightFactor,
          ),
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
  Widget build(BuildContext context) => AppTextField(
    controller: _controller,
    focusNode: _focus,
    monospace: true,
    autocorrect: false,
    enableSuggestions: false,
    hintText: widget.hint,
    onSubmitted: (_) => _commit(),
  );
}
