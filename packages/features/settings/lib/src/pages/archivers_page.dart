import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:preferences_service/preferences_service.dart';

import '../settings_rows.dart';
import 'archiver_options_dialog.dart';

class ArchiversPage extends StatefulWidget {
  const ArchiversPage({
    required this.prefs,
    required this.service,
    this.discover,
    this.validateOptions,
    super.key,
  });
  final Preferences prefs;
  final PreferencesService service;
  final ArchiverDiscovery? discover;
  final ArchiverOptionsValidator? validateOptions;
  @override
  State<ArchiversPage> createState() => _ArchiversPageState();
}

class _ArchiversPageState extends State<ArchiversPage> {
  List<ArchiveTool> _tools = const [];
  bool _loading = false;
  FerryxException? _error;
  int _scan = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ArchiversPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prefs.archivers.manual != widget.prefs.archivers.manual) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final scan = ++_scan;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tools =
          await widget.discover?.call(
            widget.prefs.archivers.manual,
            refresh: true,
          ) ??
          const <ArchiveTool>[];
      if (mounted && scan == _scan) {
        setState(() {
          _tools = tools;
          _loading = false;
        });
      }
    } on FerryxException catch (error) {
      if (mounted && scan == _scan) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _enable(ArchiveTool tool, bool enabled) =>
      widget.service.update((p) {
        final disabled = {...p.archivers.disabled};
        if (enabled) {
          disabled.remove(tool.id);
        } else {
          disabled.add(tool.id);
        }
        return p.copyWith(
          archivers: p.archivers.copyWith(disabled: disabled.toList()),
        );
      });

  Future<void> _edit([ArchiveTool? tool]) async {
    final result = await showAppDialog<ArchiveTool>(
      context,
      (_) => _ArchiverDialog(initial: tool, discover: widget.discover),
    );
    if (result == null || !mounted) return;
    await widget.service.update((p) {
      final manual =
          p.archivers.manual
              .where((t) => t.id != tool?.id && t.id != result.id)
              .toList()
            ..add(result);
      final options = {...p.archivers.options};
      if (tool != null && tool.id != result.id) {
        final previous = options.remove(tool.id);
        if (previous != null) options[result.id] = previous;
      }
      return p.copyWith(
        archivers: p.archivers.copyWith(manual: manual, options: options),
      );
    });
  }

  Future<void> _remove(ArchiveTool tool) => widget.service.update(
    (p) => p.copyWith(
      archivers: p.archivers.copyWith(
        manual: p.archivers.manual.where((t) => t.id != tool.id).toList(),
        disabled: p.archivers.disabled.where((id) => id != tool.id).toList(),
        options: {...p.archivers.options}..remove(tool.id),
      ),
    ),
  );

  Future<void> _configure([ArchiveTool? tool]) async {
    final id = tool?.id ?? builtInArchiverId;
    final options = await showArchiverOptionsDialog(
      context,
      name: tool?.name ?? context.l10n.archiversBuiltin,
      engine: tool?.engine,
      initial: widget.prefs.archivers.optionsFor(id),
      validate: widget.validateOptions,
    );
    if (options == null || !mounted) return;
    await widget.service.update((p) {
      final values = {...p.archivers.options};
      if (options == const ArchiverOptions()) {
        values.remove(id);
      } else {
        values[id] = options;
      }
      return p.copyWith(archivers: p.archivers.copyWith(options: values));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final prefs = widget.prefs.archivers;
    final manualIds = prefs.manual.map((t) => t.id).toSet();
    final detected = _tools.where((t) => !manualIds.contains(t.id)).toList();
    final available = _tools.map((t) => t.id).toSet();
    return SettingsPage(
      children: [
        Text(l10n.archiversIntro, style: context.text.bodyMedium),
        SettingsGroup(
          children: [
            AppControlRow(
              label: l10n.archiversBuiltin,
              note: l10n.archiversBuiltinNote,
              control: AppIconButton(
                icon: AppIcons.settings,
                tooltip: l10n.archiverOptionsTitle(l10n.archiversBuiltin),
                onPressed: _configure,
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: l10n.archiversDetected,
          footer: Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(AppIcons.refresh, size: AppIconSize.sm),
              label: Text(l10n.archiversRescan),
            ),
          ),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error case final error?)
              Text(
                l10n.errorMessage(error),
                style: context.text.bodySmall?.copyWith(
                  color: context.appColors.danger,
                ),
              ),
            if (!_loading && detected.isEmpty)
              SettingsPlaceholderRow(l10n.archiversEmpty),
            for (final tool in detected)
              _ArchiverRow(
                tool: tool,
                enabled: !prefs.disabled.contains(tool.id),
                available: true,
                onChanged: (v) => _enable(tool, v),
                customized:
                    prefs.optionsFor(tool.id) != const ArchiverOptions(),
                onConfigure: () => _configure(tool),
              ),
          ],
        ),
        SettingsGroup(
          title: l10n.archiversManual,
          footer: Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(AppIcons.add, size: AppIconSize.sm),
              label: Text(l10n.archiversAdd),
            ),
          ),
          children: [
            if (prefs.manual.isEmpty)
              SettingsPlaceholderRow(l10n.archiversManualHint),
            for (final tool in prefs.manual)
              _ArchiverRow(
                tool: tool,
                enabled: !prefs.disabled.contains(tool.id),
                available: available.contains(tool.id),
                onChanged: (v) => _enable(tool, v),
                customized:
                    prefs.optionsFor(tool.id) != const ArchiverOptions(),
                onConfigure: () => _configure(tool),
                onEdit: () => _edit(tool),
                onRemove: () => _remove(tool),
              ),
          ],
        ),
      ],
    );
  }
}

class _ArchiverRow extends StatelessWidget {
  const _ArchiverRow({
    required this.tool,
    required this.enabled,
    required this.available,
    required this.onChanged,
    required this.onConfigure,
    required this.customized,
    this.onEdit,
    this.onRemove,
  });
  final ArchiveTool tool;
  final bool enabled;
  final bool available;
  final ValueChanged<bool> onChanged;
  final VoidCallback onConfigure;
  final bool customized;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) => AppControlRow(
    label: tool.name,
    note: available
        ? customized
              ? context.l10n.joinedDetails(
                  tool.path,
                  context.l10n.archiverCustomized,
                )
              : tool.path
        : context.l10n.joinedDetails(tool.path, context.l10n.archiversMissing),
    control: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: context.metrics.toolbarSpacing,
      children: [
        AppIconButton(
          icon: AppIcons.settings,
          tooltip: context.l10n.archiverOptionsTitle(tool.name),
          onPressed: onConfigure,
        ),
        if (onEdit != null)
          AppIconButton(
            icon: AppIcons.edit,
            tooltip: context.l10n.hotkeysChange,
            onPressed: onEdit,
          ),
        if (onRemove != null)
          AppIconButton(
            icon: AppIcons.close,
            tooltip: context.l10n.actionRemove,
            onPressed: onRemove,
          ),
        AppTooltip(
          message: tool.path,
          child: AppToggle(value: enabled, onChanged: onChanged),
        ),
      ],
    ),
  );
}

class _ArchiverDialog extends StatefulWidget {
  const _ArchiverDialog({required this.initial, required this.discover});
  final ArchiveTool? initial;
  final ArchiverDiscovery? discover;
  @override
  State<_ArchiverDialog> createState() => _ArchiverDialogState();
}

class _ArchiverDialogState extends State<_ArchiverDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _path = TextEditingController(text: widget.initial?.path ?? '');
  late ArchiverEngine _engine =
      widget.initial?.engine ?? ArchiverEngine.sevenZip;
  bool _saving = false;
  bool _missing = false;
  @override
  void dispose() {
    _name.dispose();
    _path.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    final picked = await openFile();
    if (picked == null || !mounted) return;
    _path.text = picked.path;
    if (_name.text.trim().isEmpty) _name.text = _engine.label;
    setState(() => _missing = false);
  }

  Future<void> _save() async {
    if (_saving || _name.text.trim().isEmpty || _path.text.trim().isEmpty) {
      return;
    }
    final tool = ArchiveTool(
      name: _name.text.trim(),
      path: _path.text.trim(),
      engine: _engine,
    );
    setState(() {
      _saving = true;
      _missing = false;
    });
    try {
      final found =
          await widget.discover?.call([tool], refresh: true) ??
          const <ArchiveTool>[];
      if (!mounted) return;
      if (!found.any((t) => t.id == tool.id)) {
        setState(() {
          _saving = false;
          _missing = true;
        });
        return;
      }
      Navigator.of(context).pop(tool);
    } on FerryxException {
      if (mounted) {
        setState(() {
          _saving = false;
          _missing = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: Listenable.merge([_name, _path]),
      builder: (context, _) => AppDialog(
        title: widget.initial == null
            ? l10n.archiversAddTitle
            : l10n.archiversEditTitle,
        body: AppDialogScrollBody(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.archiversManualHint, style: context.text.bodySmall),
              const SizedBox(height: AppSpacing.md),
              LabeledField(
                label: l10n.archiversName,
                controller: _name,
                autofocus: true,
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: AppSpacing.md),
              LabeledField(
                label: l10n.archiversPath,
                controller: _path,
                monospace: true,
                trailing: OutlinedButton(
                  onPressed: _saving ? null : _browse,
                  child: Text(l10n.choosePath),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: AppSpacing.md),
              ChoiceRow<ArchiverEngine>(
                label: l10n.archiversAdapter,
                value: _engine,
                items: [
                  for (final engine in ArchiverEngine.values)
                    (engine, engine.label),
                ],
                onChanged: (v) => setState(() => _engine = v),
              ),
              if (_missing)
                Text(
                  l10n.archiversMissing,
                  style: context.text.bodySmall?.copyWith(
                    color: context.appColors.danger,
                  ),
                ),
              if (_saving) const LinearProgressIndicator(),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed:
                _saving ||
                    _name.text.trim().isEmpty ||
                    _path.text.trim().isEmpty
                ? null
                : _save,
            child: Text(l10n.actionSave),
          ),
        ],
      ),
    );
  }
}
