import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:monitoring/monitoring.dart';
import 'package:network_service/testing.dart';
import 'package:operations_service/operations_service.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:preferences_service/preferences_service.dart';

class _Files extends Mock implements FileRepository {}

class _Operations extends Mock implements OperationsService {}

const box = 'sftp://me@box.lan:22';
const home = Location.native('/home');
const srv = Location.remote(server: box, path: '/srv');

FileEntry _file(String dir, String name) => FileEntry(
  name: name,
  path: dir == '/' ? '/$name' : '$dir/$name',
  kind: EntryKind.file,
  isDir: false,
  size: 1,
);

FileEntry _dir(String dir, String name) => FileEntry(
  name: name,
  path: dir == '/' ? '/$name' : '$dir/$name',
  kind: EntryKind.directory,
  isDir: true,
);

/// Folders on disk and on the one server, read as the core would: a
/// server's only while it is connected.
class _World {
  final connected = <String>{};
  final folders = <Location, List<FileEntry>>{
    home: [_file('/home', 'a.txt')],
    const Location.native('/'): [_dir('/', 'home')],
    srv: [_dir('/srv', 'www'), _file('/srv', 'index.html')],
    const Location.remote(server: box, path: '/srv/www'): [
      _file('/srv/www', 'b.css'),
    ],
  };
  final opened = <String, Location>{};

  /// Reads that fail once as replaced by a later one.
  final superseded = <Location>{};

  Listing list(String id, Location location) {
    if (superseded.remove(location)) {
      throw const FerryxException(FerryxErrorKind.cancelled, 'replaced');
    }
    final server = location.server;
    if (server != null && !connected.contains(server)) {
      throw FerryxException(FerryxErrorKind.notConnected, server);
    }
    final entries = folders[location];
    if (entries == null) {
      throw FerryxException(FerryxErrorKind.notFound, location.path);
    }
    opened[id] = location;
    return Listing(location: location, entries: entries);
  }
}

void main() {
  late _Files files;
  late _Operations operations;
  late PreferencesService preferences;
  late FakeNetworkService network;
  late StreamController<OperationProgress> progress;
  late _World world;
  late List<String> asked;
  late bool answer;
  late PanelCubit cubit;

  setUpAll(() {
    registerFallbackValue(home);
    registerFallbackValue(const ListingOptions());
    registerFallbackValue(
      const OperationRequest(kind: OpKind.calcSizes, sources: []),
    );
  });

  setUp(() async {
    files = _Files();
    operations = _Operations();
    network = FakeNetworkService();
    progress = StreamController<OperationProgress>.broadcast();
    world = _World();
    asked = [];
    answer = true;
    preferences = await PreferencesService.create(
      storage: InMemoryPreferencesStorage(),
    );
    when(
      () => files.directoryChanges,
    ).thenAnswer((_) => const Stream<String>.empty());
    when(() => files.openListing(any(), any(), any())).thenAnswer(
      (inv) async => world.list(
        inv.positionalArguments[0] as String,
        inv.positionalArguments[1] as Location,
      ),
    );
    when(() => files.refreshListing(any())).thenAnswer((inv) async {
      final id = inv.positionalArguments[0] as String;
      return world.list(id, world.opened[id]!);
    });
    when(() => files.closeListing(any())).thenAnswer((_) async {});
    when(() => files.isArchive(any())).thenReturn(false);
    when(() => operations.progress).thenAnswer((_) => progress.stream);
    when(() => operations.start(any())).thenAnswer((_) async => 7);
    when(() => operations.forget(any())).thenAnswer((_) async {});
    cubit = PanelCubit(
      side: PanelSide.left,
      files: files,
      operations: operations,
      preferences: preferences,
      logger: Logger(),
      network: network,
      connectServer: (server) async {
        asked.add(server);
        if (answer) {
          world.connected.add(server);
          network.setState(server, ServerState.connected);
        }
        return answer;
      },
    );
  });

  tearDown(() async {
    await cubit.close();
    await progress.close();
    await preferences.dispose();
    await network.dispose();
  });

  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  PanelTabState tab() => cubit.state.active!;

  List<String> names() => [for (final r in tab().rows) r.name];

  group('a tab on a server', () {
    test('restored, it waits unread; nothing is asked at the start', () async {
      await cubit.start(
        const SavedPanel(tabs: [SavedTab(location: srv)]),
        home,
      );
      expect(asked, isEmpty);
      expect(tab().location, srv);
      expect(tab().listing, isNull);
      expect(tab().error?.kind, FerryxErrorKind.notConnected);
      expect(tab().history, [srv]);
      expect(cubit.state.serverStateOf(tab()), ServerState.closed);
    });

    test('Reconnect (and ⌘R) connects, then reads the folder', () async {
      await cubit.start(
        const SavedPanel(tabs: [SavedTab(location: srv)]),
        home,
      );
      await cubit.refresh();
      expect(asked, [box]);
      expect(tab().error, isNull);
      expect(names(), ['www', 'index.html']);
      expect(cubit.state.serverStateOf(tab()), ServerState.connected);
    });

    test('gone to from the disk: connected to first', () async {
      await cubit.start(null, home);
      await cubit.open(srv);
      expect(asked, [box]);
      expect(tab().location, srv);
      expect(tab().history, [home, srv]);
      // Already open: no second question.
      await cubit.open(const Location.remote(server: box, path: '/srv/www'));
      expect(asked, [box]);
      expect(names(), ['b.css']);
    });

    test(
      'a connection given up leaves the tab where it was, quietly',
      () async {
        answer = false;
        await cubit.start(null, home);
        await cubit.open(srv);
        expect(asked, [box]);
        expect(tab().location, home);
        expect(tab().loading, isFalse);
        expect(tab().error, isNull);
        expect(names(), ['a.txt']);
      },
    );

    test('a read replaced by a later one says nothing', () async {
      await cubit.start(null, home);
      world.superseded.add(srv);
      // The first read is given up for the second, which shows.
      await Future.wait([
        cubit.open(srv),
        cubit.open(const Location.remote(server: box, path: '/srv/www')),
      ]);
      expect(tab().error, isNull);
      expect(tab().loading, isFalse);
      expect(names(), ['b.css']);
      world.superseded.add(tab().location);
      await cubit.refresh();
      expect(tab().error, isNull);
    });

    test('disconnected, its tabs go back to where they were on disk', () async {
      await cubit.start(null, home);
      await cubit.open(srv);
      await cubit.newTab(location: srv);
      expect(cubit.state.tabs.map((t) => t.location), [srv, srv]);
      network.setState(box, ServerState.closed);
      await settle();
      expect(cubit.state.tabs.map((t) => t.location), [home, home]);
      expect(cubit.state.servers, isEmpty);
    });

    test('a connection that dropped is shown, and the tab stays', () async {
      await cubit.start(null, home);
      await cubit.open(srv);
      network.setState(box, ServerState.lost);
      await settle();
      expect(cubit.state.serverStateOf(tab()), ServerState.lost);
      expect(tab().location, srv);
    });
  });

  group('operations on a server', () {
    setUp(() async {
      await cubit.start(null, home);
      await cubit.open(srv);
      clearInteractions(files);
    });

    test('one that ends reads the tabs on its server again', () async {
      progress.add(
        const OperationProgress(
          id: 3,
          kind: OpKind.copy,
          state: OpState.done,
          sources: ['/home/a.txt'],
          destination: '$box/srv',
        ),
      );
      await settle();
      verify(() => files.refreshListing(tab().id)).called(1);
      // One on another server's same path does not.
      progress.add(
        const OperationProgress(
          id: 4,
          kind: OpKind.copy,
          state: OpState.done,
          sources: ['/home/a.txt'],
          destination: 'sftp://me@box.lan:2222/srv',
        ),
      );
      await settle();
      verifyNever(() => files.refreshListing(any()));
    });

    test('folder sizes go over the network, named by their server', () async {
      await cubit.calcSizes();
      final request =
          verify(() => operations.start(captureAny())).captured.single
              as OperationRequest;
      expect(request.kind, OpKind.calcSizes);
      expect(request.sources, ['/srv/www']);
      expect(request.sourceServer, box);
      progress.add(
        const OperationProgress(
          id: 7,
          kind: OpKind.calcSizes,
          state: OpState.done,
          sizes: [FolderSize(path: '$box/srv/www', bytes: 4096)],
        ),
      );
      await settle();
      expect(tab().folderSizes, {'www': 4096});
    });

    test('renaming in place goes to the server', () async {
      when(() => files.renameAt(any(), any())).thenAnswer(
        (_) async => const Location.remote(server: box, path: '/srv/home.html'),
      );
      cubit.moveCursorTo(1);
      cubit.startRenaming();
      expect(tab().renaming, 1);
      final error = await cubit.commitRename('home.html');
      expect(error, isNull);
      verify(
        () => files.renameAt(
          const Location.remote(server: box, path: '/srv/index.html'),
          'home.html',
        ),
      ).called(1);
    });
  });
}
