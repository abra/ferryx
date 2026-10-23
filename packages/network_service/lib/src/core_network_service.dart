import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' as rust;
import 'package:monitoring/monitoring.dart';

import 'network_service.dart';

/// [NetworkService] over the Rust core: its calls, and its
/// `ConnectionChanged`, `NetworkQuestion` and `NetworkQuestionWithdrawn`
/// events.
class CoreNetworkService implements NetworkService {
  CoreNetworkService({
    required rust.FerryxBackend backend,
    required this.logger,
  }) {
    _subscription = backend.events.listen(_onEvent);
    try {
      for (final status in rust.listServers().map(rust.serverStatusFromView)) {
        _servers[status.server] = status;
      }
    } on Object catch (error) {
      logger.warn('servers', error: error);
    }
  }

  final Logger logger;
  final _servers = <String, ServerStatus>{};
  final _serverChanges =
      StreamController<Map<String, ServerStatus>>.broadcast();
  final _questions = StreamController<NetworkQuestion>.broadcast();
  final _withdrawn = StreamController<int>.broadcast();
  StreamSubscription<rust.AppEvent>? _subscription;

  @override
  Map<String, ServerStatus> get servers => Map.unmodifiable(_servers);

  @override
  Stream<Map<String, ServerStatus>> get serverChanges => _serverChanges.stream;

  @override
  Stream<NetworkQuestion> get questions => _questions.stream;

  @override
  Stream<int> get withdrawn => _withdrawn.stream;

  void _onEvent(rust.AppEvent event) {
    final network = event.network;
    if (network == null) return;
    switch (event.kind) {
      case rust.AppEventKind.connectionChanged:
        final state = network.state;
        if (state == null) return;
        final next = rust.serverStateFromView(state);
        if (next == ServerState.closed) {
          _servers.remove(network.server);
        } else {
          _servers[network.server] = ServerStatus(
            server: network.server,
            display:
                ServerKey.parse(network.server)?.displayRoot ?? network.server,
            state: next,
          );
        }
        _serverChanges.add(servers);
      case rust.AppEventKind.networkQuestion:
        final question = network.question;
        if (question != null) {
          _questions.add(rust.networkQuestionFromView(question));
        }
      case rust.AppEventKind.networkQuestionWithdrawn:
        _withdrawn.add(network.questionId);
      default:
        break;
    }
  }

  @override
  ServerAddress parse(
    String text, {
    ServerProtocol fallback = ServerProtocol.sftp,
  }) {
    try {
      return rust.serverAddressFromView(
        rust.parseServerAddress(
          text: text,
          defaultProtocol: rust.protocolToView(fallback),
        ),
      );
    } on rust.FerryxError catch (error) {
      throw FerryxException(
        rust.errorKindFromView(error.kind),
        error.message,
        path: error.path,
      );
    }
  }

  @override
  String keyOf(ServerProfile profile) {
    try {
      return rust.serverKey(request: rust.connectRequestToView(profile));
    } on rust.FerryxError catch (error) {
      throw FerryxException(rust.errorKindFromView(error.kind), error.message);
    }
  }

  @override
  ConnectAttempt connect(ServerProfile profile, {String? password}) {
    final attempt = rust.beginConnect();
    final result = rust.FerryxBackend.guard(() async {
      final view = await rust.connectServer(
        attempt: attempt,
        request: rust.connectRequestToView(profile, password: password),
      );
      return rust.connectionFromView(view);
    });
    return ConnectAttempt(result, () => rust.cancelConnect(attempt: attempt));
  }

  @override
  Future<void> disconnect(String server) =>
      rust.FerryxBackend.guard(() => rust.disconnectServer(server: server));

  @override
  void answer(int questionId, NetworkAnswer answer) =>
      rust.answerNetworkQuestion(
        id: questionId,
        accept: answer.accept,
        texts: answer.texts,
        remember: answer.remember,
      );

  @override
  Future<void> forgetPassword(String server) =>
      rust.FerryxBackend.guard(() => rust.forgetServerPassword(server: server));

  @override
  Future<String> tempFolder(String server) =>
      rust.FerryxBackend.guard(() => rust.remoteTempFolder(server: server));

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _serverChanges.close();
    await _questions.close();
    await _withdrawn.close();
  }
}
