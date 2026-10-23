import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dialog_parts.dart';

/// Asks the user [question] in its dialog; answers `null` when the dialog
/// was closed because the question no longer waits ([withdrawn] took its
/// id).
Future<NetworkAnswer?> showNetworkQuestion(
  BuildContext context,
  NetworkQuestion question, {
  required ValueListenable<Set<int>> withdrawn,
}) => showAppDialog<NetworkAnswer>(
  context,
  (context) => _Withdrawable(
    id: question.id,
    withdrawn: withdrawn,
    child: switch (question) {
      HostKeyQuestion() => HostKeyDialog(question: question),
      PasswordQuestion() => SecretDialog.password(question),
      PassphraseQuestion() => SecretDialog.passphrase(question),
      PromptsQuestion() => PromptsDialog(question: question),
    },
  ),
);

/// Closes its dialog (answering `null`) once [withdrawn] has [id].
class _Withdrawable extends StatefulWidget {
  const _Withdrawable({
    required this.id,
    required this.withdrawn,
    required this.child,
  });

  final int id;
  final ValueListenable<Set<int>> withdrawn;
  final Widget child;

  @override
  State<_Withdrawable> createState() => _WithdrawableState();
}

class _WithdrawableState extends State<_Withdrawable> {
  @override
  void initState() {
    super.initState();
    widget.withdrawn.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    widget.withdrawn.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (!mounted || !widget.withdrawn.value.contains(widget.id)) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The host of the server: from the key `sftp://me@host:22`, as it reads.
String _serverLabel(String server) =>
    ServerKey.parse(server)?.displayRoot ?? server;

/// A password, or a key file's passphrase: the field, the wrong one said
/// when it is asked again, and whether the keychain keeps it.
class SecretDialog extends StatefulWidget {
  const SecretDialog._({
    required this.title,
    required this.message,
    required this.retryMessage,
    required this.label,
    required this.retry,
  });

  factory SecretDialog.password(PasswordQuestion question) => SecretDialog._(
    title: (l10n) => l10n.networkPasswordTitle(_serverLabel(question.server)),
    message: (l10n) => question.user.isEmpty
        ? null
        : l10n.networkPasswordMessage(question.user),
    retryMessage: (l10n) => l10n.networkPasswordWrong,
    label: (l10n) => l10n.networkPasswordLabel,
    retry: question.retry,
  );

  factory SecretDialog.passphrase(PassphraseQuestion question) =>
      SecretDialog._(
        title: (l10n) => l10n.networkPassphraseTitle,
        message: (l10n) => l10n.networkPassphraseMessage(question.keyPath),
        retryMessage: (l10n) => l10n.networkPassphraseWrong,
        label: (l10n) => l10n.networkPassphraseLabel,
        retry: question.retry,
      );

  final String Function(FerryxLocalizations l10n) title;
  final String? Function(FerryxLocalizations l10n) message;
  final String Function(FerryxLocalizations l10n) retryMessage;
  final String Function(FerryxLocalizations l10n) label;
  final bool retry;

  @override
  State<SecretDialog> createState() => _SecretDialogState();
}

class _SecretDialogState extends State<SecretDialog> {
  final _secret = TextEditingController();
  bool _remember = false;

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  void _submit() {
    if (_secret.text.isEmpty) return;
    Navigator.of(context).pop(
      NetworkAnswer(accept: true, texts: [_secret.text], remember: _remember),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final message = widget.message(l10n);
    return AppDialog(
      title: widget.title(l10n),
      width: AppSizes.compactDialogWidth,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message != null) ...[
            Text(
              message,
              style: context.text.bodyMedium?.copyWith(
                color: context.appColors.textMuted,
              ),
            ),
            networkRowGap,
          ],
          NetworkField(
            label: widget.label(l10n),
            controller: _secret,
            autofocus: true,
            obscure: true,
            onSubmitted: (_) => _submit(),
          ),
          if (widget.retry) ...[
            const SizedBox(height: AppSpacing.xs),
            NetworkNote.error(context, widget.retryMessage(l10n)),
          ],
          const SizedBox(height: AppSpacing.sm),
          AppCheckbox(
            value: _remember,
            label: l10n.networkRememberPassword,
            onChanged: (value) => setState(() => _remember = value),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () =>
              Navigator.of(context).pop(const NetworkAnswer.cancel()),
          child: Text(l10n.actionCancel),
        ),
        ListenableBuilder(
          listenable: _secret,
          builder: (context, _) => FilledButton(
            onPressed: _secret.text.isEmpty ? null : _submit,
            child: Text(l10n.networkConnect),
          ),
        ),
      ],
    );
  }
}

/// An SSH key no known_hosts file has: its fingerprint, as OpenSSH shows
/// it, to compare with the one the server's administrator gave. Trusting
/// is never the default: Return cancels.
class HostKeyDialog extends StatefulWidget {
  const HostKeyDialog({required this.question, super.key});

  final HostKeyQuestion question;

  @override
  State<HostKeyDialog> createState() => _HostKeyDialogState();
}

class _HostKeyDialogState extends State<HostKeyDialog> {
  bool _remember = true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final question = widget.question;
    final host = question.port == ServerProtocol.sftp.defaultPort
        ? question.host
        : '${question.host}:${question.port}';
    return AppDialog(
      title: l10n.networkHostKeyTitle,
      width: AppSizes.compactDialogWidth,
      // Trust is not what Return does: it would accept blind.
      destructive: true,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.networkHostKeyMessage(host, question.algorithm),
            style: context.text.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          _Fingerprint(question.fingerprint),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.networkHostKeyAdvice,
            style: context.text.bodySmall?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppCheckbox(
            value: _remember,
            label: l10n.networkHostKeyRemember,
            onChanged: (value) => setState(() => _remember = value),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () =>
              Navigator.of(context).pop(const NetworkAnswer.cancel()),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(NetworkAnswer(accept: true, remember: _remember)),
          child: Text(l10n.networkHostKeyTrust),
        ),
      ],
    );
  }
}

/// A fingerprint in the monospace face on a sunken field, selectable to
/// copy; it wraps rather than hides a character.
class _Fingerprint extends StatelessWidget {
  const _Fingerprint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: context.appColors.surfaceSunken,
      borderRadius: BorderRadius.circular(context.metrics.radius.control),
      border: AppBorder.fromBorderSide(
        BorderSide(color: context.appColors.line),
      ),
    ),
    child: SelectableText(text, style: context.mono),
  );
}

/// The server's own prompts (keyboard-interactive): a field each, hidden
/// unless the server says what is typed may show.
class PromptsDialog extends StatefulWidget {
  const PromptsDialog({required this.question, super.key});

  final PromptsQuestion question;

  @override
  State<PromptsDialog> createState() => _PromptsDialogState();
}

class _PromptsDialogState extends State<PromptsDialog> {
  late final _fields = [
    for (final _ in widget.question.prompts) TextEditingController(),
  ];

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(
    NetworkAnswer(
      accept: true,
      texts: [for (final field in _fields) field.text],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final question = widget.question;
    final title = question.name.trim().isNotEmpty
        ? question.name.trim()
        : l10n.networkPromptsTitle(_serverLabel(question.server));
    return AppDialog(
      title: title,
      width: AppSizes.compactDialogWidth,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (question.instructions.trim().isNotEmpty) ...[
            Text(
              question.instructions.trim(),
              style: context.text.bodyMedium?.copyWith(
                color: context.appColors.textMuted,
              ),
            ),
            networkRowGap,
          ],
          for (var i = 0; i < question.prompts.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            NetworkField(
              label: question.prompts[i].$1.trim().replaceAll(
                RegExp(r':$'),
                '',
              ),
              controller: _fields[i],
              autofocus: i == 0,
              obscure: !question.prompts[i].$2,
              onSubmitted: i == question.prompts.length - 1
                  ? (_) => _submit()
                  : null,
            ),
          ],
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () =>
              Navigator.of(context).pop(const NetworkAnswer.cancel()),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.networkContinue)),
      ],
    );
  }
}

/// A server whose SSH key is not the one on record: an alarm, the core's
/// words (the known_hosts file and its line), and no way to go on.
Future<void> showHostKeyChangedDialog(
  BuildContext context, {
  required String server,
  required String detail,
}) => showAppDialog<void>(
  context,
  (context) => HostKeyChangedDialog(server: server, detail: detail),
);

class HostKeyChangedDialog extends StatelessWidget {
  const HostKeyChangedDialog({
    required this.server,
    required this.detail,
    super.key,
  });

  final String server;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final danger = context.appColors.danger;
    return AppDialog(
      title: l10n.networkHostKeyChangedTitle,
      width: AppSizes.compactDialogWidth,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(AppIcons.shieldAlert, color: danger, size: AppIconSize.xl),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  l10n.networkHostKeyChangedMessage(_serverLabel(server)),
                  style: context.text.bodyMedium?.copyWith(color: danger),
                ),
              ),
            ],
          ),
          networkRowGap,
          Text(
            l10n.networkHostKeyChangedAdvice,
            style: context.text.bodySmall?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            SelectableText(
              detail,
              style: context.mono.copyWith(
                fontSize: context.text.bodySmall?.fontSize,
              ),
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionClose),
        ),
      ],
    );
  }
}
