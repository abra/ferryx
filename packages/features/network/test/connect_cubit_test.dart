import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_feature/network_feature.dart';
import 'package:network_service/testing.dart';

const web = ServerProfile(
  id: 'web',
  name: 'Web',
  protocol: ServerProtocol.sftp,
  host: 'web.example.com',
  user: 'deploy',
  path: '/srv/www',
  auth: ServerAuth.key,
  keyPath: '~/.ssh/deploy',
);

const nas = ServerProfile(
  id: 'nas',
  protocol: ServerProtocol.dav,
  host: 'nas.lan',
);

void main() {
  late FakeNetworkService service;
  late List<List<ServerProfile>> saved;
  late List<String> recorded;

  setUp(() {
    service = FakeNetworkService();
    saved = [];
    recorded = [];
  });

  ConnectCubit cubit({
    List<ServerProfile> servers = const [web, nas],
    List<String> recent = const [],
    String address = '',
  }) => ConnectCubit(
    service: service,
    servers: servers,
    onServersChanged: saved.add,
    recent: recent,
    onRecent: recorded.add,
    initialAddress: address,
  );

  group('the address and the list', () {
    test('starts on the first saved server, its address in the field', () {
      final c = cubit();
      expect(c.state.cursor, 0);
      expect(c.state.address, 'sftp://deploy@web.example.com/srv/www');
      expect(c.state.parsed?.protocol, ServerProtocol.sftp);
      expect(c.state.insecure, isFalse);
      expect(c.state.canConnect, isTrue);
    });

    test('an empty list starts with nothing to connect to', () {
      final c = cubit(servers: const []);
      expect(c.state.cursor, -1);
      expect(c.state.canConnect, isFalse);
    });

    test('the arrows walk the saved servers, then the recent addresses', () {
      final c = cubit(recent: const ['ftp://files.lan', 'dav://nas.lan']);
      // An address already saved is not listed twice.
      expect(c.state.recent, ['ftp://files.lan']);
      c.moveCursor(1);
      expect(c.state.selectedServer, nas);
      expect(c.state.address, 'dav://nas.lan');
      expect(c.state.insecure, isTrue);
      c.moveCursor(1);
      expect(c.state.selectedRecent, 'ftp://files.lan');
      expect(c.state.address, 'ftp://files.lan');
      c.moveCursor(5);
      expect(c.state.cursor, 2);
      c.moveCursor(-9);
      expect(c.state.cursor, 0);
    });

    test('what does not read as an address says so', () {
      final c = cubit()..typeAddress('gopher://x');
      expect(c.state.invalid, isTrue);
      expect(c.state.parsed, isNull);
      expect(c.state.canConnect, isFalse);
      c.typeAddress('ftps://me@files.lan:2121/pub');
      expect(c.state.invalid, isFalse);
      expect(c.state.parsed?.port, 2121);
      expect(c.state.insecure, isFalse);
    });
  });

  group('connecting', () {
    test('a saved server goes with its way of logging in', () async {
      final c = cubit();
      await c.connect();
      expect(service.connected.single, web);
      expect(c.state.connection?.home, '/srv/www');
      expect(recorded, isEmpty);
    });

    test(
      'an address typed goes as typed; its password once, never kept',
      () async {
        final c = cubit(address: 'ftp://me:pw@files.lan/pub');
        String? password;
        service.onConnect = (profile, given) async {
          password = given;
          return const ServerConnection(
            server: 'ftp://me@files.lan:21',
            display: 'ftp://me@files.lan',
            home: '/pub',
            protocol: ServerProtocol.ftp,
            secure: false,
          );
        };
        expect(c.state.parsed!.user, 'me');
        expect(c.state.insecure, isTrue);
        await c.connect();
        expect(service.connected.single.host, 'files.lan');
        expect(service.connected.single.auth, ServerAuth.automatic);
        expect(password, 'pw');
        // What the recent list keeps has no password in it.
        expect(recorded, ['ftp://me@files.lan/pub']);
        expect(c.state.connection?.server, 'ftp://me@files.lan:21');
      },
    );

    blocTest<ConnectCubit, ConnectState>(
      'a failure stays to be read, a cancel says nothing',
      build: () {
        service.onConnect = (profile, _) async => throw const FerryxException(
          FerryxErrorKind.authFailed,
          'me@web did not accept the login',
        );
        return cubit();
      },
      act: (c) => c.connect(),
      skip: 1,
      expect: () => [
        isA<ConnectState>()
            .having((s) => s.connecting, 'connecting', isFalse)
            .having((s) => s.error?.kind, 'error', FerryxErrorKind.authFailed),
      ],
    );

    test('a cancel gives the attempt up and leaves no error', () async {
      final never = Completer<ServerConnection>();
      service.onConnect = (profile, _) => never.future;
      final c = cubit();
      final connecting = c.connect();
      expect(c.state.connecting, isTrue);
      expect(c.state.connectingTo, 'sftp://deploy@web.example.com');
      expect(c.state.canConnect, isFalse);
      c.cancel();
      await connecting;
      expect(service.cancelled, 1);
      expect(c.state.connecting, isFalse);
      expect(c.state.error, isNull);
      expect(c.state.connection, isNull);
    });
  });

  group('saved servers', () {
    test('added, edited and removed, each change handed on', () {
      final c = cubit();
      const added = ServerProfile(
        id: 'new',
        protocol: ServerProtocol.ftps,
        host: 'files.lan',
      );
      c.addServer(added);
      expect(saved.last, [web, nas, added]);
      expect(c.state.selectedServer, added);
      expect(c.state.address, 'ftps://files.lan');
      c.updateServer(added.copyWith(user: 'me'));
      expect(saved.last.last.user, 'me');
      expect(c.state.address, 'ftps://me@files.lan');
      c.removeServer('web');
      expect(saved.last.map((s) => s.id), ['nas', 'new']);
      expect(c.state.cursor, 0);
      c
        ..removeServer('nas')
        ..removeServer('new');
      expect(c.state.servers, isEmpty);
      expect(c.state.cursor, -1);
    });

    test('an address typed becomes a server to save', () {
      final c = cubit()..typeAddress('sftp://me@box.lan:2200/home/me');
      final server = c.serverFromAddress('id1')!;
      expect(server.id, 'id1');
      expect(
        (server.host, server.port, server.user, server.path),
        ('box.lan', 2200, 'me', '/home/me'),
      );
      // The protocol's own port is saved as the default.
      c.typeAddress('sftp://box.lan');
      expect(c.serverFromAddress('id2')!.port, 0);
    });

    test('forgetting a password asks the keychain by the server key', () async {
      final c = cubit();
      expect(await c.forgetPassword(web), isNull);
      expect(service.forgotten, ['sftp://deploy@web.example.com:22']);
    });
  });
}
