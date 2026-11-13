import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:material_ui/material_ui.dart';

import 'dialog_support.dart';

export 'compress_dialog.dart';

/// F7: a folder's name, or a nested path of folders.
Future<String?> showCreateDirectoryDialog(
  BuildContext context, {
  required bool opposite,
}) {
  final l10n = context.l10n;
  return showWorkspaceDialog<String>(
    context,
    (context) => _TextDialog(
      title: opposite
          ? l10n.createDirectoryInOppositeTitle
          : l10n.createDirectoryTitle,
      label: l10n.createDirectoryHint,
      confirmLabel: l10n.actionCreate,
    ),
  );
}

/// ⇧⌘G: a path to go to.
Future<String?> showGoToFolderDialog(
  BuildContext context, {
  required String initial,
}) {
  final l10n = context.l10n;
  return showWorkspaceDialog<String>(
    context,
    (context) => _TextDialog(
      title: l10n.goToFolderTitle,
      label: l10n.goToFolderHint,
      confirmLabel: l10n.actionGo,
      initial: initial,
      monospace: true,
      selectAll: true,
    ),
  );
}

/// A mask or expression to select or deselect by.
class MaskChoice {
  const MaskChoice(this.mask, {required this.regex});

  final String mask;
  final bool regex;
}

Future<MaskChoice?> showSelectMaskDialog(
  BuildContext context, {
  required bool select,
}) {
  final l10n = context.l10n;
  return showWorkspaceDialog<MaskChoice>(
    context,
    (context) => _MaskDialog(
      title: select ? l10n.selectMaskTitle : l10n.deselectMaskTitle,
      confirmLabel: select ? l10n.actionSelect : l10n.actionDeselect,
    ),
  );
}

/// F8: whether to trash or delete for good.
enum DeleteChoice { trash, permanent }

Future<DeleteChoice?> showDeleteDialog(
  BuildContext context, {
  required List<String> names,
  required bool trashDefault,
  required bool trashAvailable,
  String? note,
}) => showWorkspaceDialog<DeleteChoice>(
  context,
  (context) => _DeleteDialog(
    names: names,
    trashDefault: trashDefault && trashAvailable,
    trashAvailable: trashAvailable,
    note: note,
  ),
);

/// A symbolic or hard link: what it points to and where it is made.
class LinkChoice {
  const LinkChoice({required this.target, required this.link});

  final String target;
  final String link;
}

enum LinkDialogKind { symlink, hardlink, editSymlink }

Future<LinkChoice?> showLinkDialog(
  BuildContext context, {
  required LinkDialogKind kind,
  required String target,
  required String link,
}) => showWorkspaceDialog<LinkChoice>(
  context,
  (context) => _LinkDialog(kind: kind, target: target, link: link),
);

// ─── Implementations ───

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.label,
    required this.confirmLabel,
    this.initial = '',
    this.monospace = false,
    this.selectAll = false,
  });

  final String title;
  final String label;
  final String confirmLabel;
  final String initial;
  final bool monospace;
  final bool selectAll;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void initState() {
    super.initState();
    if (widget.selectAll) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initial.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: widget.title,
    width: AppSizes.compactDialogWidth,
    body: DialogField(
      label: widget.label,
      controller: _controller,
      autofocus: true,
      monospace: widget.monospace,
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.l10n.actionCancel),
      ),
      DialogSubmitButton(
        label: widget.confirmLabel,
        controllers: [_controller],
        onPressed: _submit,
      ),
    ],
  );
}

class _MaskDialog extends StatefulWidget {
  const _MaskDialog({required this.title, required this.confirmLabel});

  final String title;
  final String confirmLabel;

  @override
  State<_MaskDialog> createState() => _MaskDialogState();
}

class _MaskDialogState extends State<_MaskDialog> {
  final _controller = TextEditingController(text: '*.');
  bool _regex = false;

  @override
  void initState() {
    super.initState();
    _controller.selection = const TextSelection.collapsed(offset: 2);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(MaskChoice(text, regex: _regex));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppDialog(
      title: widget.title,
      width: AppSizes.compactDialogWidth,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DialogField(
            label: l10n.maskLabel,
            hint: l10n.maskHint,
            controller: _controller,
            autofocus: true,
            monospace: true,
            onSubmitted: (_) => _submit(),
          ),
          dialogRowGap,
          DialogToggle(
            label: l10n.maskRegex,
            value: _regex,
            onChanged: (v) => setState(() => _regex = v),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        DialogSubmitButton(
          label: widget.confirmLabel,
          controllers: [_controller],
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// The platform's alert: Cancel, the Trash and the permanent delete as
/// its buttons. Return moves to the Trash when that is what was asked;
/// a permanent delete is never Return's (the alert is destructive, so
/// Return cancels).
class _DeleteDialog extends StatelessWidget {
  const _DeleteDialog({
    required this.names,
    required this.trashDefault,
    required this.trashAvailable,
    this.note,
  });

  final List<String> names;
  final bool trashDefault;
  final bool trashAvailable;

  /// Why there is no Trash (a server has none).
  final String? note;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    void pop(DeleteChoice choice) => Navigator.of(context).pop(choice);
    final permanent = OutlinedButton(
      onPressed: () => pop(DeleteChoice.permanent),
      style: OutlinedButton.styleFrom(foregroundColor: colors.danger),
      child: Text(l10n.deletePermanently),
    );
    // Only Return's button is the accent: the Trash when it is the
    // default, else a plain one (Return cancels a permanent delete).
    final trash = !trashAvailable
        ? null
        : trashDefault
        ? FilledButton(
            onPressed: () => pop(DeleteChoice.trash),
            child: Text(l10n.deleteToTrash),
          )
        : OutlinedButton(
            onPressed: () => pop(DeleteChoice.trash),
            child: Text(l10n.deleteToTrash),
          );
    final cancel = OutlinedButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text(l10n.actionCancel),
    );
    return AppDialog(
      title: l10n.deleteTitle(names.length, firstName(names)),
      alert: true,
      destructive: !trashDefault,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        // Each line as wide as the alert, aligned as the alert aligns.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            trashDefault
                ? l10n.deleteMessageTrash
                : l10n.deleteMessagePermanent,
          ),
          if (note case final note?) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              note,
              style: context.text.bodySmall?.copyWith(color: colors.textMuted),
            ),
          ],
        ],
      ),
      actions: [
        cancel,
        if (trashDefault) ...[permanent, ?trash] else ...[?trash, permanent],
      ],
    );
  }
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({
    required this.kind,
    required this.target,
    required this.link,
  });

  final LinkDialogKind kind;
  final String target;
  final String link;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final TextEditingController _target = TextEditingController(
    text: widget.target,
  );
  late final TextEditingController _link = TextEditingController(
    text: widget.link,
  );

  @override
  void dispose() {
    _target.dispose();
    _link.dispose();
    super.dispose();
  }

  void _submit() {
    final target = _target.text.trim();
    final link = _link.text.trim();
    if (target.isEmpty || link.isEmpty) return;
    Navigator.of(context).pop(LinkChoice(target: target, link: link));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final editing = widget.kind == LinkDialogKind.editSymlink;
    return AppDialog(
      title: switch (widget.kind) {
        LinkDialogKind.symlink => l10n.symlinkTitle,
        LinkDialogKind.hardlink => l10n.hardlinkTitle,
        LinkDialogKind.editSymlink => l10n.editSymlinkTitle,
      },
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DialogField(
            label: l10n.linkTargetLabel,
            controller: _target,
            monospace: true,
            autofocus: editing,
            onSubmitted: (_) => _submit(),
          ),
          dialogRowGap,
          DialogField(
            label: l10n.linkNameLabel,
            controller: _link,
            monospace: true,
            autofocus: !editing,
            enabled: !editing,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        DialogSubmitButton(
          label: editing ? l10n.actionSave : l10n.actionCreate,
          controllers: [_target, _link],
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// The text of a conflict's side: its size and date.
String describeSide(FerryxLocalizations l10n, ConflictSide side) {
  final parts = [
    if (side.isDir) l10n.conflictFolderLabel,
    if (side.size != null && !side.isDir) l10n.fileSize(side.size!),
    if (side.modified != null) l10n.dateTime(side.modified!),
  ];
  return parts.isEmpty ? '' : parts.reduce(l10n.joinedDetails);
}
