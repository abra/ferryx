/// Translation of the network's bridge types: servers, connections, the
/// questions a connection asks, the operations that cross the network.
library;

import 'package:domain_models/domain_models.dart' as d;

import 'mapping.dart';
import 'rust/api/network.dart' as rust;
import 'rust/api/types.dart' as rust;

rust.ProtocolView protocolToView(d.ServerProtocol protocol) =>
    switch (protocol) {
      d.ServerProtocol.sftp => rust.ProtocolView.sftp,
      d.ServerProtocol.ftp => rust.ProtocolView.ftp,
      d.ServerProtocol.ftps => rust.ProtocolView.ftps,
      d.ServerProtocol.dav => rust.ProtocolView.dav,
      d.ServerProtocol.davs => rust.ProtocolView.davs,
    };

d.ServerProtocol protocolFromView(rust.ProtocolView protocol) =>
    switch (protocol) {
      rust.ProtocolView.sftp => d.ServerProtocol.sftp,
      rust.ProtocolView.ftp => d.ServerProtocol.ftp,
      rust.ProtocolView.ftps => d.ServerProtocol.ftps,
      rust.ProtocolView.dav => d.ServerProtocol.dav,
      rust.ProtocolView.davs => d.ServerProtocol.davs,
    };

rust.AuthMethodView authToView(d.ServerAuth auth) => switch (auth) {
  d.ServerAuth.automatic => rust.AuthMethodView.auto,
  d.ServerAuth.password => rust.AuthMethodView.password,
  d.ServerAuth.key => rust.AuthMethodView.key,
  d.ServerAuth.agent => rust.AuthMethodView.agent,
};

/// What to connect to for [profile]; [password] typed into an address.
rust.ConnectRequestView connectRequestToView(
  d.ServerProfile profile, {
  String? password,
}) => rust.ConnectRequestView(
  protocol: protocolToView(profile.protocol),
  host: profile.host.trim(),
  port: profile.port,
  user: profile.user.trim(),
  path: profile.path.trim(),
  password: password,
  auth: authToView(profile.auth),
  keyPath: profile.keyPath.trim().isEmpty ? null : profile.keyPath.trim(),
);

d.ServerAddress serverAddressFromView(rust.ServerAddressView view) =>
    d.ServerAddress(
      protocol: protocolFromView(view.protocol),
      host: view.host,
      port: view.port,
      user: view.user,
      path: view.path,
      password: view.password,
      key: view.key,
      display: view.display,
    );

d.ServerConnection connectionFromView(rust.ConnectionView view) =>
    d.ServerConnection(
      server: view.server,
      display: view.display,
      home: view.home,
      protocol: protocolFromView(view.protocol),
      secure: view.secure,
    );

d.ServerState serverStateFromView(rust.ConnectionStateView state) =>
    switch (state) {
      rust.ConnectionStateView.connected => d.ServerState.connected,
      rust.ConnectionStateView.lost => d.ServerState.lost,
      rust.ConnectionStateView.closed => d.ServerState.closed,
    };

d.ServerStatus serverStatusFromView(rust.ServerStateView view) =>
    d.ServerStatus(
      server: view.server,
      display: view.display,
      state: serverStateFromView(view.state),
    );

d.NetworkQuestion networkQuestionFromView(rust.NetworkQuestionView view) =>
    switch (view.kind) {
      rust.NetworkQuestionKindView.hostKey => d.HostKeyQuestion(
        id: view.id,
        server: view.server,
        host: view.host,
        port: view.port,
        algorithm: view.algorithm,
        fingerprint: view.fingerprint,
      ),
      rust.NetworkQuestionKindView.password => d.PasswordQuestion(
        id: view.id,
        server: view.server,
        user: view.user,
        retry: view.retry,
      ),
      rust.NetworkQuestionKindView.passphrase => d.PassphraseQuestion(
        id: view.id,
        server: view.server,
        keyPath: view.keyPath,
        retry: view.retry,
      ),
      rust.NetworkQuestionKindView.keyboardInteractive => d.PromptsQuestion(
        id: view.id,
        server: view.server,
        name: view.name,
        instructions: view.instructions,
        prompts: [for (final p in view.prompts) (p.text, p.echo)],
      ),
    };

/// An operation that crosses the network (see
/// [d.OperationRequest.crossesNetwork]).
rust.NetworkOpRequestView networkOperationToView(d.OperationRequest request) =>
    rust.NetworkOpRequestView(
      kind: opKindToView(request.kind),
      sources: request.sources,
      sourceServer: request.sourceServer,
      destination: request.destination,
      destinationServer: request.destinationServer,
      newName: request.newName,
      conflicts: conflictPolicyToView(request.conflicts),
      preserveAttributes: request.preserveAttributes,
    );

/// A row on a server, as a listing reads it.
d.FileEntry? remoteEntryFromView(rust.EntryView? view) =>
    view == null ? null : entryFromView(view);
