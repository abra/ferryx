import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:monitoring/monitoring.dart';
import 'package:operations_service/operations_service.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:panels_feature/src/panel/panel_row.dart';
import 'package:panels_feature/src/workspace/tag_menu.dart';
import 'package:preferences_service/preferences_service.dart';

class _Files extends Mock implements FileRepository {}

class _Operations extends Mock implements OperationsService {}

void main() {
  final en = lookupFerryxLocalizations(const Locale('en'));
  const red = FileTag('Red', color: 6);
  const work = FileTag('work');

  FileEntry file(String name, {List<FileTag> tags = const []}) => FileEntry(
    name: name,
    path: '/home/$name',
    kind: EntryKind.file,
    isDir: false,
    tags: tags,
  );

  group('the tag menu', () {
    test('checks a tag all targets have, dashes one some have', () {
      final targets = [
        file('a', tags: [red, work]),
        file('b', tags: [red]),
      ];
      final choices = tagChoices(
        targets: targets,
        folderRows: [
          file('c', tags: const [FileTag('Alpha', color: 4)]),
        ],
        localName: en.tagColorName,
      );
      TagChoice named(String name) =>
          choices.firstWhere((c) => c.tag.name == name);
      // Finder's seven first, in its order, then the named ones sorted.
      expect(choices.take(7).map((c) => c.tag.color), [6, 7, 5, 2, 4, 3, 1]);
      expect(choices.skip(7).map((c) => c.tag.name), ['Alpha', 'work']);
      expect(named('Red').state, TagState.on);
      expect(named('work').state, TagState.mixed);
      expect(named('Blue').state, TagState.off);
      expect(named('Alpha').state, TagState.off);
    });

    test('a pick turns a tag on for all, or off when all had it', () {
      final on = TagChoice(
        tag: const FileTag('Red', color: 6),
        state: TagState.on,
        standard: true,
      );
      expect(on.edit.$1, isEmpty);
      expect(on.edit.$2, ['Red', 'Red']);
      final mixed = TagChoice(
        tag: work,
        state: TagState.mixed,
        standard: false,
      );
      expect(mixed.edit.$1, [work]);
      expect(mixed.edit.$2, isEmpty);
    });

    test('a standard tag is known by its English Finder name too', () {
      final ru = lookupFerryxLocalizations(const Locale('ru'));
      final choices = tagChoices(
        targets: [
          file('a', tags: const [FileTag('Red', color: 6)]),
        ],
        folderRows: const [],
        localName: ru.tagColorName,
      );
      final redChoice = choices.firstWhere((c) => c.tag.color == 6);
      expect(redChoice.tag.name, ru.tagColorRed);
      expect(redChoice.state, TagState.on);
      expect(choices.length, 7, reason: 'not listed again as a named tag');
    });

    test(':tag adds and takes off, by colour names in either language', () {
      final (add, remove) = parseTagCommand(
        'red, Work, -grey, -old, gray',
        localName: en.tagColorName,
        folderRows: [
          file('x', tags: const [FileTag('work', color: 2)]),
        ],
      );
      expect(add, [
        const FileTag('Red', color: 6),
        const FileTag('work', color: 2),
        const FileTag('Gray', color: 1),
      ]);
      expect(remove, ['Gray', 'Gray', 'old']);
      final (none, nothing) = parseTagCommand(
        ' , - ',
        localName: en.tagColorName,
        folderRows: const [],
      );
      expect(none, isEmpty);
      expect(nothing, isEmpty);
    });
  });

  group('rows', () {
    testWidgets('dots follow the name; the reader hears the tags', (
      tester,
    ) async {
      final entry = file(
        'report.pdf',
        tags: const [FileTag('Red', color: 6), work, FileTag('Blue', color: 4)],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(AppPlatformStyle.macos),
          localizationsDelegates: FerryxLocalizations.localizationsDelegates,
          supportedLocales: FerryxSupportedLocales.locales,
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: Builder(
                builder: (context) => Column(
                  children: [
                    RowName(
                      entry: entry,
                      look: const RowLook(
                        cursor: false,
                        active: true,
                        selected: false,
                        match: null,
                      ),
                    ),
                    Text(rowSemanticsLabel(context, entry)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final dots = tester.widget<AppTagDots>(find.byType(AppTagDots));
      expect(dots.colors, [6, 4], reason: 'an uncoloured tag has no dot');
      // Right after the name, not at the row's end.
      final nameRight = tester.getTopRight(find.text('report.pdf')).dx;
      final dotsLeft = tester.getTopLeft(find.byType(AppTagDots)).dx;
      expect(dotsLeft - nameRight, lessThan(AppSpacing.md));
      expect(
        find.text(
          en.tagsRowLabel(
            'report.pdf',
            en.tagNames(['Red', 'work', 'Blue']),
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('the panel', () {
    late _Files files;
    late _Operations operations;
    late PreferencesService preferences;
    late StreamController<String> changes;
    late PanelCubit cubit;
    const home = Location.native('/home');

    setUpAll(() {
      registerFallbackValue(home);
      registerFallbackValue(const ListingOptions());
    });

    setUp(() async {
      files = _Files();
      operations = _Operations();
      changes = StreamController<String>.broadcast();
      preferences = await PreferencesService.create(
        storage: InMemoryPreferencesStorage(),
      );
      final listing = Listing(
        location: home,
        entries: [file('a.txt'), file('b.txt')],
        watched: true,
      );
      when(() => files.directoryChanges).thenAnswer((_) => changes.stream);
      when(
        () => files.openListing(any(), any(), any()),
      ).thenAnswer((_) async => listing);
      when(
        () => files.refreshListing(any()),
      ).thenAnswer((_) async => listing);
      when(() => files.closeListing(any())).thenAnswer((_) async {});
      when(() => files.isArchive(any())).thenReturn(false);
      when(() => files.listingTags(any())).thenAnswer(
        (_) async => {
          '/home/a.txt': const [red],
        },
      );
      when(
        () => operations.progress,
      ).thenAnswer((_) => const Stream<OperationProgress>.empty());
      cubit = PanelCubit(
        side: PanelSide.left,
        files: files,
        operations: operations,
        preferences: preferences,
        logger: Logger(),
        readTags: true,
      );
      await cubit.start(null, home);
      await Future<void>.delayed(Duration.zero);
    });

    tearDown(() async {
      await cubit.close();
      await changes.close();
      await preferences.dispose();
    });

    List<List<FileTag>> tags() => [
      for (final r in cubit.state.active!.rows) r.tags,
    ];

    test('tags come after the listing, and stay through a refresh', () async {
      expect(tags(), [
        [red],
        <FileTag>[],
      ]);
      // A refresh shows the dots it had until the tags are read anew.
      final read = Completer<Map<String, List<FileTag>>>();
      when(() => files.listingTags(any())).thenAnswer((_) => read.future);
      await cubit.refresh();
      expect(tags().first, [red]);
      read.complete({
        '/home/a.txt': const [red, work],
      });
      await Future<void>.delayed(Duration.zero);
      expect(tags().first, [red, work]);
    });

    test('an edit shows at once, an emptied list too', () {
      cubit.applyTags({
        '/home/a.txt': const [],
        '/home/b.txt': const [work],
      });
      expect(tags(), [
        <FileTag>[],
        [work],
      ]);
    });

    test('without the capability no tags are asked for', () async {
      final plain = PanelCubit(
        side: PanelSide.right,
        files: files,
        operations: operations,
        preferences: preferences,
        logger: Logger(),
      );
      clearInteractions(files);
      await plain.start(null, home);
      await Future<void>.delayed(Duration.zero);
      verifyNever(() => files.listingTags(any()));
      await plain.close();
    });
  });
}
