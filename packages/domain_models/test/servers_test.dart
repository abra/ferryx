import 'package:domain_models/domain_models.dart';
import 'package:test/test.dart';

void main() {
  group('ServerKey', () {
    test('reads a key and shows it as a person reads it', () {
      final key = ServerKey.parse('sftp://me@host.lan:22')!;
      expect(key.protocol, ServerProtocol.sftp);
      expect((key.user, key.host, key.port), ('me', 'host.lan', 22));
      expect(key.displayRoot, 'sftp://me@host.lan');
      expect(key.urlOf('/srv/www'), 'sftp://me@host.lan/srv/www');
      expect(key.urlOf('/'), 'sftp://me@host.lan/');

      final other = ServerKey.parse('ftp://files.lan:2121')!;
      expect(other.user, '');
      expect(other.displayRoot, 'ftp://files.lan:2121');

      final v6 = ServerKey.parse('davs://me%40mail.com@[::1]:443')!;
      expect(v6.user, 'me@mail.com');
      expect(v6.host, '::1');
      expect(v6.displayRoot, 'davs://me@mail.com@[::1]');
    });

    test('anything else is no key', () {
      expect(ServerKey.parse('/Users/me'), isNull);
      expect(ServerKey.parse('gopher://host:70'), isNull);
      expect(ServerKey.parse('sftp://host'), isNull);
      expect(ServerKey.parse('sftp://:22'), isNull);
    });
  });

  group('ServerProfile', () {
    const profile = ServerProfile(
      id: 'a1',
      name: 'Web',
      protocol: ServerProtocol.sftp,
      host: 'Web.Example.com',
      port: 2222,
      user: 'deploy',
      path: '/srv/www',
      auth: ServerAuth.key,
      keyPath: '~/.ssh/id_ed25519',
    );

    test('goes to the preferences and back, never with a password', () {
      final json = profile.toJson();
      expect(json.keys, isNot(contains('password')));
      expect(ServerProfile.fromJson(json), profile);
      expect(ServerProfile.fromJson({'id': 'x'}), isNull);
      expect(ServerProfile.fromJson('nope'), isNull);
      // A server saved by a later version keeps what this one knows.
      expect(
        ServerProfile.fromJson({
          'id': 'b',
          'host': 'h',
          'protocol': 'ftp',
          'auth': 'quantum',
        })!.auth,
        ServerAuth.automatic,
      );
    });

    test('names itself and its address', () {
      expect(profile.label, 'Web');
      expect(profile.copyWith(name: '  ').label, 'Web.Example.com');
      expect(profile.displayRoot, 'sftp://deploy@web.example.com:2222');
      expect(profile.copyWith(port: 0).effectivePort, 22);
      expect(
        profile.copyWith(port: 22).displayRoot,
        'sftp://deploy@web.example.com',
      );
    });
  });

  group('Location on a server', () {
    const root = Location.remote(server: 'sftp://me@host.lan:22');

    test('walks up and down', () {
      expect(root.isRemote && root.isRemoteRoot, isTrue);
      expect(root.isNative, isFalse);
      expect(root.parent, isNull);
      expect(root.name, 'host.lan');
      expect(root.display, 'sftp://me@host.lan/');
      final deep = root.join('srv').join('www');
      expect(
        deep,
        const Location.remote(
          server: 'sftp://me@host.lan:22',
          path: '/srv/www',
        ),
      );
      expect(deep.name, 'www');
      expect(deep.display, 'sftp://me@host.lan/srv/www');
      expect(deep.parent, root.join('srv'));
      expect(deep.ancestry, [root, root.join('srv'), deep]);
    });

    test('goes to the preferences and back', () {
      final deep = root.join('a#b').join('ü c');
      expect(Location.decode(deep.encode()), deep);
      expect(Location.decode(root.encode()), root);
      expect(Location.decode('remote:not a key#/x'), isNull);
      expect(
        Location.decode('remote:ftp://h:21'),
        const Location.remote(server: 'ftp://h:21'),
      );
    });
  });

  test('what is typed for a login never shows when printed', () {
    const address = ServerAddress(
      protocol: ServerProtocol.ftp,
      host: 'files.lan',
      port: 21,
      key: 'ftp://me@files.lan:21',
      display: 'ftp://me@files.lan',
      user: 'me',
      password: 'hunter2',
    );
    expect('$address', isNot(contains('hunter2')));
    expect('$address', contains('files.lan'));
    const answer = NetworkAnswer(accept: true, texts: ['hunter2']);
    expect('$answer', isNot(contains('hunter2')));
  });

  test('errors that a connection may cure', () {
    expect(FerryxErrorKind.notConnected.needsConnection, isTrue);
    expect(FerryxErrorKind.connectionLost.needsConnection, isTrue);
    expect(FerryxErrorKind.authFailed.needsConnection, isFalse);
    expect(FerryxErrorKind.hostKeyChanged.needsConnection, isFalse);
    expect(FerryxErrorKind.notFound.needsConnection, isFalse);
  });
}
