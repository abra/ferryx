import 'dart:async';

import 'package:domain_models/domain_models.dart';

import 'network_service.dart';

/// A [NetworkService] for tests: addresses read by a small parser of its
/// own, connections answered by [onConnect] (or made at once), questions
/// put in by [ask], every call kept.
class FakeNetworkService implements NetworkService {
  FakeNetworkService({this.onConnect});

  /// How a connection attempt ends; by default it succeeds at the
  /// profile's folder (or `/`).
  Future<ServerConnection> Function(ServerProfile profile, String? password)?
  onConnect;

  final connected = <ServerProfile>[];
  final disconnected = <String>[];
  final answers = <int, NetworkAnswer>{};
  final forgotten = <String>[];
  int cancelled = 0;

  final _servers = <String, ServerStatus>{};
  final _serverChanges =
      StreamController<Map<String, ServerStatus>>.broadcast();
  final _questions = StreamController<NetworkQuestion>.broadcast();
  final _withdrawn = StreamController<int>.broadcast();

  @override
  Map<String, ServerStatus> get servers => Map.unmodifiable(_servers);

  @override
  Stream<Map<String, ServerStatus>> get serverChanges => _serverChanges.stream;

  @override
  Stream<NetworkQuestion> get questions => _questions.stream;

  @override
  Stream<int> get withdrawn => _withdrawn.stream;

  /// A connection asks [question].
  void ask(NetworkQuestion question) => _questions.add(question);

  /// The connection of [question] gave up on it.
  void withdraw(int id) => _withdrawn.add(id);

  /// [server]'s connection is now in [state].
  void setState(String server, ServerState state) {
    if (state == ServerState.closed) {
      _servers.remove(server);
    } else {
      _servers[server] = ServerStatus(
        server: server,
        display: ServerKey.parse(server)?.displayRoot ?? server,
        state: state,
      );
    }
    _serverChanges.add(servers);
  }

  @override
  ServerAddress parse(
    String text, {
    ServerProtocol fallback = ServerProtocol.sftp,
  }) {
    final trimmed = text.trim();
    final schemeEnd = trimmed.indexOf('://');
    final protocol = schemeEnd < 0
        ? fallback
        : ServerProtocol.ofScheme(trimmed.substring(0, schemeEnd)) ??
              (throw FerryxException(FerryxErrorKind.invalidName, text));
    var rest = schemeEnd < 0 ? trimmed : trimmed.substring(schemeEnd + 3);
    final slash = rest.indexOf('/');
    final path = slash < 0 ? '' : rest.substring(slash);
    rest = slash < 0 ? rest : rest.substring(0, slash);
    final at = rest.lastIndexOf('@');
    final userInfo = at < 0 ? '' : rest.substring(0, at);
    final colonAt = userInfo.indexOf(':');
    final user = colonAt < 0 ? userInfo : userInfo.substring(0, colonAt);
    final password = colonAt < 0 ? null : userInfo.substring(colonAt + 1);
    final hostPort = at < 0 ? rest : rest.substring(at + 1);
    final colon = hostPort.lastIndexOf(':');
    final host = colon < 0 ? hostPort : hostPort.substring(0, colon);
    final port = colon < 0
        ? protocol.defaultPort
        : int.tryParse(hostPort.substring(colon + 1)) ??
              (throw FerryxException(FerryxErrorKind.invalidName, text));
    if (host.isEmpty) throw FerryxException(FerryxErrorKind.invalidName, text);
    final key = ServerKey(
      protocol: protocol,
      host: host.toLowerCase(),
      port: port,
      user: user,
    );
    return ServerAddress(
      protocol: protocol,
      host: host.toLowerCase(),
      port: port,
      user: user,
      path: path,
      password: password,
      key: _key(key),
      display: key.displayRoot,
    );
  }

  static String _key(ServerKey key) {
    final user = key.user.isEmpty ? '' : '${key.user}@';
    return '${key.protocol.scheme}://$user${key.host}:${key.port}';
  }

  @override
  String keyOf(ServerProfile profile) {
    if (profile.host.trim().isEmpty) {
      throw const FerryxException(FerryxErrorKind.invalidName, '');
    }
    return _key(
      ServerKey(
        protocol: profile.protocol,
        host: profile.host.trim().toLowerCase(),
        port: profile.effectivePort,
        user: profile.user.trim(),
      ),
    );
  }

  @override
  ConnectAttempt connect(ServerProfile profile, {String? password}) {
    connected.add(profile);
    final key = keyOf(profile);
    final completer = Completer<ServerConnection>();
    final result =
        onConnect?.call(profile, password) ??
        Future.value(
          ServerConnection(
            server: key,
            display: ServerKey.parse(key)!.displayRoot,
            home: profile.path.isEmpty ? '/' : profile.path,
            protocol: profile.protocol,
            secure: profile.protocol.secure,
          ),
        );
    unawaited(
      result.then(
        (connection) {
          if (completer.isCompleted) return;
          setState(connection.server, ServerState.connected);
          completer.complete(connection);
        },
        onError: (Object error, StackTrace stack) {
          if (!completer.isCompleted) completer.completeError(error, stack);
        },
      ),
    );
    return ConnectAttempt(completer.future, () {
      cancelled++;
      if (!completer.isCompleted) {
        completer.completeError(
          const FerryxException(FerryxErrorKind.cancelled, 'cancelled'),
        );
      }
    });
  }

  @override
  Future<void> disconnect(String server) async {
    disconnected.add(server);
    setState(server, ServerState.closed);
  }

  @override
  void answer(int questionId, NetworkAnswer answer) =>
      answers[questionId] = answer;

  @override
  Future<void> forgetPassword(String server) async => forgotten.add(server);

  @override
  Future<String> tempFolder(String server) async => '/tmp/ferryx-test';

  @override
  Future<void> dispose() async {
    await _serverChanges.close();
    await _questions.close();
    await _withdrawn.close();
  }
}
