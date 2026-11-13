import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// The catalog belongs to this page's lifetime, not to preference rebuilds.
/// Keeping an unavailable saved family lets a temporarily missing font return.
class TerminalFontPicker extends StatefulWidget {
  const TerminalFontPicker({
    required this.value,
    required this.onChanged,
    this.loadFonts,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final Future<List<String>> Function()? loadFonts;

  @override
  State<TerminalFontPicker> createState() => _TerminalFontPickerState();
}

class _TerminalFontPickerState extends State<TerminalFontPicker> {
  late Future<List<String>> _fonts = _load();

  Future<List<String>> _load() => Future.sync(
    () => widget.loadFonts?.call() ?? const <String>[],
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<List<String>>(
    future: _fonts,
    builder: (context, snapshot) {
      final l10n = context.l10n;
      final available = {
        AppTypography.bundledMono,
        ...?snapshot.data,
      };
      final families = {
        ...available,
        if (widget.value.isNotEmpty) widget.value,
      }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final note = snapshot.connectionState != ConnectionState.done
          ? l10n.terminalFontsLoading
          : snapshot.hasError
          ? l10n.terminalFontsLoadFailed
          : widget.value.isNotEmpty && !available.contains(widget.value)
          ? l10n.terminalFontUnavailable
          : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AppControlRow(
            label: l10n.terminalFontLabel,
            note: note,
            control: AppPopupButton<String>(
              value: widget.value,
              items: [
                ('', l10n.terminalFontSystem),
                for (final family in families) (family, family),
              ],
              onChanged: widget.onChanged,
            ),
          ),
          if (snapshot.hasError)
            TextButton(
              onPressed: () => setState(() {
                _fonts = _load();
              }),
              child: Text(l10n.actionRetry),
            ),
        ],
      );
    },
  );
}
