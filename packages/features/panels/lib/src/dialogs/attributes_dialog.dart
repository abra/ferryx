import 'dart:math' as math;

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/material.dart';

import '../path_text.dart';
import 'dialog_support.dart';

/// File Attributes (⌃A): permissions, flags, owner, group and dates of
/// one or several items; answers whether anything was changed.
Future<bool> showAttributesDialog(
  BuildContext context, {
  required List<String> paths,
  required FileRepository files,
}) async {
  final attributes = <FileAttributes>[];
  for (final path in paths) {
    try {
      attributes.add(await files.readAttributes(path));
    } on FerryxException catch (error) {
      if (context.mounted) {
        showAppNotice(context, context.l10n.errorMessage(error));
      }
      return false;
    }
  }
  if (attributes.isEmpty || !context.mounted) return false;
  final changed = await showWorkspaceDialog<bool>(
    context,
    (context) => _AttributesDialog(attributes: attributes, files: files),
  );
  return changed ?? false;
}

/// A bit as the items have it: on all, off all, or mixed.
enum _Bit { on, off, mixed }

class _AttributesDialog extends StatefulWidget {
  const _AttributesDialog({required this.attributes, required this.files});

  final List<FileAttributes> attributes;
  final FileRepository files;

  @override
  State<_AttributesDialog> createState() => _AttributesDialogState();
}

class _AttributesDialogState extends State<_AttributesDialog> {
  /// The bits the user set or cleared; every other bit stays as each item
  /// has it.
  final _permissions = <int, bool>{};
  final _flags = <int, bool>{};
  late final TextEditingController _owner;
  late final TextEditingController _group;
  final _modified = TextEditingController();
  final _accessed = TextEditingController();
  bool _recursive = false;
  bool _applying = false;
  String? _ownerError;
  String? _groupError;
  String? _modifiedError;
  String? _accessedError;

  List<FileAttributes> get _items => widget.attributes;

  bool get _several => _items.length > 1;

  bool get _hasFolder => _items.any((a) => a.isDir);

  /// The items carry BSD flags (a file system that keeps them): the
  /// flags are offered; elsewhere there are none to set.
  bool get _hasFlags => _items.any((a) => a.supportsFlags || a.flags != 0);

  @override
  void initState() {
    super.initState();
    _owner = TextEditingController(text: _common((a) => a.owner) ?? '');
    _group = TextEditingController(text: _common((a) => a.group) ?? '');
    final modified = _commonTime((a) => a.modified);
    final accessed = _commonTime((a) => a.accessed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l10n = context.l10n;
      _modified.text = modified == null ? '' : l10n.dateTimeField(modified);
      _accessed.text = accessed == null ? '' : l10n.dateTimeField(accessed);
    });
  }

  @override
  void dispose() {
    _owner.dispose();
    _group.dispose();
    _modified.dispose();
    _accessed.dispose();
    super.dispose();
  }

  /// The value every item shares, or `null` when they differ.
  T? _common<T>(T Function(FileAttributes a) pick) {
    final first = pick(_items.first);
    return _items.every((a) => pick(a) == first) ? first : null;
  }

  DateTime? _commonTime(DateTime? Function(FileAttributes a) pick) {
    final first = pick(_items.first);
    if (first == null) return null;
    final minute = DateTime(
      first.year,
      first.month,
      first.day,
      first.hour,
      first.minute,
    );
    for (final item in _items) {
      final time = pick(item);
      if (time == null) return null;
      final other = DateTime(
        time.year,
        time.month,
        time.day,
        time.hour,
        time.minute,
      );
      if (other != minute) return null;
    }
    return first;
  }

  _Bit _bitOf(int Function(FileAttributes a) field, int bit) {
    final set = _items.where((a) => field(a) & bit != 0).length;
    if (set == 0) return _Bit.off;
    if (set == _items.length) return _Bit.on;
    return _Bit.mixed;
  }

  /// What a checkbox shows: the user's choice, else the items' state.
  bool? _value(
    Map<int, bool> chosen,
    int Function(FileAttributes a) field,
    int bit,
  ) {
    final choice = chosen[bit];
    if (choice != null) return choice;
    return switch (_bitOf(field, bit)) {
      _Bit.on => true,
      _Bit.off => false,
      _Bit.mixed => null,
    };
  }

  void _toggle(
    Map<int, bool> chosen,
    int Function(FileAttributes a) field,
    int bit,
  ) {
    setState(() {
      final current = _value(chosen, field, bit);
      // Mixed goes to on, on to off, off to on.
      chosen[bit] = current != true;
    });
  }

  DateTime? _parseTime(String text) {
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$',
    ).firstMatch(text.trim());
    if (match == null) return null;
    final parts = [for (var i = 1; i <= 5; i++) int.parse(match.group(i)!)];
    final time = DateTime(parts[0], parts[1], parts[2], parts[3], parts[4]);
    final valid =
        time.year == parts[0] && time.month == parts[1] && time.day == parts[2];
    return valid ? time : null;
  }

  Future<void> _apply() async {
    if (_applying) return;
    final l10n = context.l10n;
    final files = widget.files;
    setState(() {
      _applying = true;
      _ownerError = null;
      _groupError = null;
      _modifiedError = null;
      _accessedError = null;
    });
    var permissionsSet = 0;
    var permissionsClear = 0;
    for (final entry in _permissions.entries) {
      if (entry.value) {
        permissionsSet |= entry.key;
      } else {
        permissionsClear |= entry.key;
      }
    }
    var flagsSet = 0;
    var flagsClear = 0;
    for (final entry in _flags.entries) {
      if (entry.value) {
        flagsSet |= entry.key;
      } else {
        flagsClear |= entry.key;
      }
    }
    int? uid;
    int? gid;
    final owner = _owner.text.trim();
    if (owner.isNotEmpty && owner != _common((a) => a.owner)) {
      uid = await files.lookupUser(owner);
      if (uid == null) {
        if (mounted) {
          setState(() {
            _applying = false;
            _ownerError = l10n.attributesUnknownUser(owner);
          });
        }
        return;
      }
    }
    final group = _group.text.trim();
    if (group.isNotEmpty && group != _common((a) => a.group)) {
      gid = await files.lookupGroup(group);
      if (gid == null) {
        if (mounted) {
          setState(() {
            _applying = false;
            _groupError = l10n.attributesUnknownGroup(group);
          });
        }
        return;
      }
    }
    DateTime? modified;
    DateTime? accessed;
    final modifiedText = _modified.text.trim();
    if (modifiedText.isNotEmpty) {
      modified = _parseTime(modifiedText);
      if (modified == null) {
        setState(() {
          _applying = false;
          _modifiedError = l10n.attributesInvalidDate;
        });
        return;
      }
      final original = _commonTime((a) => a.modified);
      if (original != null &&
          _parseTime(l10n.dateTimeField(original)) == modified) {
        modified = null;
      }
    }
    final accessedText = _accessed.text.trim();
    if (accessedText.isNotEmpty) {
      accessed = _parseTime(accessedText);
      if (accessed == null) {
        setState(() {
          _applying = false;
          _accessedError = l10n.attributesInvalidDate;
        });
        return;
      }
      final original = _commonTime((a) => a.accessed);
      if (original != null &&
          _parseTime(l10n.dateTimeField(original)) == accessed) {
        accessed = null;
      }
    }
    final changes = AttributeChanges(
      permissionsSet: permissionsSet,
      permissionsClear: permissionsClear,
      uid: uid,
      gid: gid,
      flagsSet: flagsSet,
      flagsClear: flagsClear,
      modified: modified,
      accessed: accessed,
    );
    if (!mounted) return;
    if (changes.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    try {
      final failures = await files.applyAttributes(
        [for (final a in _items) a.path],
        changes,
        recursive: _recursive && _hasFolder,
      );
      if (!mounted) return;
      if (failures.isNotEmpty) {
        showAppNotice(context, l10n.attributesFailed(failures.length));
      }
      Navigator.of(context).pop(failures.length < _items.length);
    } on FerryxException catch (error) {
      if (!mounted) return;
      setState(() => _applying = false);
      showAppNotice(context, l10n.errorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final created = _commonTime((a) => a.created);
    return AppDialog(
      title: l10n.attributesTitle(
        _items.length,
        PathText.baseName(_items.first.path),
      ),
      body: AppDialogScrollBody(
        maxHeight: dialogBodyMaxHeight(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.permissionsLabel, style: context.text.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            _PermissionsGrid(
              value: (bit) => _value(_permissions, (a) => a.permissions, bit),
              onToggle: (bit) =>
                  _toggle(_permissions, (a) => a.permissions, bit),
            ),
            if (_hasFlags) ...[
              dialogRowGap,
              Text(l10n.flagsLabel, style: context.text.labelMedium),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final (bit, label) in [
                    (FileFlags.hidden, l10n.flagHidden),
                    (FileFlags.userImmutable, l10n.flagLocked),
                    (FileFlags.userAppend, l10n.flagAppendOnly),
                    (FileFlags.noDump, l10n.flagNoDump),
                    (FileFlags.archived, l10n.flagArchived),
                  ])
                    _BitCheckbox(
                      label: label,
                      value: _value(_flags, (a) => a.flags, bit),
                      onToggle: () => _toggle(_flags, (a) => a.flags, bit),
                    ),
                ],
              ),
            ],
            dialogRowGap,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.md,
              children: [
                Expanded(
                  child: _FieldWithError(
                    field: DialogField(
                      label: l10n.ownerLabel,
                      controller: _owner,
                      hint: _several ? '—' : null,
                      onSubmitted: (_) => _apply(),
                    ),
                    error: _ownerError,
                  ),
                ),
                Expanded(
                  child: _FieldWithError(
                    field: DialogField(
                      label: l10n.groupLabel,
                      controller: _group,
                      hint: _several ? '—' : null,
                      onSubmitted: (_) => _apply(),
                    ),
                    error: _groupError,
                  ),
                ),
              ],
            ),
            dialogRowGap,
            Text(l10n.timesLabel, style: context.text.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.md,
              children: [
                Expanded(
                  child: _FieldWithError(
                    field: DialogField(
                      label: l10n.modifiedLabel,
                      controller: _modified,
                      monospace: true,
                      hint: l10n.dateFieldHint,
                      onSubmitted: (_) => _apply(),
                    ),
                    error: _modifiedError,
                  ),
                ),
                Expanded(
                  child: _FieldWithError(
                    field: DialogField(
                      label: l10n.accessedLabel,
                      controller: _accessed,
                      monospace: true,
                      hint: l10n.dateFieldHint,
                      onSubmitted: (_) => _apply(),
                    ),
                    error: _accessedError,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            AppLabelRow(
              label: Text(
                l10n.createdLabel,
                style: context.text.bodyMedium?.copyWith(
                  color: colors.textMuted,
                ),
              ),
              trailing: Text(
                created == null ? '—' : l10n.dateTime(created),
                style: context.text.bodyMedium?.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ),
            if (_hasFolder) ...[
              dialogRowGap,
              DialogToggle(
                label: l10n.applyRecursively,
                value: _recursive,
                onChanged: (v) => setState(() => _recursive = v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _applying ? null : _apply,
          child: Text(l10n.actionApply),
        ),
      ],
    );
  }
}

/// The tallest a scrolling dialog body gets: a panel dialog's height, or
/// what the window leaves past the dialog's inset, title, buttons and
/// margins ([appDialogBodyMaxHeight]).
double dialogBodyMaxHeight(BuildContext context) =>
    math.min(AppSizes.panelDialogHeight, appDialogBodyMaxHeight(context));

/// Owner, group and others against read, write and execute, with the
/// special bits under them.
class _PermissionsGrid extends StatelessWidget {
  const _PermissionsGrid({required this.value, required this.onToggle});

  final bool? Function(int bit) value;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final header = context.text.labelSmall?.copyWith(color: colors.textMuted);
    final rows = [
      (
        l10n.permOwner,
        [
          Permissions.ownerRead,
          Permissions.ownerWrite,
          Permissions.ownerExecute,
        ],
      ),
      (
        l10n.permGroup,
        [
          Permissions.groupRead,
          Permissions.groupWrite,
          Permissions.groupExecute,
        ],
      ),
      (
        l10n.permOthers,
        [
          Permissions.othersRead,
          Permissions.othersWrite,
          Permissions.othersExecute,
        ],
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Table(
          columnWidths: const {0: IntrinsicColumnWidth()},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                const SizedBox.shrink(),
                for (final label in [
                  l10n.permRead,
                  l10n.permWrite,
                  l10n.permExecute,
                ])
                  Text(label, style: header, textAlign: TextAlign.center),
              ],
            ),
            for (final (label, bits) in rows)
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.md),
                    child: Text(label, style: context.text.bodyMedium),
                  ),
                  for (final bit in bits)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xxs,
                      ),
                      child: Center(
                        child: _BitCheckbox(
                          value: value(bit),
                          onToggle: () => onToggle(bit),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.xs,
          children: [
            for (final (bit, label) in [
              (Permissions.setUid, l10n.permSetUid),
              (Permissions.setGid, l10n.permSetGid),
              (Permissions.sticky, l10n.permSticky),
            ])
              _BitCheckbox(
                label: label,
                value: value(bit),
                onToggle: () => onToggle(bit),
              ),
          ],
        ),
      ],
    );
  }
}

/// A bit's check box: `null` (the bit set on some items only) shows
/// clear, and the first press sets it everywhere.
class _BitCheckbox extends StatelessWidget {
  const _BitCheckbox({required this.value, required this.onToggle, this.label});

  final bool? value;
  final VoidCallback onToggle;
  final String? label;

  @override
  Widget build(BuildContext context) => AppCheckbox(
    value: value ?? false,
    mixed: value == null,
    onChanged: (_) => onToggle(),
    label: label,
  );
}

/// A field with its error, if any, under it.
class _FieldWithError extends StatelessWidget {
  const _FieldWithError({required this.field, required this.error});

  final Widget field;
  final String? error;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      field,
      if (error != null) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          error!,
          style: context.text.bodySmall?.copyWith(
            color: context.appColors.danger,
          ),
        ),
      ],
    ],
  );
}
