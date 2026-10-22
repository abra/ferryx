import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/src/dialogs/archive_password_dialog.dart';
import 'package:panels_feature/src/dialogs/extract_dialog.dart';

void main() {
  final en = lookupFerryxLocalizations(const Locale('en'));

  Future<void> host(WidgetTester tester, Widget dialog) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        localizationsDelegates: FerryxLocalizations.localizationsDelegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: Scaffold(body: Center(child: dialog)),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the dialog through [showExtractDialog] and answers its result
  /// once it closes.
  Future<Future<ExtractChoice?>> open(
    WidgetTester tester, {
    required List<ExtractSource> archives,
    Future<List<String>> Function(String text)? complete,
    Future<FerryxException?> Function(String, String)? check,
    int? members,
  }) async {
    late Future<ExtractChoice?> result;
    await host(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => result = showExtractDialog(
            context,
            archives: archives,
            defaultDestination: '/dest',
            complete: complete ?? (_) async => const [],
            checkPassword: check ?? (_, _) async => null,
            members: members,
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  AppCheckbox checkbox(WidgetTester tester) =>
      tester.widget<AppCheckbox>(find.byType(AppCheckbox));

  testWidgets('one archive of one item goes straight into the destination', (
    tester,
  ) async {
    final result = await open(
      tester,
      archives: [
        ExtractSource(
          name: 'site.tar.gz',
          path: '/a/site.tar.gz',
          info: Future.value(
            const ArchiveInfo(format: 'tar.gz', topLevelCount: 1),
          ),
        ),
      ],
    );
    expect(find.text(en.archiveExtractOneTitle('site.tar.gz')), findsOneWidget);
    expect(find.text(en.archiveIntoFolder('site')), findsOneWidget);
    expect(checkbox(tester).value, isFalse);
    expect(find.text(en.archivePasswordLabel), findsNothing);
    await tester.tap(find.text(en.archiveExtractAction));
    await tester.pumpAndSettle();
    final choice = await result;
    expect(choice?.destination, '/dest');
    expect(choice?.intoFolders, isFalse);
    expect(choice?.password, isNull);
  });

  testWidgets('an archive of many items wants a folder; the user decides', (
    tester,
  ) async {
    final info = Completer<ArchiveInfo?>();
    final result = await open(
      tester,
      archives: [
        ExtractSource(name: 'a.zip', path: '/a.zip', info: info.future),
        ExtractSource(
          name: 'b.zip',
          path: '/b.zip',
          info: Future.value(
            const ArchiveInfo(format: 'zip', topLevelCount: 1),
          ),
        ),
      ],
    );
    expect(find.text(en.archiveExtractManyTitle(2)), findsOneWidget);
    info.complete(const ArchiveInfo(format: 'zip', topLevelCount: 3));
    await tester.pumpAndSettle();
    expect(checkbox(tester).value, isTrue);
    await tester.tap(find.text(en.archiveIntoFolders));
    await tester.pump();
    expect(checkbox(tester).value, isFalse);
    // Return submits from the field.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect((await result)?.intoFolders, isFalse);
  });

  testWidgets('a wrong password is said in the dialog, a right one closes it', (
    tester,
  ) async {
    final tried = <String>[];
    final result = await open(
      tester,
      archives: [
        ExtractSource(
          name: 'locked.7z',
          path: '/locked.7z',
          info: Future.value(
            const ArchiveInfo(format: '7z', topLevelCount: 2, encrypted: true),
          ),
        ),
      ],
      check: (archive, password) async {
        tried.add(password);
        return password == 'right'
            ? null
            : const FerryxException(FerryxErrorKind.wrongPassword, 'no');
      },
    );
    final field = find.widgetWithText(TextField, '').last;
    expect(find.text(en.archivePasswordLabel), findsOneWidget);
    await tester.enterText(field, 'wrong');
    await tester.tap(find.text(en.archiveExtractAction));
    await tester.pumpAndSettle();
    expect(find.text(en.archiveWrongPasswordFor('locked.7z')), findsOneWidget);
    expect(find.byType(ExtractDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'right');
    await tester.tap(find.text(en.archiveExtractAction));
    await tester.pumpAndSettle();
    expect(tried, ['wrong', 'right']);
    final choice = await result;
    expect(choice?.password, 'right');
    expect(choice?.intoFolders, isTrue);
  });

  testWidgets('members of an archive have no folder option', (tester) async {
    await open(
      tester,
      archives: [ExtractSource(name: 'a.zip', path: '/a.zip')],
      members: 3,
    );
    expect(find.text(en.archiveExtractMembersTitle(3)), findsOneWidget);
    expect(find.byType(AppCheckbox), findsNothing);
  });

  testWidgets('Tab completes the destination, then moves on', (tester) async {
    final asked = <String>[];
    await open(
      tester,
      archives: [ExtractSource(name: 'a.zip', path: '/a.zip')],
      complete: (text) async {
        asked.add(text);
        return text == '/dest' ? const [] : ['/data/one/', '/data/two/'];
      },
    );
    final field = find.byType(TextField).first;
    await tester.enterText(field, '/data/');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '/data/one/');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '/data/two/');
    expect(asked, ['/data/']);
  });

  test('completions are the folders under the one typed into', () async {
    Future<List<String>> peek(String folder) async => switch (folder) {
      '/home/me/' => ['Documents', 'Downloads', 'Music'],
      '/work' => ['src', 'Docs'],
      _ => const [],
    };
    expect(
      await completeFolderPath(
        '~/Do',
        home: '/home/me',
        base: '/work',
        peek: peek,
      ),
      ['~/Documents/', '~/Downloads/'],
    );
    expect(
      await completeFolderPath(
        'd',
        home: '/home/me',
        base: '/work',
        peek: peek,
      ),
      ['Docs/'],
    );
    expect(
      await completeFolderPath(
        '~',
        home: '/home/me',
        base: '/work',
        peek: peek,
      ),
      ['~/'],
    );
  });

  test('an archive is named without its archive extensions', () {
    expect(archiveStem('site.tar.gz'), 'site');
    expect(archiveStem('photos.zip'), 'photos');
    expect(archiveStem('log.txt.gz'), 'log.txt');
    expect(archiveStem('README'), 'README');
  });

  testWidgets('the password dialog stays until a password opens the archive', (
    tester,
  ) async {
    late Future<bool> result;
    await host(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => result = showArchivePasswordDialog(
            context,
            name: 'hidden.7z',
            submit: (password) async => password == 'pw'
                ? null
                : const FerryxException(FerryxErrorKind.wrongPassword, ''),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(en.archivePasswordTitle('hidden.7z')), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text(en.archiveWrongPasswordFor('hidden.7z')), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'pw');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });
}
