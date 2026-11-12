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
import 'package:panels_feature/src/panel/rows_brief.dart';
import 'package:panels_feature/src/panel/panel_row.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

class _Files extends Mock implements FileRepository {}

class _Operations extends Mock implements OperationsService {}

/// Brief mode over a folder of [count] files.
void main() {
  const home = Location.native('/home');
  const platform = TargetPlatform.macOS;
  late _Files files;
  late PanelCubit cubit;
  late PreferencesService preferences;
  late FocusNode focus;

  Listing listing(int count) => Listing(
    location: home,
    entries: [
      for (var i = 0; i < count; i++)
        FileEntry(
          name: 'file ${'x' * (i % 17)} $i.txt',
          path: '/home/file $i.txt',
          kind: EntryKind.file,
          isDir: false,
          size: 1,
          extension: 'txt',
        ),
    ],
    watched: true,
  );

  setUpAll(() {
    registerFallbackValue(home);
    registerFallbackValue(const ListingOptions());
  });

  Future<void> start(int count) async {
    files = _Files();
    final operations = _Operations();
    preferences = await PreferencesService.create(
      storage: InMemoryPreferencesStorage(),
    );
    when(
      () => files.directoryChanges,
    ).thenAnswer((_) => const Stream<String>.empty());
    when(
      () => files.openListing(any(), any(), any()),
    ).thenAnswer((_) async => listing(count));
    when(() => files.closeListing(any())).thenAnswer((_) async {});
    when(() => files.isArchive(any())).thenReturn(false);
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
  }

  tearDown(() async {
    focus.dispose();
    await cubit.close();
    await preferences.dispose();
  });

  Future<void> pump(WidgetTester tester, int layout) async {
    tester.view.physicalSize = const Size(900, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    cubit.setLayout(layout);
    final map = ShortcutMap.forUser(platform);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        localizationsDelegates: FerryxSupportedLocales.delegates,
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

  group('1500 names', () {
    setUp(() => start(1500));

    testWidgets('names sized to their columns are measured once: the cursor '
        'moving does not measure them again', (tester) async {
      // Medium: columns as wide as their names.
      await pump(tester, 1);
      final measured = RowsBrief.debugMeasures;
      final offsets = RowsBrief.debugOffsetBuilds;
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      expect(cubit.state.active!.cursor, 5);
      expect(RowsBrief.debugMeasures, measured);
      expect(RowsBrief.debugOffsetBuilds, offsets);
    });
  });

  group('20000 names', () {
    setUp(() => start(20000));

    testWidgets('the columns\' widths are known to the list: End lands on '
        'the last name building only the columns in view', (
      tester,
    ) async {
      // Short: thirds of the panel.
      await pump(tester, 0);
      final built = RowsBrief.debugColumnsBuilt;
      final clock = Stopwatch()..start();
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      // Laid out one by one, the 1400 columns before it take a minute.
      expect(RowsBrief.debugColumnsBuilt - built, lessThan(20));
      expect(clock.elapsed, lessThan(const Duration(seconds: 10)));
      expect(cubit.state.active!.cursor, 19999);
      // A long name may be ellipsized. Check the actual file row and its
      // position, rather than assuming the whole label fits in a column.
      final last = find.byWidgetPredicate(
        (w) =>
            w is RowName &&
            w.entry.name == 'file ${'x' * (19999 % 17)} 19999.txt',
      );
      expect(last, findsOneWidget);
      expect(
        tester.getRect(find.byType(RowsBrief)).contains(tester.getCenter(last)),
        isTrue,
      );
    });
  });
}
