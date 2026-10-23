import 'dart:async';

import 'package:domain_models/domain_models.dart';

/// A connection being made: its result, and a way to give it up (its
/// questions are withdrawn, and the result fails with
/// [FerryxErrorKind.cancelled]).
class ConnectAttempt {
  ConnectAttempt(this.result, this._cancel);

  final Future<ServerConnection> result;
  final void Function() _cancel;

  void cancel() => _cancel();
}

/// Servers over SFTP, FTP(S) and WebDAV, as far as the interface deals
/// with them: addresses read, connections made, closed and watched, and
/// the questions a connection asks the user (a host key, a password),
/// answered by their id. Listings and operations on a server go through
/// the file repository and the operations service, by location.
abstract interface class NetworkService {
  /// The servers open now, by key.
  Map<String, ServerStatus> get servers;

  /// [servers] each time one connects, drops or closes.
  Stream<Map<String, ServerStatus>> get serverChanges;

  /// Questions to ask the user, as connections ask them.
  Stream<NetworkQuestion> get questions;

  /// Ids of questions no longer waiting (their connection was given up).
  Stream<int> get withdrawn;

  /// Reads an address as typed: `sftp://me@host:2222/srv`, `ftp://host`,
  /// `https://…` (WebDAV), `me@host` as [fallback]. Throws a
  /// [FerryxException] of [FerryxErrorKind.invalidName] for what is no
  /// address.
  ServerAddress parse(
    String text, {
    ServerProtocol fallback = ServerProtocol.sftp,
  });

  /// The key a connection to [profile] gets (`sftp://me@host:22`).
  String keyOf(ServerProfile profile);

  /// Connects to [profile] ([password] typed into an address), or answers
  /// the connection already open to it.
  ConnectAttempt connect(ServerProfile profile, {String? password});

  /// Closes every connection to [server].
  Future<void> disconnect(String server);

  void answer(int questionId, NetworkAnswer answer);

  /// Forgets the password the system's keychain keeps for [server].
  Future<void> forgetPassword(String server);

  /// A new temporary folder for a copy of [server]'s file to open.
  Future<String> tempFolder(String server);

  Future<void> dispose();
}
