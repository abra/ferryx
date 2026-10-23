import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';

import 'dialog_support.dart';

/// Asks the password of the encrypted archive [name]. [submit] tries it
/// and answers the error, if any: a wrong password is said in the dialog,
/// which stays for another try. Answers whether a password was taken.
Future<bool> showArchivePasswordDialog(
  BuildContext context, {
  required String name,
  required Future<FerryxException?> Function(String password) submit,
}) async =>
    await showWorkspaceDialog<bool>(
      context,
      (context) => ArchivePasswordDialog(name: name, submit: submit),
    ) ??
    false;

class ArchivePasswordDialog extends StatefulWidget {
  const ArchivePasswordDialog({
    required this.name,
    required this.submit,
    super.key,
  });

  final String name;
  final Future<FerryxException?> Function(String password) submit;

  @override
  State<ArchivePasswordDialog> createState() => _ArchivePasswordDialogState();
}

class _ArchivePasswordDialogState extends State<ArchivePasswordDialog> {
  final _password = TextEditingController();
  final _focus = FocusNode(debugLabel: 'archive password');
  FerryxException? _error;
  bool _checking = false;

  @override
  void dispose() {
    _password.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _password.text;
    if (password.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final error = await widget.submit(password);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _checking = false;
      _error = error;
    });
    _focus.requestFocus();
    _password.selection = TextSelection(
      baseOffset: 0,
      extentOffset: password.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final error = _error;
    return AppDialog(
      title: l10n.archivePasswordTitle(widget.name),
      width: AppSizes.compactDialogWidth,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.archivePasswordMessage,
            style: context.text.bodyMedium?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
          dialogRowGap,
          DialogField(
            label: l10n.archivePasswordLabel,
            controller: _password,
            focusNode: _focus,
            autofocus: true,
            obscure: true,
            readOnly: _checking,
            onSubmitted: (_) => unawaited(_submit()),
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              error.kind == FerryxErrorKind.wrongPassword
                  ? l10n.archiveWrongPasswordFor(widget.name)
                  : l10n.errorMessage(error),
              style: context.text.bodySmall?.copyWith(
                color: context.appColors.danger,
              ),
            ),
          ],
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.actionCancel),
        ),
        DialogSubmitButton(
          label: l10n.archivePasswordOpen,
          controllers: [_password],
          enabled: !_checking,
          onPressed: () => unawaited(_submit()),
        ),
      ],
    );
  }
}
