import 'package:domain_models/domain_models.dart';

import 'generated/ferryx_localizations.dart';

/// Servers in words.
extension NetworkLabels on FerryxLocalizations {
  /// The protocol as the server editor offers it: `SFTP (SSH)`.
  String protocolLabel(ServerProtocol protocol) => switch (protocol) {
    ServerProtocol.sftp => networkProtocolSftp,
    ServerProtocol.ftp => networkProtocolFtp,
    ServerProtocol.ftps => networkProtocolFtps,
    ServerProtocol.dav => networkProtocolDav,
    ServerProtocol.davs => networkProtocolDavs,
  };

  /// The protocol's short name, for a capsule: `SFTP`, `WebDAV`.
  String protocolShortName(ServerProtocol protocol) => switch (protocol) {
    ServerProtocol.sftp => 'SFTP',
    ServerProtocol.ftp => 'FTP',
    ServerProtocol.ftps => 'FTPS',
    ServerProtocol.dav || ServerProtocol.davs => 'WebDAV',
  };

  String authLabel(ServerAuth auth) => switch (auth) {
    ServerAuth.automatic => networkAuthAutomatic,
    ServerAuth.password => networkAuthPassword,
    ServerAuth.key => networkAuthKey,
    ServerAuth.agent => networkAuthAgent,
  };

  /// A connection's state for [server] (`sftp://me@host`), said whole.
  String serverStateLabel(
    ServerState state,
    String server, {
    required bool secure,
  }) {
    final text = switch (state) {
      ServerState.connected => networkStateConnected(server),
      ServerState.lost => networkStateLost(server),
      ServerState.closed => networkStateClosed(server),
    };
    return secure ? text : networkStateInsecure(text);
  }
}
