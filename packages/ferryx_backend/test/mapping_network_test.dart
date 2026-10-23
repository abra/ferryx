import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' as rust;
import 'package:flutter_test/flutter_test.dart';

rust.NetworkQuestionView question(
  rust.NetworkQuestionKindView kind, {
  List<rust.PromptView> prompts = const [],
}) => rust.NetworkQuestionView(
  id: 9,
  kind: kind,
  server: 'sftp://me@box.lan:22',
  host: 'box.lan',
  port: 22,
  user: 'me',
  algorithm: 'ssh-ed25519',
  fingerprint: 'SHA256:abc',
  keyPath: '/k/id_ed25519',
  retry: true,
  name: 'Two factors',
  instructions: 'Use your token',
  prompts: prompts,
);

void main() {
  test('every protocol goes there and back', () {
    for (final protocol in ServerProtocol.values) {
      expect(
        rust.protocolFromView(rust.protocolToView(protocol)),
        protocol,
      );
    }
  });

  test('a saved server asks to connect trimmed, a blank key path unset', () {
    const profile = ServerProfile(
      id: 'a',
      protocol: ServerProtocol.sftp,
      host: ' box.lan ',
      port: 2222,
      user: ' me ',
      path: ' /srv ',
      auth: ServerAuth.agent,
      keyPath: '  ',
    );
    final view = rust.connectRequestToView(profile, password: 'pw');
    expect(
      (view.host, view.port, view.user, view.path, view.password),
      ('box.lan', 2222, 'me', '/srv', 'pw'),
    );
    expect(view.auth, rust.AuthMethodView.agent);
    expect(view.keyPath, isNull);
    final keyed = rust.connectRequestToView(
      profile.copyWith(auth: ServerAuth.key, keyPath: '~/.ssh/deploy'),
    );
    expect(
      (keyed.auth, keyed.keyPath, keyed.password),
      (
        rust.AuthMethodView.key,
        '~/.ssh/deploy',
        null,
      ),
    );
  });

  test('each question a connection asks reads as its own kind', () {
    final hostKey = rust.networkQuestionFromView(
      question(rust.NetworkQuestionKindView.hostKey),
    );
    expect(
      hostKey,
      const HostKeyQuestion(
        id: 9,
        server: 'sftp://me@box.lan:22',
        host: 'box.lan',
        port: 22,
        algorithm: 'ssh-ed25519',
        fingerprint: 'SHA256:abc',
      ),
    );
    expect(
      rust.networkQuestionFromView(
        question(rust.NetworkQuestionKindView.password),
      ),
      const PasswordQuestion(
        id: 9,
        server: 'sftp://me@box.lan:22',
        user: 'me',
        retry: true,
      ),
    );
    expect(
      rust.networkQuestionFromView(
        question(rust.NetworkQuestionKindView.passphrase),
      ),
      const PassphraseQuestion(
        id: 9,
        server: 'sftp://me@box.lan:22',
        keyPath: '/k/id_ed25519',
        retry: true,
      ),
    );
    final prompts = rust.networkQuestionFromView(
      question(
        rust.NetworkQuestionKindView.keyboardInteractive,
        prompts: const [
          rust.PromptView(text: 'Code:', echo: false),
          rust.PromptView(text: 'Name:', echo: true),
        ],
      ),
    );
    expect(
      prompts,
      const PromptsQuestion(
        id: 9,
        server: 'sftp://me@box.lan:22',
        name: 'Two factors',
        instructions: 'Use your token',
        prompts: [('Code:', false), ('Name:', true)],
      ),
    );
  });

  test('an operation across the network names its servers', () {
    final view = rust.networkOperationToView(
      const OperationRequest(
        kind: OpKind.move,
        sources: ['/srv/a'],
        destination: '/home',
        sourceServer: 'ftp://files.lan:21',
        newName: 'b',
        conflicts: ConflictPolicy.keepBoth,
        preserveAttributes: false,
      ),
    );
    expect(view.sourceServer, 'ftp://files.lan:21');
    expect(view.destinationServer, isNull);
    expect(
      (view.destination, view.newName, view.preserveAttributes),
      (
        '/home',
        'b',
        false,
      ),
    );
  });

  test('a server open, with its state', () {
    final status = rust.serverStatusFromView(
      const rust.ServerStateView(
        server: 'davs://nas.lan:443',
        display: 'davs://nas.lan',
        state: rust.ConnectionStateView.lost,
      ),
    );
    expect(
      status,
      const ServerStatus(
        server: 'davs://nas.lan:443',
        display: 'davs://nas.lan',
        state: ServerState.lost,
      ),
    );
  });
}
