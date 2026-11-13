import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:network_service/network_service.dart';
import 'package:shortcuts/shortcuts.dart';

import 'connect_cubit.dart';
import 'dialog_parts.dart';
import 'prompt_dialogs.dart';
import 'server_editor.dart';

/// Connect to Server (⌘K): an address to type (`sftp://me@host/srv`,
/// `ftp://…`, `davs://…`, `https://…`), the saved servers and the
/// addresses connected to lately under it, with add, edit and remove.
/// ↑ ↓ in the field walk the list, Return connects; the dialog stays
/// while the connection is made (its questions come over it) and closes
/// with it. Answers the connection, or `null` when cancelled.
Future<ServerConnection?> showConnectDialog(
  BuildContext context, {
  required NetworkService service,
  required List<ServerProfile> servers,
  required ValueChanged<List<ServerProfile>> onServersChanged,
  required ShortcutMap shortcutMap,
  List<String> recent = const [],
  ValueChanged<String>? onRecent,
  String initialAddress = '',
}) => showAppDialog<ServerConnection>(
  context,
  (context) => BlocProvider(
    create: (_) => ConnectCubit(
      service: service,
      servers: servers,
      onServersChanged: onServersChanged,
      recent: recent,
      onRecent: onRecent,
      initialAddress: initialAddress,
    ),
    child: ConnectDialog(shortcutMap: shortcutMap),
  ),
);

/// The dialog over a [ConnectCubit] provided above it.
class ConnectDialog extends StatefulWidget {
  const ConnectDialog({required this.shortcutMap, super.key});

  final ShortcutMap shortcutMap;

  @override
  State<ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<ConnectDialog> {
  final _address = TextEditingController();
  final _addressFocus = FocusNode(debugLabel: 'server address');
  final _listKey = GlobalKey(debugLabel: 'servers');
  int? _lastTapIndex;
  DateTime? _lastTapAt;
  int _nextId = DateTime.now().microsecondsSinceEpoch;

  ConnectCubit get _cubit => context.read<ConnectCubit>();

  @override
  void initState() {
    super.initState();
    _address.value = _selected(context.read<ConnectCubit>().state.address);
  }

  /// [address] in the field, all of it selected: what is typed next
  /// replaces it, as in Finder's Connect to Server, never runs on after it.
  static TextEditingValue _selected(String address) => TextEditingValue(
    text: address,
    selection: TextSelection(baseOffset: 0, extentOffset: address.length),
  );

  @override
  void dispose() {
    _address.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  void _showAddress(String address) {
    if (_address.text == address) return;
    _address.value = _selected(address);
  }

  /// ↑ and ↓ in the address field walk the list below it.
  KeyEventResult _onFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _cubit.moveCursor(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _cubit.moveCursor(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// A click picks the row; a second one within the double-tap time
  /// connects.
  void _tap(int index) {
    final now = DateTime.now();
    final again =
        _lastTapIndex == index &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!) <= kDoubleTapTimeout;
    _lastTapIndex = index;
    _lastTapAt = now;
    _cubit.select(index);
    if (again) unawaited(_cubit.connect());
  }

  String _newId() => 's${(_nextId++).toRadixString(36)}';

  Future<void> _add() async {
    final start =
        _cubit.serverFromAddress(_newId()) ??
        ServerProfile(id: _newId(), protocol: ServerProtocol.sftp, host: '');
    final added = await showServerEditor(context, server: start, isNew: true);
    if (added != null && mounted) _cubit.addServer(added);
  }

  Future<void> _edit() async {
    final server = _cubit.state.selectedServer;
    if (server == null) return;
    final edited = await showServerEditor(
      context,
      server: server,
      isNew: false,
      onForgetPassword: _forget,
    );
    if (edited != null && mounted) _cubit.updateServer(edited);
  }

  Future<void> _forget(ServerProfile server) async {
    final error = await _cubit.forgetPassword(server);
    if (!mounted) return;
    showAppNotice(
      context,
      error == null
          ? context.l10n.networkPasswordForgotten(server.displayRoot)
          : context.l10n.errorMessage(error),
    );
  }

  Future<void> _remove() async {
    final server = _cubit.state.selectedServer;
    if (server == null) return;
    final l10n = context.l10n;
    final sure = await AppDialog.confirm(
      context,
      title: l10n.networkRemoveServerTitle(server.label),
      message: l10n.networkRemoveServerMessage,
      confirmLabel: l10n.networkRemoveServer,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (sure && mounted) _cubit.removeServer(server.id);
  }

  Future<void> _menu(int index, Rect anchor) async {
    _cubit.select(index);
    final l10n = context.l10n;
    final saved = _cubit.state.selectedServer != null;
    final picked = await showAppMenu<String>(
      context: context,
      anchor: anchor,
      entries: [
        AppMenuAction(
          value: 'connect',
          label: l10n.networkConnect,
          icon: AppIcons.server,
        ),
        if (saved) ...[
          AppMenuAction(
            value: 'edit',
            label: l10n.networkEditServer,
            icon: AppIcons.edit,
          ),
          const AppMenuSeparator(),
          AppMenuAction(
            value: 'remove',
            label: l10n.networkRemoveServer,
            icon: AppIcons.trash,
            danger: true,
          ),
        ],
      ],
    );
    if (!mounted) return;
    switch (picked) {
      case 'connect':
        await _cubit.connect();
      case 'edit':
        await _edit();
      case 'remove':
        await _remove();
    }
  }

  void _onState(BuildContext context, ConnectState state) {
    _showAddress(state.address);
    final connection = state.connection;
    if (connection != null) {
      Navigator.of(context).pop(connection);
      return;
    }
    final error = state.error;
    if (error != null && error.kind == FerryxErrorKind.hostKeyChanged) {
      unawaited(
        showHostKeyChangedDialog(
          context,
          server:
              state.parsed?.display ??
              state.selectedServer?.displayRoot ??
              state.address,
          detail: error.message,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocConsumer<ConnectCubit, ConnectState>(
      listenWhen: (before, after) =>
          before.address != after.address ||
          before.connection != after.connection ||
          (after.error != null && before.error != after.error),
      listener: _onState,
      builder: (context, state) => AppDialog(
        title: l10n.networkConnectTitle,
        // The menu key opens the cursor row's menu, from the field too.
        body: CommandHandlers(
          handlers: {
            AppCommand.contextMenu: () {
              final list = _listKey.currentContext;
              if (state.cursor < 0 || list == null) return;
              unawaited(_menu(state.cursor, keyboardMenuAnchor(list)));
            },
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Focus(
                onKeyEvent: _onFieldKey,
                canRequestFocus: false,
                skipTraversal: true,
                child: NetworkField(
                  label: l10n.networkAddressLabel,
                  controller: _address,
                  focusNode: _addressFocus,
                  autofocus: true,
                  hint: l10n.networkAddressHint,
                  monospace: true,
                  readOnly: state.connecting,
                  onChanged: _cubit.typeAddress,
                  onSubmitted: (_) => unawaited(_cubit.connect()),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              _Status(state: state),
              _ServerList(
                key: _listKey,
                state: state,
                shortcutMap: widget.shortcutMap,
                onTap: _tap,
                onFocused: _cubit.select,
                onConnect: (index) {
                  _cubit.select(index);
                  unawaited(_cubit.connect());
                },
                onMenu: (index, anchor) => unawaited(_menu(index, anchor)),
                onEdit: () => unawaited(_edit()),
                onRemove: () => unawaited(_remove()),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: context.metrics.toolbarSpacing,
                runSpacing: AppSpacing.xs,
                children: [
                  OutlinedButton.icon(
                    style: AppButtonStyles.small(context),
                    onPressed: state.connecting
                        ? null
                        : () => unawaited(_add()),
                    icon: const Icon(AppIcons.add, size: AppIconSize.sm),
                    label: Text(l10n.networkAddServer),
                  ),
                  OutlinedButton.icon(
                    style: AppButtonStyles.small(context),
                    onPressed: state.connecting || state.selectedServer == null
                        ? null
                        : () => unawaited(_edit()),
                    icon: const Icon(AppIcons.edit, size: AppIconSize.sm),
                    label: Text(l10n.networkEditServer),
                  ),
                  OutlinedButton.icon(
                    style: AppButtonStyles.small(context),
                    onPressed: state.connecting || state.selectedServer == null
                        ? null
                        : () => unawaited(_remove()),
                    icon: const Icon(AppIcons.trash, size: AppIconSize.sm),
                    label: Text(l10n.networkRemoveServer),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () {
              _cubit.cancel();
              Navigator.of(context).pop();
            },
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: state.canConnect
                ? () => unawaited(_cubit.connect())
                : null,
            child: Text(l10n.networkConnect),
          ),
        ],
      ),
    );
  }
}

/// Under the field: the connection under way, the last failure, an
/// address that does not read, or what the field takes, and a warning for
/// an unencrypted protocol.
class _Status extends StatelessWidget {
  const _Status({required this.state});

  final ConnectState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final muted = context.text.bodySmall?.copyWith(
      color: context.appColors.textMuted,
    );
    final connectingTo = state.connectingTo;
    final error = state.error;
    final Widget line;
    if (connectingTo != null) {
      line = Row(
        children: [
          AppSpinner(size: AppIconSize.sm),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: AppMiddleEllipsis(
              l10n.networkConnecting(connectingTo),
              style: muted!,
            ),
          ),
        ],
      );
    } else if (error != null) {
      line = NetworkNote.error(context, l10n.errorMessage(error));
    } else if (state.invalid) {
      line = NetworkNote.error(
        context,
        l10n.networkNotAnAddress(state.address.trim()),
      );
    } else {
      line = Text(l10n.networkAddressNote, style: muted);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line,
        if (state.insecure) ...[
          const SizedBox(height: AppSpacing.xs),
          NetworkNote.insecure(context, l10n.networkInsecure),
        ],
      ],
    );
  }
}

/// The saved servers, then the addresses connected to lately; the cursor
/// row selected. A row in focus takes F2 (edit), the delete key (remove)
/// and Return (connect).
class _ServerList extends StatelessWidget {
  const _ServerList({
    required this.state,
    super.key,
    required this.shortcutMap,
    required this.onTap,
    required this.onFocused,
    required this.onConnect,
    required this.onMenu,
    required this.onEdit,
    required this.onRemove,
  });

  final ConnectState state;
  final ShortcutMap shortcutMap;
  final ValueChanged<int> onTap;

  /// The keys moved onto a row.
  final ValueChanged<int> onFocused;
  final ValueChanged<int> onConnect;
  final void Function(int index, Rect anchor) onMenu;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rows = <Widget>[
      AppSectionLabel(l10n.networkSavedServers),
      if (state.servers.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Text(
            l10n.networkNoServers,
            style: context.text.bodySmall?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
        ),
      for (var i = 0; i < state.servers.length; i++)
        _Row(
          key: ValueKey('server ${state.servers[i].id}'),
          label: state.servers[i].label,
          detail: state.servers[i].address,
          icon: state.servers[i].protocol.secure
              ? AppIcons.server
              : AppIcons.unlocked,
          selected: state.cursor == i,
          onTap: () => onTap(i),
          onFocused: () => onFocused(i),
          onConnect: () => onConnect(i),
          onMenu: (anchor) => onMenu(i, anchor),
        ),
      if (state.recent.isNotEmpty) AppSectionLabel(l10n.networkRecent),
      for (var i = 0; i < state.recent.length; i++)
        _Row(
          key: ValueKey('recent ${state.recent[i]}'),
          label: state.recent[i],
          icon: AppIcons.history,
          selected: state.cursor == state.servers.length + i,
          onTap: () => onTap(state.servers.length + i),
          onFocused: () => onFocused(state.servers.length + i),
          onConnect: () => onConnect(state.servers.length + i),
          onMenu: (anchor) => onMenu(state.servers.length + i, anchor),
        ),
    ];
    return CommandShortcuts(
      shortcuts: shortcutMap.toShortcuts(
        Theme.of(context).platform,
        scopes: const {CommandScope.lists},
      ),
      child: CommandHandlers(
        handlers: {
          AppCommand.renameItem: onEdit,
          AppCommand.deleteItem: onRemove,
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: AppSizes.pickerListMaxHeight,
          ),
          child: ListView(shrinkWrap: true, children: rows),
        ),
      ),
    );
  }
}

/// One server or address: its name, and its address after it in the
/// secondary colour.
class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.onFocused,
    required this.onConnect,
    required this.onMenu,
    this.detail,
    super.key,
  });

  final String label;
  final String? detail;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onFocused;
  final VoidCallback onConnect;
  final void Function(Rect anchor) onMenu;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.enter): _ConnectIntent(),
      SingleActivator(LogicalKeyboardKey.numpadEnter): _ConnectIntent(),
    },
    child: Actions(
      actions: {
        _ConnectIntent: CallbackAction<_ConnectIntent>(
          onInvoke: (_) {
            onConnect();
            return null;
          },
        ),
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) {
          if (focused && !selected) onFocused();
        },
        child: Builder(
          builder: (rowContext) => AppNavItem(
            label: label,
            icon: icon,
            trailing: detail == null
                ? null
                : Text(detail!, maxLines: 1, overflow: TextOverflow.ellipsis),
            selected: selected,
            onTap: onTap,
            onSecondaryTap: () => onMenu(keyboardMenuAnchor(rowContext)),
            tooltip: detail ?? label,
          ),
        ),
      ),
    ),
  );
}

class _ConnectIntent extends Intent {
  const _ConnectIntent();
}
