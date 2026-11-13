import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:material_ui/material_ui.dart';

import 'archive_engine_picker.dart';
import 'dialog_support.dart';

/// The archive's name, format, password and destination panel.
class CompressChoice {
  const CompressChoice({
    required this.name,
    required this.password,
    required this.toOpposite,
    this.archiver,
    this.format = ArchiveType.zip,
    this.engineId = '',
  });

  final ArchiveTool? archiver;
  final ArchiveType format;
  final String engineId;
  final String name;
  final String? password;
  final bool toOpposite;
}

Future<CompressChoice?> showCompressDialog(
  BuildContext context, {
  required List<String> names,
  required String defaultName,
  required bool toOpposite,
  List<ArchiveTool> tools = const [],
  ArchiveType format = ArchiveType.zip,
  String engineId = '',
  bool singleFile = false,
  Future<List<ArchiveTool>> Function()? onManage,
}) => showWorkspaceDialog<CompressChoice>(
  context,
  (context) => _CompressDialog(
    names: names,
    defaultName: defaultName,
    toOpposite: toOpposite,
    tools: tools,
    format: format,
    engineId: engineId,
    singleFile: singleFile,
    onManage: onManage,
  ),
);

class _CompressDialog extends StatefulWidget {
  const _CompressDialog({
    required this.names,
    required this.defaultName,
    required this.toOpposite,
    required this.tools,
    required this.format,
    required this.engineId,
    required this.singleFile,
    this.onManage,
  });

  final List<String> names;
  final String defaultName;
  final bool toOpposite;
  final List<ArchiveTool> tools;
  final ArchiveType format;
  final String engineId;
  final bool singleFile;
  final Future<List<ArchiveTool>> Function()? onManage;

  @override
  State<_CompressDialog> createState() => _CompressDialogState();
}

class _CompressDialogState extends State<_CompressDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.defaultName,
  );
  final _password = TextEditingController();
  bool _passwordFallback = false;
  late bool _toOpposite = widget.toOpposite;
  late List<ArchiveTool> _tools = widget.tools;
  late ArchiveType _format = _formats.contains(_preferredFormat)
      ? _preferredFormat
      : ArchiveType.zip;
  ArchiveType get _preferredFormat =>
      widget.singleFile ? widget.format : widget.format.container;
  late String _engineId =
      widget.engineId == builtInArchiverId && _format == ArchiveType.zip ||
          _candidates.any((t) => t.id == widget.engineId)
      ? widget.engineId
      : '';
  List<ArchiveType> get _formats => [
    ArchiveType.zip,
    for (final type in ArchiveType.values)
      if (type != ArchiveType.zip &&
          (widget.singleFile || !type.singleFileOnly) &&
          _tools.any((t) => t.engine.creates.contains(type)))
        type,
  ];
  List<ArchiveTool> get _candidates {
    final indexed =
        _tools.where((t) => t.engine.creates.contains(_format)).indexed.toList()
          ..sort((a, b) {
            final priority = a.$2.engine.compressionPriority.compareTo(
              b.$2.engine.compressionPriority,
            );
            return priority == 0 ? a.$1.compareTo(b.$1) : priority;
          });
    return [for (final (_, tool) in indexed) tool];
  }

  ArchiveTool? get _tool => _engineId == builtInArchiverId
      ? null
      : toolById(_candidates, _engineId) ??
            (_format == ArchiveType.zip ? null : _candidates.firstOrNull);
  bool get _passwords => _tool?.engine.passwords ?? _format == ArchiveType.zip;

  void _chooseFormat(ArchiveType value) {
    setState(() {
      _format = value;
      _name.text = value.nameFor(_name.text);
      if (_engineId == builtInArchiverId && value != ArchiveType.zip ||
          _engineId != builtInArchiverId &&
              _engineId.isNotEmpty &&
              !_candidates.any((t) => t.id == _engineId)) {
        _engineId = '';
      }
    });
    _passwordChanged();
  }

  Future<void> _manage() async {
    final tools = await widget.onManage!();
    if (!mounted) return;
    setState(() {
      _tools = tools;
      if (!_formats.contains(_format)) _format = ArchiveType.zip;
      if (!_candidates.any((t) => t.id == _engineId)) _engineId = '';
      _name.text = _format.nameFor(_name.text);
    });
  }

  void _passwordChanged() {
    if (_format == ArchiveType.zip &&
        _tool?.engine == ArchiverEngine.sevenZip &&
        _password.text.runes.any((rune) => rune > 127)) {
      setState(() {
        _engineId = builtInArchiverId;
        _passwordFallback = true;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _password.addListener(_passwordChanged);
    _name.text = _format.nameFor(_name.text);
    final dot = _name.text.length - _format.extension.length - 1;
    _name.selection = TextSelection(
      baseOffset: 0,
      extentOffset: dot > 0 ? dot : widget.defaultName.length,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      CompressChoice(
        name: _format.nameFor(name),
        archiver: _tool,
        format: _format,
        engineId: _engineId,
        password: !_passwords || _password.text.isEmpty ? null : _password.text,
        toOpposite: _toOpposite,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppDialog(
      title: l10n.compressTitle(widget.names.length, firstName(widget.names)),
      body: AppDialogScrollBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DialogChoice<ArchiveType>(
              label: l10n.archiveFormatLabel,
              value: _format,
              items: [for (final type in _formats) (type, type.label)],
              onChanged: _chooseFormat,
            ),
            dialogRowGap,
            ArchiveEnginePicker(
              tools: _candidates,
              value: _engineId,
              includeBuiltin: _format == ArchiveType.zip,
              automaticName: _format == ArchiveType.zip
                  ? l10n.archiversBuiltin
                  : _candidates.firstOrNull?.name,
              onChanged: (value) {
                if (value == builtInArchiverId && _format != ArchiveType.zip) {
                  _chooseFormat(ArchiveType.zip);
                }
                setState(() {
                  _engineId = value;
                  _passwordFallback = false;
                });
                _passwordChanged();
              },
              onManage: widget.onManage == null ? null : () => _manage(),
            ),
            dialogRowGap,
            DialogField(
              label: l10n.archiveNameLabel,
              controller: _name,
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
            dialogRowGap,
            if (_passwords)
              DialogField(
                label: l10n.passwordLabel,
                controller: _password,
                obscure: true,
                onSubmitted: (_) => _submit(),
              ),
            if (_passwordFallback && _format == ArchiveType.zip)
              Text(
                l10n.archiveZipUnicodeFallback,
                style: context.text.bodySmall,
              ),
            if (!_passwords)
              Text(
                l10n.archivePasswordUnavailable,
                style: context.text.bodySmall,
              ),
            dialogRowGap,
            AppSegmentedControl<bool>(
              options: [
                (false, l10n.compressHere),
                (true, l10n.compressToOpposite),
              ],
              value: _toOpposite,
              onChanged: (v) => setState(() => _toOpposite = v),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        DialogSubmitButton(
          label: l10n.actionCompress,
          controllers: [_name],
          onPressed: _submit,
        ),
      ],
    );
  }
}
