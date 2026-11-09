import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shortcuts/shortcuts.dart';

import '../path_text.dart';
import 'dialog_support.dart';
import 'archive_engine_picker.dart';
import 'path_field.dart';

/// What Extract To answered.
class ExtractChoice {
  const ExtractChoice({
    required this.destination,
    required this.intoFolders,
    required this.password,
    required this.conflicts,
    this.archiver,
    this.engineId = '',
  });

  /// The folder written into, as typed (`~` not yet expanded).
  final String destination;

  /// Each archive into a folder named after it.
  final bool intoFolders;

  /// The password, checked before submission when using the built-in engine.
  final String? password;
  final ConflictPolicy conflicts;
  final ArchiveTool? archiver;
  final String engineId;
}

/// An archive Extract To works on, with what the core says it holds once
/// it has read it.
class ExtractSource {
  const ExtractSource({required this.name, required this.path, this.info});

  final String name;
  final String path;
  final Future<ArchiveInfo?>? info;
}

/// Extract To: where the archives go, whether each gets a folder of
/// its own, and their password when they ask for one. [members] is the
/// number of items picked inside an archive (then there is no folder
/// option); [checkPassword] tries a password on an archive and answers
/// the error, if any, so a wrong one is said in the dialog.
Future<ExtractChoice?> showExtractDialog(
  BuildContext context, {
  required List<ExtractSource> archives,
  required String defaultDestination,
  required Future<List<String>> Function(String text) complete,
  required Future<FerryxException?> Function(String archive, String password)
  checkPassword,
  int? members,
  List<ArchiveTool> tools = const [],
  String engineId = '',
  Future<List<ArchiveTool>> Function()? onManage,
}) => showWorkspaceDialog<ExtractChoice>(
  context,
  (context) => ExtractDialog(
    archives: archives,
    defaultDestination: defaultDestination,
    complete: complete,
    checkPassword: checkPassword,
    members: members,
    tools: tools,
    engineId: engineId,
    onManage: onManage,
  ),
);

class ExtractDialog extends StatefulWidget {
  const ExtractDialog({
    required this.archives,
    required this.defaultDestination,
    required this.complete,
    required this.checkPassword,
    this.members,
    this.tools = const [],
    this.engineId = '',
    this.onManage,
    super.key,
  });

  final List<ExtractSource> archives;
  final String defaultDestination;
  final Future<List<String>> Function(String text) complete;
  final Future<FerryxException?> Function(String archive, String password)
  checkPassword;
  final int? members;
  final List<ArchiveTool> tools;
  final String engineId;
  final Future<List<ArchiveTool>> Function()? onManage;

  @override
  State<ExtractDialog> createState() => _ExtractDialogState();
}

class _ExtractDialogState extends State<ExtractDialog> {
  late final TextEditingController _destination = TextEditingController(
    text: widget.defaultDestination,
  );
  final _password = TextEditingController();
  final _passwordFocus = FocusNode(debugLabel: 'archive password');

  /// What the core said about each archive, as it comes.
  late final List<ArchiveInfo?> _infos = List.filled(
    widget.archives.length,
    null,
  );

  /// Until the user flips it, the option follows the archives: a folder
  /// when one unpacks to more than one item, as Archive Utility does.
  bool? _intoFolders;
  ConflictPolicy _conflicts = ConflictPolicy.ask;

  /// The archive the password last given did not open.
  String? _wrongFor;
  bool _checking = false;
  late List<ArchiveTool> _tools = widget.tools;
  late String _engineId = widget.engineId;
  List<ArchiveTool> get _candidates => !_wholeArchives
      ? const []
      : _tools
            .where(
              (tool) =>
                  tool.engine.extracts &&
                  widget.archives.every((a) => tool.engine.reads(a.path)) &&
                  (_locked.isEmpty || tool.engine.passwords),
            )
            .toList();
  String get _chosenId =>
      _engineId == builtInArchiverId ||
          _candidates.any((t) => t.id == _engineId)
      ? _engineId
      : '';
  ArchiveTool? get _automatic =>
      _infos.any((info) => info == null) ? _candidates.firstOrNull : null;
  ArchiveTool? get _tool => _chosenId == builtInArchiverId
      ? null
      : toolById(_candidates, _chosenId) ?? _automatic;
  Future<void> _manage() async {
    final tools = await widget.onManage!();
    if (mounted) setState(() => _tools = tools);
  }

  @override
  void initState() {
    super.initState();
    _destination.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _destination.text.length,
    );
    for (var i = 0; i < widget.archives.length; i++) {
      final info = widget.archives[i].info;
      if (info == null) continue;
      unawaited(
        info.then((value) {
          if (mounted) setState(() => _infos[i] = value);
        }),
      );
    }
  }

  @override
  void dispose() {
    _destination.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool get _wholeArchives => widget.members == null;

  bool get _intoFoldersShown =>
      _intoFolders ??
      (_infos.every((i) => i == null)
          ? widget.archives.length > 1 || _candidates.isNotEmpty
          : _infos.any((i) => i?.wantsFolder ?? false));

  /// The archives that ask for a password.
  List<ExtractSource> get _locked => [
    for (var i = 0; i < widget.archives.length; i++)
      if (_infos[i]?.asksPassword ?? false) widget.archives[i],
  ];

  Future<void> _submit() async {
    final destination = _destination.text.trim();
    if (destination.isEmpty || _checking) return;
    final locked = _locked;
    final password = _password.text;
    if (locked.isNotEmpty && _tool == null) {
      if (password.isEmpty) {
        _passwordFocus.requestFocus();
        return;
      }
      setState(() {
        _checking = true;
        _wrongFor = null;
      });
      for (final archive in locked) {
        final error = await widget.checkPassword(archive.path, password);
        if (!mounted) return;
        if (error != null) {
          setState(() {
            _checking = false;
            _wrongFor = archive.name;
          });
          _passwordFocus.requestFocus();
          _password.selection = TextSelection(
            baseOffset: 0,
            extentOffset: password.length,
          );
          return;
        }
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      ExtractChoice(
        destination: destination,
        intoFolders: _wholeArchives && _intoFoldersShown,
        password: password.isEmpty ? null : password,
        conflicts: _conflicts,
        archiver: _tool,
        engineId: _chosenId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final platform = Theme.of(context).platform;
    final count = widget.archives.length;
    final members = widget.members;
    final title = members != null
        ? (members == 1 && count == 1
              ? l10n.archiveExtractOneTitle(widget.archives.first.name)
              : l10n.archiveExtractMembersTitle(members))
        : count == 1
        ? l10n.archiveExtractOneTitle(widget.archives.first.name)
        : l10n.archiveExtractManyTitle(count);
    final locked = _locked;
    final wrongFor = _wrongFor;
    return AppDialog(
      title: title,
      body: AppDialogScrollBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_wholeArchives) ...[
              ArchiveEnginePicker(
                tools: _candidates,
                value: _chosenId,
                automaticName: _automatic?.name ?? l10n.archiversBuiltin,
                onChanged: (value) => setState(() => _engineId = value),
                onManage: widget.onManage == null ? null : () => _manage(),
              ),
              dialogRowGap,
            ],
            PathField(
              label: l10n.destinationLabel,
              controller: _destination,
              autofocus: true,
              complete: widget.complete,
              hint: l10n.archiveDestinationHint(
                Chord.keyLabel(LogicalKeyboardKey.tab, platform),
              ),
              onSubmitted: (_) => unawaited(_submit()),
            ),
            if (_wholeArchives) ...[
              dialogRowGap,
              DialogToggle(
                label: count == 1
                    ? l10n.archiveIntoFolder(_folderName(widget.archives.first))
                    : l10n.archiveIntoFolders,
                value: _intoFoldersShown,
                onChanged: (v) => setState(() => _intoFolders = v),
              ),
            ],
            if (locked.isNotEmpty || _tool?.engine.passwords == true) ...[
              dialogRowGap,
              DialogField(
                label: l10n.archivePasswordLabel,
                controller: _password,
                focusNode: _passwordFocus,
                obscure: true,
                readOnly: _checking,
                onSubmitted: (_) => unawaited(_submit()),
              ),
              if (wrongFor != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.archiveWrongPasswordFor(wrongFor),
                  style: context.text.bodySmall?.copyWith(
                    color: context.appColors.danger,
                  ),
                ),
              ],
            ],
            const SizedBox(height: AppSpacing.sm),
            DialogChoice<ConflictPolicy>(
              label: l10n.conflictsLabel,
              value: _conflicts,
              items: [
                (ConflictPolicy.ask, l10n.conflictAsk),
                (ConflictPolicy.overwrite, l10n.conflictOverwrite),
                (ConflictPolicy.overwriteOlder, l10n.conflictOverwriteOlder),
                (ConflictPolicy.skip, l10n.conflictSkip),
                (ConflictPolicy.keepBoth, l10n.conflictKeepBoth),
              ],
              onChanged: (v) => setState(() => _conflicts = v),
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
          label: l10n.archiveExtractAction,
          controllers: [_destination],
          enabled: !_checking,
          onPressed: () => unawaited(_submit()),
        ),
      ],
    );
  }

  /// The folder an archive goes into: its name without the archive's
  /// extensions.
  String _folderName(ExtractSource archive) => archiveStem(archive.name);
}

/// [name] without its archive extensions: `site.tar.gz` → `site`, as the
/// core names the folder.
String archiveStem(String name) {
  final lower = name.toLowerCase();
  for (final suffix in const [
    '.tar.gz',
    '.tar.bz2',
    '.tar.xz',
    '.tar.zst',
    '.tar.zstd',
    '.tar.lz4',
  ]) {
    if (lower.endsWith(suffix) && lower.length > suffix.length) {
      return name.substring(0, name.length - suffix.length);
    }
  }
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/// The texts a destination completes to: the folders under the one it
/// points into whose names start with what follows its last separator.
/// [peek] lists a folder's folders; [home] and [base] resolve `~` and a
/// relative path.
Future<List<String>> completeFolderPath(
  String text, {
  required String home,
  required String base,
  required Future<List<String>> Function(String folder) peek,
}) async {
  final slash = PathText.lastSeparator(text);
  final dirPart = slash < 0 ? '' : text.substring(0, slash + 1);
  final prefix = text.substring(slash + 1).toLowerCase();
  final String folder;
  if (dirPart.isEmpty) {
    folder = text.startsWith('~') ? home : base;
  } else if (dirPart.startsWith('~')) {
    folder = '$home${dirPart.substring(1)}';
  } else if (PathText.isAbsolute(dirPart)) {
    folder = dirPart;
  } else {
    folder = PathText.join(base, dirPart);
  }
  if (dirPart.isEmpty && text.startsWith('~')) {
    return text == '~' ? ['~/'] : const [];
  }
  final names = await peek(folder);
  final matching = [
    for (final name in names)
      if (name.toLowerCase().startsWith(prefix)) name,
  ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [for (final name in matching) '$dirPart$name/'];
}
