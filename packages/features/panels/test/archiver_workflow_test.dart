import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:panels_feature/panels_feature.dart';

import 'support/workspace_harness.dart';

void main() {
  const seven = ArchiveTool(
    name: '7-Zip',
    path: '/usr/local/bin/7zz',
    engine: ArchiverEngine.sevenZip,
  );
  const tar = ArchiveTool(
    name: 'tar',
    path: '/usr/bin/tar',
    engine: ArchiverEngine.tar,
  );
  const zstd = ArchiveTool(
    name: 'zstd',
    path: '/opt/homebrew/bin/zstd',
    engine: ArchiverEngine.zstd,
  );
  final en = lookupFerryxLocalizations(const Locale('en'));
  late WorkspaceHarness h;
  setUpAll(WorkspaceHarness.registerFallbacks);
  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp(vim: true);
    h.addFolder('/home/docs', ['archive.zip', 'archive.cab']);
    when(() => h.files.archiveInfo(any())).thenAnswer((call) async {
      if ((call.positionalArguments[0] as String).endsWith('.cab')) {
        throw const FerryxException(FerryxErrorKind.unsupported, 'CAB');
      }
      return const ArchiveInfo(format: 'zip', topLevelCount: 2);
    });
  });
  tearDown(() => h.tearDown());
  PanelCubit panel(WidgetTester tester) =>
      tester.element(find.byType(PanelView).first).read<PanelCubit>();
  Future<void> pump(WidgetTester tester) async {
    await h.pump(
      tester,
      loadArchivers: (manual, {refresh = false}) async => [seven, tar, zstd],
    );
    final cubit = panel(tester);
    cubit.moveCursorTo(
      cubit.state.active!.rows.indexWhere((r) => r.name == 'a.txt'),
    );
    await tester.pumpAndSettle();
  }

  Future<void> vimCommand(WidgetTester tester, String text) async {
    await h.press(
      tester,
      LogicalKeyboardKey.semicolon,
      shift: true,
      character: ':',
    );
    await tester.enterText(find.byType(EditableText), text);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  }

  testWidgets('Vim stream compression applies the selected program defaults', (
    tester,
  ) async {
    await pump(tester);
    unawaited(
      h.preferences.update(
        (p) => p.copyWith(
          archivers: p.archivers.copyWith(
            options: {
              zstd.id: const ArchiverOptions(
                level: 15,
                threads: 2,
                arguments: ['--long=27'],
              ),
            },
          ),
        ),
      ),
    );
    await vimCommand(tester, 'pack zst');
    await tester.tap(find.text(en.actionCompress));
    await tester.pumpAndSettle();
    expect(h.started.single.archiveType, ArchiveType.zstd);
    expect(h.started.single.archiver, zstd);
    expect(
      h.started.single.archiveOptions,
      const ArchiverOptions(level: 15, threads: 2, arguments: ['--long=27']),
    );
  });

  testWidgets(
    'multiple files use a TAR container and prefer the dedicated compressor',
    (tester) async {
      await pump(tester);
      panel(tester).selectOnly({'a.txt', 'archive.zip'});
      await tester.pumpAndSettle();
      await vimCommand(tester, 'pack zst');
      final format = tester.widget<AppPopupButton<ArchiveType>>(
        find.byType(AppPopupButton<ArchiveType>),
      );
      expect(format.value, ArchiveType.tarZstd);
      expect(format.items.any((item) => item.$1.singleFileOnly), isFalse);
      await tester.tap(find.text(en.actionCompress));
      await tester.pumpAndSettle();
      expect(h.started.single.sources, hasLength(2));
      expect(h.started.single.archiver, zstd);
    },
  );

  testWidgets(
    'macOS compression needs no Fn; changing format chooses its engine and extension',
    (tester) async {
      await pump(tester);
      await h.press(tester, LogicalKeyboardKey.keyC, control: true, meta: true);
      expect(find.text(en.archiveFormatLabel), findsOneWidget);
      final format = tester.widget<AppPopupButton<ArchiveType>>(
        find.byType(AppPopupButton<ArchiveType>),
      );
      expect(
        format.items.map((item) => item.$1),
        containsAll([
          ArchiveType.zip,
          ArchiveType.sevenZip,
          ArchiveType.tarGzip,
        ]),
      );
      format.onChanged(ArchiveType.sevenZip);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .controller
            .text,
        'a.7z',
      );
      await tester.tap(find.text(en.actionCompress));
      await tester.pumpAndSettle();
      expect(h.started.single.archiveType, ArchiveType.sevenZip);
      expect(h.started.single.archiver, seven);
      expect(h.preferences.current.archivers.format, ArchiveType.sevenZip);
    },
  );

  testWidgets(
    'Vim zc and :pack use the same dialog; Unicode ZIP passwords choose the built-in engine',
    (tester) async {
      await pump(tester);
      await h.press(tester, LogicalKeyboardKey.keyZ, character: 'z');
      await h.press(tester, LogicalKeyboardKey.keyC, character: 'c');
      var engine = tester.widget<AppPopupButton<String>>(
        find.byType(AppPopupButton<String>),
      );
      engine.onChanged(seven.id);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, 'секрет');
      await tester.pumpAndSettle();
      expect(find.text(en.archiveZipUnicodeFallback), findsOneWidget);
      await tester.tap(find.text(en.actionCompress));
      await tester.pumpAndSettle();
      expect(h.started.single.archiver, isNull);
      expect(h.started.single.password, 'секрет');
      await vimCommand(tester, 'pack tar.gz');
      expect(
        tester
            .widget<AppPopupButton<ArchiveType>>(
              find.byType(AppPopupButton<ArchiveType>),
            )
            .value,
        ArchiveType.tarGzip,
      );
      await tester.tap(find.text(en.actionCompress));
      await tester.pumpAndSettle();
      expect(h.started.last.archiver, tar);
      expect(h.started.last.newName, 'a.tar.gz');
    },
  );

  testWidgets('macOS extraction uses the chosen program and remembers it', (
    tester,
  ) async {
    await pump(tester);
    final cubit = panel(tester);
    cubit.moveCursorTo(
      cubit.state.active!.rows.indexWhere((r) => r.name == 'archive.zip'),
    );
    await tester.pumpAndSettle();
    await h.press(tester, LogicalKeyboardKey.keyE, control: true, meta: true);
    tester
        .widget<AppPopupButton<String>>(find.byType(AppPopupButton<String>))
        .onChanged(seven.id);
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.archiveExtractAction));
    await tester.pumpAndSettle();
    expect(h.started.single.kind, OpKind.extract);
    expect(h.started.single.archiver, seven);
    expect(h.preferences.current.archivers.extractTool, seven.id);
  });

  testWidgets(
    ':unpack recognizes an external format and selects an available reader',
    (tester) async {
      await pump(tester);
      final cubit = panel(tester);
      cubit.moveCursorTo(
        cubit.state.active!.rows.indexWhere((r) => r.name == 'archive.cab'),
      );
      await tester.pumpAndSettle();
      await vimCommand(tester, 'unpack /dest');
      expect(h.started.single.destination, '/dest');
      expect(h.started.single.archiver, seven);
    },
  );

  for (final direct in [false, true]) {
    testWidgets(
      '${direct ? ':unpack' : 'Vim zx'} chooses a reader for the whole mixed selection',
      (tester) async {
        await pump(tester);
        panel(tester).selectOnly({'archive.zip', 'archive.cab'});
        await tester.pumpAndSettle();
        if (direct) {
          await vimCommand(tester, 'unpack /dest');
        } else {
          await h.press(tester, LogicalKeyboardKey.keyZ, character: 'z');
          await h.press(tester, LogicalKeyboardKey.keyX, character: 'x');
          await tester.tap(find.text(en.archiveExtractAction));
          await tester.pumpAndSettle();
        }
        expect(h.started.single.sources, hasLength(2));
        expect(h.started.single.archiver, seven);
      },
    );
  }
}
