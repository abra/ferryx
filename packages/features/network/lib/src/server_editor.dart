import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'dialog_parts.dart';

/// A saved server's settings: everything to connect but the password.
/// Answers the server as edited, or `null` when cancelled. [server] is the
/// one edited, or the start of a new one; [onForgetPassword] (an edited
/// server only) forgets the password the keychain keeps for it.
Future<ServerProfile?> showServerEditor(
  BuildContext context, {
  required ServerProfile server,
  required bool isNew,
  Future<void> Function(ServerProfile server)? onForgetPassword,
}) => showAppDialog<ServerProfile>(
  context,
  (context) => ServerEditor(
    server: server,
    isNew: isNew,
    onForgetPassword: onForgetPassword,
  ),
);

class ServerEditor extends StatefulWidget {
  const ServerEditor({
    required this.server,
    required this.isNew,
    this.onForgetPassword,
    super.key,
  });

  final ServerProfile server;
  final bool isNew;
  final Future<void> Function(ServerProfile server)? onForgetPassword;

  @override
  State<ServerEditor> createState() => _ServerEditorState();
}

class _ServerEditorState extends State<ServerEditor> {
  late final _name = TextEditingController(text: widget.server.name);
  late final _host = TextEditingController(text: widget.server.host);
  late final _port = TextEditingController(
    text: widget.server.port == 0 ? '' : '${widget.server.port}',
  );
  late final _user = TextEditingController(text: widget.server.user);
  late final _path = TextEditingController(text: widget.server.path);
  late final _key = TextEditingController(text: widget.server.keyPath);
  late ServerProtocol _protocol = widget.server.protocol;
  late ServerAuth _auth = widget.server.auth;
  String? _problem;

  @override
  void dispose() {
    for (final field in [_name, _host, _port, _user, _path, _key]) {
      field.dispose();
    }
    super.dispose();
  }

  ServerProfile get _edited => widget.server.copyWith(
    name: _name.text.trim(),
    protocol: _protocol,
    host: _host.text.trim(),
    port: int.tryParse(_port.text.trim()) ?? 0,
    user: _user.text.trim(),
    path: _path.text.trim(),
    auth: _protocol.hasKeys ? _auth : ServerAuth.password,
    keyPath: _protocol.hasKeys && _auth == ServerAuth.key
        ? _key.text.trim()
        : '',
  );

  void _save() {
    final l10n = context.l10n;
    final host = _host.text.trim();
    final port = _port.text.trim();
    final problem = host.isEmpty || host.contains(RegExp(r'[\s/]'))
        ? l10n.networkHostRequired
        : port.isNotEmpty &&
              ((int.tryParse(port) ?? 0) < 1 || int.parse(port) > 65535)
        ? l10n.networkPortInvalid
        : null;
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.of(context).pop(_edited);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final forget = widget.onForgetPassword;
    return AppDialog(
      title: widget.isNew ? l10n.networkServerNew : l10n.networkServerEdit,
      width: AppSizes.compactDialogWidth,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NetworkField(
            label: l10n.networkFieldName,
            controller: _name,
            hint: l10n.networkFieldNameHint,
            autofocus: true,
            onSubmitted: (_) => _save(),
          ),
          networkRowGap,
          AppControlRow(
            label: l10n.networkFieldProtocol,
            control: AppPopupButton<ServerProtocol>(
              value: _protocol,
              items: [
                for (final protocol in ServerProtocol.values)
                  (protocol, l10n.protocolLabel(protocol)),
              ],
              onChanged: (protocol) => setState(() => _protocol = protocol),
            ),
          ),
          if (!_protocol.secure) ...[
            const SizedBox(height: AppSpacing.xs),
            NetworkNote.insecure(context, l10n.networkInsecure),
          ],
          networkRowGap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: NetworkField(
                  label: l10n.networkFieldHost,
                  controller: _host,
                  onSubmitted: (_) => _save(),
                ),
              ),
              SizedBox(width: context.metrics.toolbarSpacing),
              SizedBox(
                width: AppSizes.portFieldWidth,
                child: NetworkField(
                  label: l10n.networkFieldPort,
                  controller: _port,
                  hint: '${_protocol.defaultPort}',
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(5),
                  ],
                  onSubmitted: (_) => _save(),
                ),
              ),
            ],
          ),
          networkRowGap,
          NetworkField(
            label: l10n.networkFieldUser,
            controller: _user,
            hint: _protocol.hasKeys ? null : l10n.networkFieldUserHint,
            onSubmitted: (_) => _save(),
          ),
          networkRowGap,
          NetworkField(
            label: l10n.networkFieldFolder,
            controller: _path,
            hint: l10n.networkFieldFolderHint,
            monospace: true,
            onSubmitted: (_) => _save(),
          ),
          if (_protocol.hasKeys) ...[
            networkRowGap,
            AppControlRow(
              label: l10n.networkFieldAuth,
              control: AppPopupButton<ServerAuth>(
                value: _auth,
                items: [
                  for (final auth in ServerAuth.values)
                    (auth, l10n.authLabel(auth)),
                ],
                onChanged: (auth) => setState(() => _auth = auth),
              ),
            ),
            if (_auth == ServerAuth.key) ...[
              networkRowGap,
              NetworkField(
                label: l10n.networkFieldKey,
                controller: _key,
                hint: l10n.networkFieldKeyHint,
                monospace: true,
                onSubmitted: (_) => _save(),
              ),
            ],
          ],
          if (forget != null && !widget.isNew) ...[
            networkRowGap,
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                style: AppButtonStyles.small(context),
                onPressed: () => forget(widget.server),
                icon: const Icon(AppIcons.keyFile, size: AppIconSize.sm),
                label: Text(l10n.networkForgetPassword),
              ),
            ),
          ],
          if (_problem case final problem?) ...[
            const SizedBox(height: AppSpacing.sm),
            NetworkNote.error(context, problem),
          ],
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(onPressed: _save, child: Text(l10n.actionSave)),
      ],
    );
  }
}
