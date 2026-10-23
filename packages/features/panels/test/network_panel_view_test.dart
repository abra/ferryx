import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:monitoring/monitoring.dart';
import 'package:network_service/testing.dart';
import 'package:operations_service/operations_service.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:panels_feature/src/dialogs/simple_dialogs.dart';
import 'package:panels_feature/src/workspace/context_menu.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

class _Files extends Mock implements FileRepository {}

class _Operations extends Mock implements OperationsService {}

const box = 'ftp://me@box.lan:21';
const srv = Location.remote(server: box, path: '/srv');
const home = Location.native('/home');

void main() {
  const platform = TargetPlatform.macOS;
  final en = lookupFerryxLocalizations(const Locale('en'));
  late _Files files;
  late _Operations operations;
  late PreferencesService preferences;
  late FakeNetworkService network;
  late PanelCubit cubit;
  late FocusNode focus;
  late bool connected;

  Listing listing(Location location) => Listing(
    location: location,
    entries: [
      const FileEntry(
        name: 'index.html',
        path: '/srv/index.html',
        kind: EntryKind.file,
        isDir: false,
        size: 120,
      ),
    ],
  );

  setUpAll(() {
    registerFallbackValue(home);
    registerFallbackValue(const ListingOptions());
  });

  setUp(() async {
    files = _Files();
    operations = _Operations();
    connected = false;
    preferences = await PreferencesService.create(
      storage: InMemoryPreferencesStorage(),
    );
    when(
      () => files.directoryChanges,
    ).thenAnswer((_) => const Stream<String>.empty());
    when(() => files.openListing(any(), any(), any())).thenAnswer((inv) async {
      final location = inv.positionalArguments[1] as Location;
      if (location.isRemote && !connected) {
        throw const FerryxException(FerryxErrorKind.notConnected, box);
      }
      return listing(location);
    });
    when(() => files.closeListing(any())).thenAnswer((_) async {});
    when(() => files.isArchive(any())).thenReturn(false);
    when(
      () => operations.progress,
    ).thenAnswer((_) => const Stream<OperationProgress>.empty());
    focus = FocusNode(debugLabel: 'panel');
  });

  /// The panel, made in the test's own zone so the server's changes reach
  /// it as the test pumps.
  void build() {
    network = FakeNetworkService();
    cubit = PanelCubit(
      side: PanelSide.left,
      files: files,
      operations: operations,
      preferences: preferences,
      logger: Logger(),
      network: network,
      connectServer: (server) async {
        connected = true;
        network.setState(server, ServerState.connected);
        return true;
      },
    );
  }

  tearDown(() async {
    focus.dispose();
    await cubit.close();
    await preferences.dispose();
    await network.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final map = ShortcutMap.defaults(platform);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: Scaffold(
          body: BlocProvider<PanelCubit>.value(
            value: cubit,
            child: PanelView(
              focusNode: focus,
              active: true,
              layouts: PanelLayout.defaults,
              showTabBarAlways: false,
              quickSearchModifier: QuickSearchModifier.none,
              vimMode: false,
              leftInset: 0,
              rightInset: 0,
              shortcutMap: map,
              hooks: PanelHooks(
                onActivate: () {},
                onOpenFile: (_) {},
                onContextMenu: (_) {},
                onPanelMenu: (_) {},
                onSwitchPanel: () {},
                onShowPreview: () {},
                onGoHome: () {},
                onGoRoot: () {},
                onVimYank: () {},
                onVimCut: () {},
                onVimPaste: () {},
                onVimCancelRegister: () {},
                onVimSetMark: (_) {},
                onVimGoMark: (_) {},
                onVimCommand: (_) {},
                onVimComplete: (_) async => const [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a tab left on a server: not connected yet, a state with '
      'Connect in the strip, not a fault', (tester) async {
    build();
    await cubit.start(const SavedPanel(tabs: [SavedTab(location: srv)]), home);
    await pump(tester);
    // What is the matter, then of what: the server's address.
    expect(find.text(en.errorNotConnected), findsOneWidget);
    expect(find.text(srv.display), findsOneWidget);
    expect(find.text(en.networkCapsuleClosed), findsOneWidget);
    // FTP crosses the network unencrypted: an open lock.
    expect(find.byIcon(AppIcons.unlocked), findsOneWidget);
    expect(find.text('FTP'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, en.networkConnect),
      findsOneWidget,
    );
    expect(find.byIcon(AppIcons.warning), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, en.networkConnect));
    await tester.pumpAndSettle();
    expect(cubit.state.active!.rows.map((r) => r.name), ['index.html']);
    expect(find.text(en.networkCapsuleClosed), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, en.networkConnect),
      findsNothing,
    );
  });

  testWidgets('the root crumb names who on which host', (tester) async {
    build();
    connected = true;
    network.setState(box, ServerState.connected);
    await cubit.start(
      const SavedPanel(
        tabs: [SavedTab(location: Location.remote(server: box))],
      ),
      home,
    );
    await pump(tester);
    expect(find.text('me@box.lan'), findsOneWidget);
    expect(find.byIcon(AppIcons.server), findsOneWidget);
  });

  testWidgets('a server row offers what a server does', (tester) async {
    build();
    late List<AppMenuEntry<AppCommand>> entries;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: Builder(
          builder: (context) {
            entries = rowMenuEntries(
              context,
              entry: listing(srv).entries.single,
              location: srv,
              severalSelected: false,
              map: ShortcutMap.defaults(platform),
            );
            return const SizedBox();
          },
        ),
      ),
    );
    final commands = {
      for (final e in entries)
        if (e case AppMenuAction<AppCommand>(:final value)) value,
    };
    expect(
      commands,
      containsAll([
        AppCommand.openItem,
        AppCommand.internalViewer,
        AppCommand.copyTo,
        AppCommand.moveTo,
        AppCommand.renameInPlace,
        AppCommand.deletePermanently,
        AppCommand.copyItemPath,
      ]),
    );
    for (final native in [
      AppCommand.openWith,
      AppCommand.revealInFileManager,
      AppCommand.quickLook,
      AppCommand.share,
      AppCommand.moveToTrash,
      AppCommand.compress,
      AppCommand.fileAttributes,
      AppCommand.duplicate,
    ]) {
      expect(commands, isNot(contains(native)), reason: '$native');
    }
  });

  testWidgets('deleting on a server: no Trash, said why; Return cancels', (
    tester,
  ) async {
    build();
    late Future<DeleteChoice?> result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => result = showDeleteDialog(
              context,
              names: const ['index.html'],
              trashDefault: false,
              trashAvailable: false,
              note: en.networkNoTrash,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(en.networkNoTrash), findsOneWidget);
    expect(find.text(en.deleteToTrash), findsNothing);
    expect(find.text(en.deletePermanently), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });
}
