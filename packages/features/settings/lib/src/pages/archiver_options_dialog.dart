import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';

import '../settings_rows.dart';

Future<ArchiverOptions?> showArchiverOptionsDialog(
  BuildContext context, {
  required String name,
  required ArchiverEngine? engine,
  required ArchiverOptions initial,
  ArchiverOptionsValidator? validate,
}) => showAppDialog<ArchiverOptions>(
  context,
  (_) => _OptionsDialog(
    name: name,
    engine: engine,
    initial: initial,
    validate: validate,
  ),
);

class _OptionsDialog extends StatefulWidget {
  const _OptionsDialog({
    required this.name,
    required this.engine,
    required this.initial,
    this.validate,
  });
  final String name;
  final ArchiverEngine? engine;
  final ArchiverOptions initial;
  final ArchiverOptionsValidator? validate;
  @override
  State<_OptionsDialog> createState() => _OptionsDialogState();
}

class _OptionsDialogState extends State<_OptionsDialog> {
  late int _level = switch (widget.initial.level) {
    final level?
        when level >= (widget.engine?.minLevel ?? 0) &&
            level <= (widget.engine?.maxLevel ?? 9) =>
      level,
    _ => -1,
  };
  late int _threads = widget.initial.threads ?? -1;
  late int _solid = switch (widget.initial.solid) {
    null => -1,
    false => 0,
    true => 1,
  };
  late final _arguments = TextEditingController(
    text: widget.initial.arguments.join('\n'),
  );
  bool _saving = false;
  FerryxException? _error;
  @override
  void dispose() {
    _arguments.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final options = ArchiverOptions(
      level: _level < 0 ? null : _level,
      threads: _threads < 0 ? null : _threads,
      solid: _solid < 0 ? null : _solid == 1,
      arguments: _arguments.text
          .split('\n')
          .map((a) => a.trim())
          .where((a) => a.isNotEmpty)
          .toList(growable: false),
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.validate?.call(widget.engine, options);
      if (mounted) Navigator.of(context).pop(options);
    } on FerryxException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error;
        });
      }
    }
  }

  void _reset() {
    setState(() {
      _level = -1;
      _threads = -1;
      _solid = -1;
      _error = null;
    });
    _arguments.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final engine = widget.engine;
    final maxLevel = engine == null ? 9 : engine.maxLevel;
    final minLevel = engine?.minLevel ?? 0;
    return AppDialog(
      title: l10n.archiverOptionsTitle(widget.name),
      body: AppDialogScrollBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.md,
          children: [
            Text(l10n.archiverOptionsNote, style: context.text.bodySmall),
            if (maxLevel != null)
              ChoiceRow<int>(
                label: l10n.archiverCompressionLevel,
                value: _level,
                items: [
                  (-1, l10n.archiverProgramDefault),
                  for (var level = minLevel; level <= maxLevel; level++)
                    (level, '$level'),
                ],
                onChanged: (value) => setState(() => _level = value),
              ),
            if (engine?.threads ?? false) ...[
              ChoiceRow<int>(
                label: l10n.archiverThreads,
                value: _threads,
                items: [
                  (-1, l10n.archiverProgramDefault),
                  for (final count in <int>{
                    1,
                    2,
                    4,
                    8,
                    16,
                    32,
                    64,
                    128,
                    256,
                    if (_threads > 0) _threads,
                  }.toList()..sort())
                    (count, '$count'),
                ],
                onChanged: (value) => setState(() => _threads = value),
              ),
              if (engine == ArchiverEngine.bsdTar)
                Text(
                  l10n.archiverTarThreadsNote,
                  style: context.text.bodySmall,
                ),
            ],
            if (engine?.solid ?? false) ...[
              ChoiceRow<int>(
                label: l10n.archiverSolid,
                value: _solid,
                items: [
                  (-1, l10n.archiverProgramDefault),
                  (1, l10n.archiverEnabled),
                  (0, l10n.archiverDisabled),
                ],
                onChanged: (value) => setState(() => _solid = value),
              ),
              Text(l10n.archiverSolidNote, style: context.text.bodySmall),
            ],
            if (engine != null) ...[
              Text(l10n.archiverArgumentsLabel, style: context.text.bodySmall),
              TextField(
                controller: _arguments,
                minLines: 3,
                maxLines: 5,
                style: context.mono,
                readOnly: _saving,
                onEditingComplete: () {},
              ),
              Text(l10n.archiverArgumentsHint, style: context.text.bodySmall),
            ],
            if (_error case final error?)
              Text(
                error.kind == FerryxErrorKind.unsupported
                    ? l10n.archiverOptionsInvalid
                    : l10n.errorMessage(error),
                style: context.text.bodySmall?.copyWith(
                  color: context.appColors.danger,
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _saving ? null : _reset,
                child: Text(l10n.actionReset),
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }
}
