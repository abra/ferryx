import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:network_service/network_service.dart';

import 'prompt_dialogs.dart';

/// Connections the window asks for outside Connect to Server: a panel's
/// server opened again (a tab restored, a favorite, Reconnect), an address
/// from the command line, a saved server from the Go To pop-up. A saved
/// server's way of logging in goes along; a failure becomes a notice, a
/// changed host key its alarm.
class ServerConnector {
  ServerConnector({required this.service, required this.servers});

  final NetworkService service;

  /// The saved servers now.
  final List<ServerProfile> Function() servers;

  /// The saved server whose key is [server], else one made from the key
  /// (logging in as OpenSSH would).
  ServerProfile profileFor(String server) {
    for (final profile in servers()) {
      try {
        if (service.keyOf(profile) == server) return profile;
      } on FerryxException {
        // A saved server that does not read is no match.
      }
    }
    final key = ServerKey.parse(server);
    return ServerProfile(
      id: 'key',
      protocol: key?.protocol ?? ServerProtocol.sftp,
      host: key?.host ?? server,
      port: key?.port ?? 0,
      user: key?.user ?? '',
    );
  }

  /// Connects to [profile]; `null` when it failed (said in a notice) or
  /// was given up.
  Future<ServerConnection?> connect(
    BuildContext context,
    ServerProfile profile, {
    String? password,
  }) async {
    final attempt = service.connect(profile, password: password);
    try {
      return await attempt.result;
    } on FerryxException catch (error) {
      if (!context.mounted) return null;
      switch (error.kind) {
        case FerryxErrorKind.cancelled:
          break;
        case FerryxErrorKind.hostKeyChanged:
          await showHostKeyChangedDialog(
            context,
            server: profile.displayRoot,
            detail: error.message,
          );
        default:
          showAppNotice(context, context.l10n.errorMessage(error));
      }
      return null;
    }
  }

  /// Opens the connection to [server] (a key) again; whether it is open.
  Future<bool> reconnect(BuildContext context, String server) async =>
      await connect(context, profileFor(server)) != null;

  /// Connects to the address [text] as typed (`:connect sftp://me@host`);
  /// a saved server of the same key lends its way of logging in.
  Future<ServerConnection?> connectAddress(
    BuildContext context,
    String text,
  ) async {
    final ServerAddress address;
    try {
      address = service.parse(text);
    } on FerryxException {
      showAppNotice(context, context.l10n.networkNotAnAddress(text));
      return null;
    }
    final saved = profileFor(address.key);
    final profile = saved.id == 'key'
        ? ServerProfile(
            id: 'address',
            protocol: address.protocol,
            host: address.host,
            port: address.port,
            user: address.user,
            path: address.path,
          )
        : saved.copyWith(path: address.path.isEmpty ? null : address.path);
    return connect(context, profile, password: address.password);
  }
}
