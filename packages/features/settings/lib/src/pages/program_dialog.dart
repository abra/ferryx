import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../settings_rows.dart';

/// What the dialog of an editor or a tool holds.
class ProgramDraft {
  const ProgramDraft({
    required this.name,
    required this.path,
    required this.extra,
    required this.inTerminal,
  });

  final String name;
  final String path;

  /// The editor's file masks, or the tool's arguments.
  final String extra;
  final bool inTerminal;
}

/// The words of the dialog: an editor's or a tool's.
class ProgramLabels {
  const ProgramLabels({
    required this.title,
    required this.addTitle,
    required this.name,
    required this.path,
    required this.extra,
    required this.extraHint,
    required this.inTerminal,
  });

  /// The title over an existing program, and over a new one.
  final String title;
  final String addTitle;
  final String name;
  final String path;
  final String extra;
  final String extraHint;
  final String inTerminal;
}

/// Edits a program's fields; answers the draft saved. The path can be
/// picked with the system's file dialog.
Future<ProgramDraft?> showProgramDialog(
  BuildContext context, {
  required ProgramLabels labels,
  required ProgramDraft? initial,
  Future<String?> Function()? pickPath,
}) => showAppDialog<ProgramDraft>(
  context,
  (context) => _ProgramDialog(
    labels: labels,
    initial: initial,
    pickPath: pickPath ?? _systemPicker,
  ),
);

Future<String?> _systemPicker() async => (await openFile())?.path;

/// The name a program's path suggests: its last segment, whichever
/// separator the path uses, without an app bundle's extension.
String programNameOf(String path) {
  final cut = path.lastIndexOf(RegExp(r'[/\\]'));
  final name = cut < 0 ? path : path.substring(cut + 1);
  return name.endsWith('.app') ? name.substring(0, name.length - 4) : name;
}

class _ProgramDialog extends StatefulWidget {
  const _ProgramDialog({
    required this.labels,
    required this.initial,
    required this.pickPath,
  });

  final ProgramLabels labels;
  final ProgramDraft? initial;
  final Future<String?> Function() pickPath;

  @override
  State<_ProgramDialog> createState() => _ProgramDialogState();
}

class _ProgramDialogState extends State<_ProgramDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _path = TextEditingController(text: widget.initial?.path ?? '');
  late final _extra = TextEditingController(text: widget.initial?.extra ?? '');
  late bool _inTerminal = widget.initial?.inTerminal ?? false;
  late final _fields = Listenable.merge([_name, _path]);

  @override
  void dispose() {
    _name.dispose();
    _path.dispose();
    _extra.dispose();
    super.dispose();
  }

  bool get _complete =>
      _name.text.trim().isNotEmpty && _path.text.trim().isNotEmpty;

  Future<void> _choose() async {
    final picked = await widget.pickPath();
    if (picked == null || !mounted) return;
    setState(() {
      _path.text = picked;
      if (_name.text.trim().isEmpty) _name.text = programNameOf(picked);
    });
  }

  void _save() {
    if (!_complete) return;
    Navigator.of(context).pop(
      ProgramDraft(
        name: _name.text.trim(),
        path: _path.text.trim(),
        extra: _extra.text.trim(),
        inTerminal: _inTerminal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = widget.labels;
    return ListenableBuilder(
      listenable: _fields,
      builder: (context, _) => AppDialog(
        title: widget.initial == null ? labels.addTitle : labels.title,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabeledField(
              label: labels.name,
              controller: _name,
              autofocus: true,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: AppSpacing.md),
            LabeledField(
              label: labels.path,
              controller: _path,
              monospace: true,
              onSubmitted: (_) => _save(),
              trailing: OutlinedButton(
                onPressed: _choose,
                child: Text(l10n.choosePath),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            LabeledField(
              label: labels.extra,
              hint: labels.extraHint,
              controller: _extra,
              monospace: true,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCheckbox(
              label: labels.inTerminal,
              value: _inTerminal,
              onChanged: (v) => setState(() => _inTerminal = v),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: _complete ? _save : null,
            child: Text(l10n.actionSave),
          ),
        ],
      ),
    );
  }
}
