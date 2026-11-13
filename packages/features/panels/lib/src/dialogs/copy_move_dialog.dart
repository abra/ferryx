import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:material_ui/material_ui.dart';

import '../path_text.dart';
import 'dialog_support.dart';

/// What the Copy or Move dialog answered.
class CopyMoveChoice {
  const CopyMoveChoice({
    required this.destination,
    required this.newName,
    required this.preserveAttributes,
    required this.verify,
    required this.conflicts,
  });

  /// The folder written into.
  final String destination;

  /// Copy As / Move As: the one item's new name.
  final String? newName;
  final bool preserveAttributes;
  final bool verify;
  final ConflictPolicy conflicts;
}

/// Copy To / Move To (a destination), or Copy As / Move As (a new name
/// in the same folder, which may be a path into a subfolder).
Future<CopyMoveChoice?> showCopyMoveDialog(
  BuildContext context, {
  required bool move,
  required bool asName,
  required List<String> names,
  required String currentFolder,
  required String defaultDestination,
  required bool preserveAttributes,
  required bool verify,
  bool canVerify = true,
}) => showWorkspaceDialog<CopyMoveChoice>(
  context,
  (context) => _CopyMoveDialog(
    move: move,
    asName: asName,
    names: names,
    currentFolder: currentFolder,
    defaultDestination: defaultDestination,
    preserveAttributes: preserveAttributes,
    verify: verify,
    canVerify: canVerify,
  ),
);

class _CopyMoveDialog extends StatefulWidget {
  const _CopyMoveDialog({
    required this.move,
    required this.asName,
    required this.names,
    required this.currentFolder,
    required this.defaultDestination,
    required this.preserveAttributes,
    required this.verify,
    required this.canVerify,
  });

  final bool move;
  final bool asName;
  final List<String> names;
  final String currentFolder;
  final String defaultDestination;
  final bool preserveAttributes;
  final bool verify;

  /// The copy can be read back (not over the network).
  final bool canVerify;

  @override
  State<_CopyMoveDialog> createState() => _CopyMoveDialogState();
}

class _CopyMoveDialogState extends State<_CopyMoveDialog> {
  late final TextEditingController _target = TextEditingController(
    text: widget.asName ? widget.names.first : widget.defaultDestination,
  );
  late bool _preserve = widget.preserveAttributes;
  late bool _verify = widget.verify;
  ConflictPolicy _conflicts = ConflictPolicy.ask;

  @override
  void initState() {
    super.initState();
    if (widget.asName) {
      final name = widget.names.first;
      final dot = name.lastIndexOf('.');
      _target.selection = TextSelection(
        baseOffset: 0,
        extentOffset: dot > 0 ? dot : name.length,
      );
    } else {
      _target.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _target.text.length,
      );
    }
  }

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _target.text.trim();
    if (text.isEmpty) return;
    final CopyMoveChoice choice;
    if (widget.asName) {
      // `name` stays in the folder; `sub/name` goes into its subfolder; an
      // absolute path names the folder outright.
      final parent = PathText.parentOf(text);
      final folder = parent == null
          ? widget.currentFolder
          : PathText.isAbsolute(text)
          ? parent
          : PathText.join(widget.currentFolder, parent);
      final name = parent == null ? text : PathText.baseName(text);
      choice = CopyMoveChoice(
        destination: folder,
        newName: name.isEmpty ? null : name,
        preserveAttributes: _preserve,
        verify: _verify,
        conflicts: _conflicts,
      );
    } else {
      final destination = PathText.isAbsolute(text)
          ? text
          : PathText.join(widget.currentFolder, text);
      choice = CopyMoveChoice(
        destination: destination,
        newName: null,
        preserveAttributes: _preserve,
        verify: _verify,
        conflicts: _conflicts,
      );
    }
    Navigator.of(context).pop(choice);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final count = widget.names.length;
    final name = firstName(widget.names);
    final title = widget.asName
        ? (widget.move ? l10n.moveAsTitle(name) : l10n.copyAsTitle(name))
        : (widget.move
              ? l10n.moveDialogTitle(count, name)
              : l10n.copyDialogTitle(count, name));
    return AppDialog(
      title: title,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DialogField(
            label: widget.asName ? l10n.newNameLabel : l10n.destinationLabel,
            controller: _target,
            autofocus: true,
            monospace: !widget.asName,
            onSubmitted: (_) => _submit(),
          ),
          dialogRowGap,
          DialogToggle(
            label: l10n.optionPreserveAttributes,
            value: _preserve,
            onChanged: (v) => setState(() => _preserve = v),
          ),
          if (!widget.move && widget.canVerify) ...[
            const SizedBox(height: AppSpacing.sm),
            DialogToggle(
              label: l10n.optionVerify,
              value: _verify,
              onChanged: (v) => setState(() => _verify = v),
            ),
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
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        DialogSubmitButton(
          label: widget.move ? l10n.actionMove : l10n.actionCopy,
          controllers: [_target],
          onPressed: _submit,
        ),
      ],
    );
  }
}
