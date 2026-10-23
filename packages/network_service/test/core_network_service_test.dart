import 'dart:io';

import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' show FerryxBackend;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoring/monitoring.dart';
import 'package:network_service/network_service.dart';

/// The host library `make core` builds.
final _library = File(
  '../../rust/target/debug/'
  '${Platform.isMacOS
      ? 'libferryx_api.dylib'
      : Platform.isWindows
      ? 'ferryx_api.dll'
      : 'libferryx_api.so'}',
);

void main() {
  final skip = _library.existsSync() ? null : 'run `make core` first';
  late CoreNetworkService service;

  setUpAll(() async {
    if (skip != null) return;
    final backend = await FerryxBackend.initialize(
      externalLibrary: ExternalLibrary.open(_library.path),
    );
    service = CoreNetworkService(backend: backend, logger: Logger());
  });

  group('addresses read by the core', () {
    test('each scheme, its port, user and folder', () {
      final sftp = service.parse('sftp://me@Box.lan:2200/home/me');
      expect(
        (sftp.protocol, sftp.host, sftp.port, sftp.user, sftp.path),
        (ServerProtocol.sftp, 'box.lan', 2200, 'me', '/home/me'),
      );
      expect(sftp.key, 'sftp://me@box.lan:2200');
      expect(sftp.display, 'sftp://me@box.lan:2200');

      final https = service.parse('https://cloud.example.com/remote.php/dav');
      expect((https.protocol, https.port), (ServerProtocol.davs, 443));
      final dav = service.parse('dav://nas.lan');
      expect(
        (dav.protocol, dav.port, dav.protocol.secure),
        (
          ServerProtocol.dav,
          80,
          false,
        ),
      );
      final ftps = service.parse('ftps://files.lan');
      expect((ftps.protocol, ftps.port), (ServerProtocol.ftps, 21));
    });

    test('a bare host takes the protocol given; a password stays apart', () {
      final bare = service.parse('box.lan', fallback: ServerProtocol.ftp);
      expect((bare.protocol, bare.port), (ServerProtocol.ftp, 21));
      final withPassword = service.parse('ftp://me:p%40ss@files.lan');
      expect(withPassword.password, 'p@ss');
      expect(withPassword.key, isNot(contains('p@ss')));
    });

    test('a user that is not ASCII is part of the key, encoded', () {
      final address = service.parse('sftp://дима@box.lan');
      expect(address.user, 'дима');
      expect(ServerKey.parse(address.key)?.user, 'дима');
    });

    test('what is not an address is a typed error', () {
      for (final text in ['gopher://x', 'sftp://', 'sftp://host:99999']) {
        expect(
          () => service.parse(text),
          throwsA(
            isA<FerryxException>().having(
              (e) => e.kind,
              'kind',
              FerryxErrorKind.invalidName,
            ),
          ),
          reason: text,
        );
      }
    });

    test('a saved server has the key of its address', () {
      const profile = ServerProfile(
        id: 'a',
        protocol: ServerProtocol.davs,
        host: 'NAS.lan',
        user: 'me',
      );
      expect(service.keyOf(profile), service.parse(profile.address).key);
    });
  }, skip: skip);

  group('connections', () {
    test('a port nobody listens on is unreachable, quickly', () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      final attempt = service.connect(
        ServerProfile(
          id: 'x',
          protocol: ServerProtocol.ftp,
          host: '127.0.0.1',
          port: port,
          user: 'me',
        ),
        password: 'pw',
      );
      await expectLater(
        attempt.result,
        throwsA(
          isA<FerryxException>().having(
            (e) => e.kind,
            'kind',
            FerryxErrorKind.hostUnreachable,
          ),
        ),
      );
      expect(service.servers, isEmpty);
    });

    test('an attempt given up ends as cancelled', () async {
      // A listener that never answers: the login waits for its greeting.
      final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(silent.close);
      final held = <Socket>[];
      silent.listen(held.add);
      addTearDown(() {
        for (final s in held) {
          s.destroy();
        }
      });
      final attempt = service.connect(
        ServerProfile(
          id: 'y',
          protocol: ServerProtocol.ftp,
          host: '127.0.0.1',
          port: silent.port,
          user: 'me',
        ),
        password: 'pw',
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      attempt.cancel();
      await expectLater(
        attempt.result,
        throwsA(
          isA<FerryxException>().having(
            (e) => e.kind,
            'kind',
            FerryxErrorKind.cancelled,
          ),
        ),
      );
    });
  }, skip: skip);
}
