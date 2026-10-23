import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// How Ferryx talks to a server.
enum ServerProtocol {
  sftp('sftp', 22, secure: true),

  /// Plain FTP: names, passwords and data cross unencrypted.
  ftp('ftp', 21, secure: false),

  /// FTP with explicit TLS (`AUTH TLS` on the FTP port).
  ftps('ftps', 21, secure: true),

  /// WebDAV over plain HTTP.
  dav('dav', 80, secure: false),

  /// WebDAV over HTTPS.
  davs('davs', 443, secure: true);

  const ServerProtocol(this.scheme, this.defaultPort, {required this.secure});

  /// The scheme of its addresses (`sftp://`).
  final String scheme;
  final int defaultPort;

  /// Whether what crosses the network is encrypted.
  final bool secure;

  /// Logging in to it may use SSH keys and an agent.
  bool get hasKeys => this == sftp;

  static ServerProtocol? ofScheme(String scheme) =>
      values.where((p) => p.scheme == scheme.toLowerCase()).firstOrNull;
}

/// A server's key, as the core spells it (`sftp://me@host:22`): what every
/// location on the server carries. The user is percent-encoded, the host
/// lower case (an IPv6 one in brackets), the port always there.
@immutable
class ServerKey extends Equatable {
  const ServerKey({
    required this.protocol,
    required this.host,
    required this.port,
    this.user = '',
  });

  final ServerProtocol protocol;
  final String host;
  final int port;

  /// Empty for anonymous FTP or a WebDAV server without a login.
  final String user;

  /// Reads a key back; `null` when [key] is none.
  static ServerKey? parse(String key) {
    final schemeEnd = key.indexOf('://');
    if (schemeEnd < 0) return null;
    final protocol = ServerProtocol.ofScheme(key.substring(0, schemeEnd));
    if (protocol == null) return null;
    final rest = key.substring(schemeEnd + 3);
    final at = rest.lastIndexOf('@');
    final user = at < 0 ? '' : Uri.decodeComponent(rest.substring(0, at));
    final hostPort = at < 0 ? rest : rest.substring(at + 1);
    final colon = hostPort.lastIndexOf(':');
    if (colon < 0) return null;
    final port = int.tryParse(hostPort.substring(colon + 1));
    var host = hostPort.substring(0, colon);
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    if (port == null || host.isEmpty) return null;
    return ServerKey(protocol: protocol, host: host, port: port, user: user);
  }

  String get _host => host.contains(':') ? '[$host]' : host;

  /// `sftp://me@host`: the port only when it is not the protocol's own.
  String get displayRoot {
    final user = this.user.isEmpty ? '' : '${this.user}@';
    final port = this.port == protocol.defaultPort ? '' : ':${this.port}';
    return '${protocol.scheme}://$user$_host$port';
  }

  /// `path` on the server as a person reads it: `sftp://me@host/srv`.
  String urlOf(String path) {
    if (path.isEmpty || path == '/') return '$displayRoot/';
    return path.startsWith('/') ? '$displayRoot$path' : '$displayRoot/$path';
  }

  @override
  List<Object?> get props => [protocol, host, port, user];

  @override
  String toString() => displayRoot;
}

/// How an SSH server is logged in to; FTP and WebDAV take a password.
enum ServerAuth {
  /// As OpenSSH: the agent's keys, the default key files, the server's
  /// prompts, a password.
  automatic,
  password,

  /// A key file ([ServerProfile.keyPath]; the default ones when empty).
  key,

  /// The keys of the SSH agent.
  agent,
}

/// A server the user saved: everything to connect but the password,
/// which only the system's keychain keeps.
@immutable
class ServerProfile extends Equatable {
  const ServerProfile({
    required this.id,
    required this.protocol,
    required this.host,
    this.name = '',
    this.port = 0,
    this.user = '',
    this.path = '',
    this.auth = ServerAuth.automatic,
    this.keyPath = '',
  });

  /// Stays the same as the server is edited.
  final String id;

  /// What the list calls it; the host when empty.
  final String name;
  final ServerProtocol protocol;
  final String host;

  /// 0 for the protocol's own.
  final int port;
  final String user;

  /// The folder to open; empty for the server's own start.
  final String path;
  final ServerAuth auth;
  final String keyPath;

  int get effectivePort => port == 0 ? protocol.defaultPort : port;

  /// What the list shows: the name, else the host.
  String get label => name.trim().isEmpty ? host : name.trim();

  /// The server as a person reads its address: `sftp://me@host`.
  String get displayRoot => ServerKey(
    protocol: protocol,
    host: host.trim().toLowerCase(),
    port: effectivePort,
    user: user.trim(),
  ).displayRoot;

  /// The address with its folder, as typed: `sftp://me@host/srv`.
  String get address {
    final folder = path.trim();
    if (folder.isEmpty) return displayRoot;
    return folder.startsWith('/')
        ? '$displayRoot$folder'
        : '$displayRoot/$folder';
  }

  ServerProfile copyWith({
    String? name,
    ServerProtocol? protocol,
    String? host,
    int? port,
    String? user,
    String? path,
    ServerAuth? auth,
    String? keyPath,
  }) => ServerProfile(
    id: id,
    name: name ?? this.name,
    protocol: protocol ?? this.protocol,
    host: host ?? this.host,
    port: port ?? this.port,
    user: user ?? this.user,
    path: path ?? this.path,
    auth: auth ?? this.auth,
    keyPath: keyPath ?? this.keyPath,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'protocol': protocol.name,
    'host': host,
    'port': port,
    'user': user,
    'path': path,
    'auth': auth.name,
    'keyPath': keyPath,
  };

  /// `null` when [json] is not a server (a newer or broken entry).
  static ServerProfile? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final host = json['host'];
    final protocol = ServerProtocol.values.asNameMap()[json['protocol']];
    if (id is! String || host is! String || protocol == null) return null;
    String text(String key) => json[key] is String ? json[key] as String : '';
    return ServerProfile(
      id: id,
      name: text('name'),
      protocol: protocol,
      host: host,
      port: json['port'] is int ? json['port'] as int : 0,
      user: text('user'),
      path: text('path'),
      auth: ServerAuth.values.asNameMap()[json['auth']] ?? ServerAuth.automatic,
      keyPath: text('keyPath'),
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    protocol,
    host,
    port,
    user,
    path,
    auth,
    keyPath,
  ];
}

/// An address as typed and read by the core.
@immutable
class ServerAddress extends Equatable {
  const ServerAddress({
    required this.protocol,
    required this.host,
    required this.port,
    required this.key,
    required this.display,
    this.user = '',
    this.path = '',
    this.password,
  });

  final ServerProtocol protocol;
  final String host;
  final int port;
  final String user;
  final String path;

  /// A password written into the address: for this connection only,
  /// never kept.
  final String? password;
  final String key;
  final String display;

  @override
  List<Object?> get props => [
    protocol,
    host,
    port,
    user,
    path,
    password,
    key,
    display,
  ];
}

/// A connection made.
@immutable
class ServerConnection extends Equatable {
  const ServerConnection({
    required this.server,
    required this.display,
    required this.home,
    required this.protocol,
    required this.secure,
  });

  /// The server's key.
  final String server;

  /// `sftp://me@host`.
  final String display;

  /// The folder to open first.
  final String home;
  final ServerProtocol protocol;
  final bool secure;

  @override
  List<Object?> get props => [server, display, home, protocol, secure];
}

/// A connection's state as the interface shows it.
enum ServerState {
  connected,

  /// It dropped; the next call tries again.
  lost,

  /// The user disconnected.
  closed,
}

@immutable
class ServerStatus extends Equatable {
  const ServerStatus({
    required this.server,
    required this.display,
    required this.state,
  });

  final String server;
  final String display;
  final ServerState state;

  @override
  List<Object?> get props => [server, display, state];
}

/// A question a connection asks the user, answered through the network
/// service by its [id].
@immutable
sealed class NetworkQuestion extends Equatable {
  const NetworkQuestion({required this.id, required this.server});

  final int id;

  /// The server's key.
  final String server;

  @override
  List<Object?> get props => [id, server];
}

/// An SSH key no known_hosts file has: trust it?
final class HostKeyQuestion extends NetworkQuestion {
  const HostKeyQuestion({
    required super.id,
    required super.server,
    required this.host,
    required this.port,
    required this.algorithm,
    required this.fingerprint,
  });

  final String host;
  final int port;

  /// `ssh-ed25519`…
  final String algorithm;

  /// `SHA256:…`, as OpenSSH prints it.
  final String fingerprint;

  @override
  List<Object?> get props => [
    ...super.props,
    host,
    port,
    algorithm,
    fingerprint,
  ];
}

final class PasswordQuestion extends NetworkQuestion {
  const PasswordQuestion({
    required super.id,
    required super.server,
    required this.user,
    required this.retry,
  });

  final String user;

  /// The password given before was refused.
  final bool retry;

  @override
  List<Object?> get props => [...super.props, user, retry];
}

final class PassphraseQuestion extends NetworkQuestion {
  const PassphraseQuestion({
    required super.id,
    required super.server,
    required this.keyPath,
    required this.retry,
  });

  final String keyPath;
  final bool retry;

  @override
  List<Object?> get props => [...super.props, keyPath, retry];
}

/// The server's own prompts (a one-time code).
final class PromptsQuestion extends NetworkQuestion {
  const PromptsQuestion({
    required super.id,
    required super.server,
    required this.name,
    required this.instructions,
    required this.prompts,
  });

  final String name;
  final String instructions;

  /// Each prompt's words and whether what is typed may show.
  final List<(String, bool)> prompts;

  @override
  List<Object?> get props => [...super.props, name, instructions, prompts];
}

/// The user's answer to a [NetworkQuestion].
@immutable
class NetworkAnswer extends Equatable {
  const NetworkAnswer({
    required this.accept,
    this.texts = const [],
    this.remember = false,
  });

  /// Cancel.
  const NetworkAnswer.cancel()
    : accept = false,
      texts = const [],
      remember = false;

  /// Go on; `false` is Cancel.
  final bool accept;

  /// The password, the passphrase, or one text per prompt.
  final List<String> texts;

  /// Keep the password in the system's keychain; for a host key, keep it
  /// in Ferryx's known_hosts.
  final bool remember;

  @override
  List<Object?> get props => [accept, texts, remember];
}
