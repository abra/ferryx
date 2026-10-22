import 'dart:async';

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
import 'package:operations_service/operations_service.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

class _Files extends Mock implements FileRepository {}

class _Operations extends Mock implements OperationsService {}

/// A flat view in a panel: each row's folder after its name, the capsule
/// in the footer, Esc and the capsule back to the folder.
void main() {
  const home = Location.native('/home');
  const platform = TargetPlatform.macOS;
  final en = lookupFerryxLocalizations(const Locale('en'));
  late _Files files;
  late _Operations operations;
  late PreferencesService preferences;
  late PanelCubit cubit;
  late FocusNode focus;

  /// The current walk's batches; each walk has its own stream.
  late StreamController<FlatBatch> batches;
  late List<StreamController<FlatBatch>> walks;

  FileEntry row(String folder, String name) => FileEntry(
    name: name,
    path: '/home/$folder/$name',
    kind: EntryKind.file,
    isDir: false,
    size: 1,
    folder: folder,
    extension: 'txt',
  );

  setUpAll(() {
    registerFallbackValue(home);
    registerFallbackValue(const ListingOptions());
  });

  setUp(() async {
    files = _Files();
    operations = _Operations();
    walks = [];
    preferences = await PreferencesService.create(
      storage: InMemoryPreferencesStorage(),
    );
    when(
      () => files.directoryChanges,
    ).thenAnswer((_) => const Stream<String>.empty());
    when(() => files.openListing(any(), any(), any())).thenAnswer(
      (_) async => const Listing(
        location: home,
        entries: [
          FileEntry(
            name: 'deep',
            path: '/home/deep',
            kind: EntryKind.directory,
            isDir: true,
          ),
        ],
      ),
    );
    when(() => files.closeListing(any())).thenAnswer((_) async {});
    when(() => files.isArchive(any())).thenReturn(false);
    when(() => files.openFlatListing(any(), any(), any())).thenAnswer((
      _,
    ) async {
      batches = StreamController<FlatBatch>();
      walks.add(batches);
      return FlatStart(
        listing: const Listing(location: home, entries: []),
        generation: 1,
        batches: batches.stream,
      );
    });
    when(
      () => files.sortFlatListing(any(), any(), any()),
    ).thenAnswer((_) async => const [0, 1]);
    when(
      () => operations.progress,
    ).thenAnswer((_) => const Stream<OperationProgress>.empty());
    cubit = PanelCubit(
      side: PanelSide.left,
      files: files,
      operations: operations,
      preferences: preferences,
      logger: Logger(),
    );
    await cubit.start(null, home);
    focus = FocusNode(debugLabel: 'panel');
  });

  tearDown(() async {
    focus.dispose();
    for (final walk in walks) {
      await walk.close();
    }
    await cubit.close();
    await preferences.dispose();
  });

  Future<void> pump(WidgetTester tester, {int layout = 2}) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    cubit.setLayout(layout);
    final map = ShortcutMap.defaults(platform);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        localizationsDelegates: FerryxLocalizations.localizationsDelegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: Scaffold(
          body: CommandShortcuts(
            shortcuts: map.toShortcuts(
              platform,
              scopes: const {CommandScope.panel},
            ),
            child: BlocProvider<PanelCubit>.value(
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
      ),
    );
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pump();
  }

  Future<void> enterFlat(WidgetTester tester) async {
    await cubit.toggleFlatView();
    batches.add(
      FlatBatch(
        generation: 1,
        entries: [row('deep/er', 'one.txt'), row('deep', 'two.txt')],
        count: 2,
      ),
    );
    await tester.pump();
    batches.add(const FlatBatch(generation: 1, done: true, count: 2));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('rows say their folders; the footer says flat and counts files', (
    tester,
  ) async {
    await pump(tester);
    await enterFlat(tester);
    await tester.pumpAndSettle();
    expect(find.text('one.txt'), findsOneWidget);
    expect(find.text('deep/er'), findsOneWidget);
    // The footer names the cursor's row with its folder.
    expect(find.text('deep/er/one.txt'), findsOneWidget);
    expect(find.text('deep'), findsOneWidget);
    expect(find.text(en.flatCapsule), findsOneWidget);
    expect(find.textContaining(en.flatFileCount(2)), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(
        RegExp(RegExp.escape(en.flatRowLabel('one.txt', 'deep/er'))),
      ),
      findsWidgets,
    );
    semantics.dispose();
  });

  testWidgets('a long folder gives way before the name', (tester) async {
    await pump(tester);
    await cubit.toggleFlatView();
    final folder = List.filled(30, 'very-long-folder').join('/');
    batches.add(
      FlatBatch(
        generation: 1,
        entries: [row(folder, 'name-that-stays-whole.txt')],
        count: 1,
      ),
    );
    // The walk goes on: its spinner turns, so no settling.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    // The name keeps its extension; the folder gives way.
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '') == 'name-that-stays-whole.txt',
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Esc and the capsule go back to the folder', (tester) async {
    await pump(tester);
    await enterFlat(tester);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(cubit.state.active!.isFlat, isFalse);
    expect(cubit.state.active!.focused?.name, 'deep');

    await enterFlat(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.flatCapsule));
    await tester.pumpAndSettle();
    expect(cubit.state.active!.isFlat, isFalse);
  });

  testWidgets('brief mode keeps the folders in its cells', (tester) async {
    await pump(tester, layout: 0);
    await enterFlat(tester);
    await tester.pumpAndSettle();
    expect(find.text('deep/er'), findsOneWidget);
  });
}
